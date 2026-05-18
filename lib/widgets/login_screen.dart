import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hatid_sundo/models/user_model.dart';

import '../core/theme.dart';
import '../core/router.dart';

import '../state/auth_provider.dart';

/// Login screen with Google OAuth
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final authNotifier = ref.read(authStateProvider.notifier);
      // Sign in without specifying role yet
      final user = await authNotifier.signInWithGoogle();

      if (user != null && mounted) {
        // Navigate based on role existence
        if (user.role == UserRole.none) {
          // New user or no role assigned -> Go to role selection
          context.go(Routes.roleSelection);
        } else if (user.isRider) {
          context.go(Routes.riderHome);
        } else if (user.isAdmin) {
          context.go(Routes.adminDashboard);
        } else {
          // Client
          context.go(Routes.clientHome);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo and branding
                _buildHeader(),

                const Spacer(),

                const SizedBox(height: 32),

                // Sign in button
                _buildSignInButton(),

                const SizedBox(height: 16),

                // Terms text
                _buildTermsText(),

                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.elevatedShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset('assets/icons/logo.png', fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Welcome to',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 16,
            color: AppTheme.neutral500,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hatid Sundo',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppTheme.neutral900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Safe and reliable rides at your fingertips',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 14,
            color: AppTheme.neutral500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.neutral900,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            side: const BorderSide(color: AppTheme.neutral200),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google icon placeholder
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppTheme.neutral100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Text(
                        'G',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.neutral600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTermsText() {
    return Text(
      'By continuing, you agree to our Terms of Service and Privacy Policy',
      style: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 12,
        color: AppTheme.neutral400,
      ),
      textAlign: TextAlign.center,
    );
  }
}
