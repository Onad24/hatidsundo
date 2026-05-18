import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../state/auth_provider.dart';

class AdminSidebar extends ConsumerWidget {
  final String activeItem;

  const AdminSidebar({super.key, required this.activeItem});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 250,
      color: AppTheme.neutral900,
      child: Column(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/icons/logo.png',
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Hatid Sundo',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.neutral700, height: 1),

          // Menu items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildMenuItem(
                  context: context,
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isSelected: activeItem == 'Dashboard',
                  route: Routes.adminDashboard,
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.people_rounded,
                  label: 'Rider Approvals',
                  isSelected: activeItem == 'Rider Approvals',
                  route: Routes.adminApprovals,
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.map_rounded,
                  label: 'Live Map',
                  isSelected: activeItem == 'Live Map',
                  route: Routes.adminLiveMap,
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.route_rounded,
                  label: 'Active Trips',
                  isSelected: activeItem == 'Active Trips',
                  route: Routes.adminTrips,
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.chat_rounded,
                  label: 'Messages',
                  isSelected: activeItem == 'Messages',
                  route: Routes.adminMessaging,
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.payments_rounded,
                  label: 'Fee Management',
                  isSelected: activeItem == 'Fee Management',
                  route: Routes.adminFees,
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.calculate_rounded,
                  label: 'Fare Settings',
                  isSelected: activeItem == 'Fare Settings',
                  route: Routes.adminFareSettings,
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.bar_chart_rounded,
                  label: 'Statistics',
                  isSelected: activeItem == 'Statistics',
                  route: Routes.adminStatistics,
                ),
              ],
            ),
          ),

          // Sign out
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildMenuItem(
              context: context,
              icon: Icons.logout_rounded,
              label: 'Sign Out',
              onTap: () async {
                await ref.read(authStateProvider.notifier).signOut();
                if (context.mounted) {
                  context.go(Routes.login);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    bool isSelected = false,
    String? route,
    VoidCallback? onTap,
  }) {
    return Material(
      color: isSelected
          ? AppTheme.primaryColor.withValues(alpha: 0.2)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap ?? () => context.go(route!),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? AppTheme.primaryColor : AppTheme.neutral400,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 14,
                  color: isSelected ? Colors.white : AppTheme.neutral300,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
