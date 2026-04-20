import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';

/// Auth state notifier
class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    // Listen to auth state changes
    final authService = ref.read(authServiceProvider);

    authService.authStateChanges.listen((authState) async {
      if (authState.event == AuthChangeEvent.signedOut) {
        state = const AsyncData(null);
      } else if (authState.event == AuthChangeEvent.signedIn) {
        // Set loading state while fetching profile
        state = const AsyncLoading();
        await _loadUserProfile();
      }
    });

    // Initial load
    if (authService.isLoggedIn) {
      return await authService.getCurrentUserProfile();
    }
    return null;
  }

  Future<void> _loadUserProfile() async {
    final authService = ref.read(authServiceProvider);
    final profile = await authService.getCurrentUserProfile();
    state = AsyncData(profile);
  }

  /// Sign in with Google
  Future<UserModel?> signInWithGoogle({UserRole? role}) async {
    state = const AsyncLoading();
    try {
      final authService = ref.read(authServiceProvider);
      final user = await authService.signInWithGoogle(preferredRole: role);
      state = AsyncData(user);
      return user;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    final authService = ref.read(authServiceProvider);
    await authService.signOut();
    state = const AsyncData(null);
  }

  /// Update profile
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? avatarUrl,
    UserRole? role,
  }) async {
    if (state.value == null) return;

    final authService = ref.read(authServiceProvider);
    final updated = await authService.updateUserProfile(
      name: name,
      phone: phone,
      avatarUrl: avatarUrl,
      role: role,
    );
    state = AsyncData(updated);
  }

  /// Delete account
  Future<void> deleteAccount() async {
    final authService = ref.read(authServiceProvider);
    await authService.deleteAccount();
    state = const AsyncData(null);
  }

  /// Refresh profile
  Future<void> refreshProfile() async {
    await _loadUserProfile();
  }
}

/// Auth state provider
final authStateProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(() {
  return AuthNotifier();
});

/// Current user provider (convenience)
final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Is logged in provider
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

/// Is rider provider
final isRiderProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider)?.isRider ?? false;
});

/// Is admin provider
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider)?.isAdmin ?? false;
});
