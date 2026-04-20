import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../core/router.dart';
import '../models/user_model.dart';
import '../state/auth_provider.dart';

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  bool _isLoading = false;

  Future<void> _selectRole(UserRole role) async {
    setState(() => _isLoading = true);
    try {
      if (role == UserRole.rider) {
        // Navigate to driver registration
        context.push(Routes.riderRegister);
      } else {
        // Provide client role and go home
        await ref.read(authStateProvider.notifier).updateProfile(role: role);
        if (mounted) context.go(Routes.clientHome);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const Text(
                  'Choose your journey',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.neutral900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'How would you like to use Hatid Sundo?',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16,
                    color: AppTheme.neutral500,
                  ),
                ),
                const SizedBox(height: 48),

                // Passenger Option
                _buildRoleCard(
                  title: 'Passenger',
                  subtitle: 'Book rides and travel safely',
                  icon: Icons.person_pin_circle_rounded,
                  color: AppTheme.primaryColor,
                  onTap: () => _selectRole(UserRole.client),
                ),
                const SizedBox(height: 16),

                // Driver Option
                _buildRoleCard(
                  title: 'Driver',
                  subtitle: 'Drive and earn money',
                  icon: Icons.directions_car_rounded,
                  color: AppTheme.secondaryColor,
                  onTap: () => _selectRole(UserRole.rider),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.neutral900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        color: AppTheme.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppTheme.neutral400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
