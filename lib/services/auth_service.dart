import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../models/user_model.dart';
import '../core/constants.dart';
import 'supabase_service.dart';

/// Authentication service
class AuthService {
  final SupabaseService _supabaseService;
  final GoogleSignIn _googleSignIn;

  AuthService(this._supabaseService)
    : _googleSignIn = GoogleSignIn(
        clientId: EnvConfig.googleWebClientId,
        scopes: ['email', 'profile'],
      );

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges =>
      _supabaseService.auth.onAuthStateChange;

  /// Get current session
  Session? get currentSession => _supabaseService.auth.currentSession;

  /// Get current user
  User? get currentUser => _supabaseService.currentUser;

  /// Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  /// Sign in with Google
  Future<UserModel?> signInWithGoogle({UserRole? preferredRole}) async {
    try {
      if (kIsWeb) {
        // On web, use Supabase's OAuth redirect flow
        // This navigates away from the app; the session is picked up
        // automatically when the user is redirected back.
        await _supabaseService.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Uri.base.origin,
        );
        // The page will redirect, so we won't reach here.
        // After redirect, Supabase picks up the session automatically.
        return null;
      }

      // On mobile, use google_sign_in package
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null; // User cancelled
      }

      // Get auth details
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw Exception('No ID token received from Google');
      }

      // Sign in to Supabase with Google credentials
      final response = await _supabaseService.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.user == null) {
        throw Exception('Sign in failed');
      }

      // Check if user profile exists, create if not
      final userModel = await _getOrCreateUserProfile(
        response.user!,
        googleUser.displayName ?? 'User',
        preferredRole ?? UserRole.none,
      );

      return userModel;
    } catch (e) {
      debugPrint('Google Sign In Error: $e');
      rethrow;
    }
  }

  /// Get or create user profile
  Future<UserModel> _getOrCreateUserProfile(
    User authUser,
    String displayName,
    UserRole preferredRole,
  ) async {
    // Try to get existing profile
    final existingProfile = await _supabaseService
        .from(AppConstants.usersTable)
        .select()
        .eq('id', authUser.id)
        .maybeSingle();

    if (existingProfile != null) {
      return UserModel.fromJson(existingProfile);
    }

    // Create new profile
    final newProfile = {
      'id': authUser.id,
      'name': displayName,
      'email': authUser.email,
      'role': preferredRole.name,
      'avatar_url': authUser.userMetadata?['avatar_url'],
      'created_at': DateTime.now().toIso8601String(),
    };

    final inserted = await _supabaseService
        .from(AppConstants.usersTable)
        .insert(newProfile)
        .select()
        .single();

    // If rider role, create pending rider profile
    if (preferredRole == UserRole.rider) {
      await _supabaseService.from(AppConstants.ridersProfilesTable).insert({
        'user_id': authUser.id,
        'status': AppConstants.statusPending,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    return UserModel.fromJson(inserted);
  }

  /// Get current user profile
  Future<UserModel?> getCurrentUserProfile() async {
    if (currentUser == null) return null;

    final profile = await _supabaseService
        .from(AppConstants.usersTable)
        .select()
        .eq('id', currentUser!.id)
        .maybeSingle();

    if (profile == null) return null;
    return UserModel.fromJson(profile);
  }

  /// Update user profile
  Future<UserModel> updateUserProfile({
    String? name,
    String? phone,
    String? avatarUrl,
    UserRole? role,
  }) async {
    if (currentUser == null) {
      throw Exception('Not authenticated');
    }

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (name != null) updates['name'] = name;
    if (phone != null) updates['phone'] = phone;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (role != null) updates['role'] = role.name;

    final updated = await _supabaseService
        .from(AppConstants.usersTable)
        .update(updates)
        .eq('id', currentUser!.id)
        .select()
        .single();

    return UserModel.fromJson(updated);
  }

  /// Sign out
  Future<void> signOut() async {
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
    await _supabaseService.auth.signOut();
  }

  /// Delete account
  Future<void> deleteAccount() async {
    // This would typically call an Edge Function for secure deletion
    await _supabaseService.callFunction('delete_account');
    await signOut();
  }
}

/// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  final supabaseService = ref.watch(supabaseServiceProvider);
  return AuthService(supabaseService);
});
