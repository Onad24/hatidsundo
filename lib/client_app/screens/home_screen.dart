import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../state/state.dart';
import '../../services/update_service.dart';
import '../../widgets/map_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'privacy_policy_screen.dart';

/// Client home screen with map and nearby drivers
class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

// Default fallback location (Tanauan, Batangas - app's home city)
const _defaultLocation = LatLng(14.0864, 121.0159);

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  LatLng? _currentLocation;
  bool _locationError = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();

    // Check for app updates and show privacy policy
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
      _checkPrivacyPolicy();
    });
  }

  Future<void> _checkPrivacyPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenPrivacy = prefs.getBool('has_seen_privacy_policy') ?? false;

    if (!hasSeenPrivacy && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text(
            'Privacy Policy',
            style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'We value your privacy. Please take a moment to read our Privacy Policy to understand how we collect, use, and protect your data.',
            style: TextStyle(fontFamily: 'Outfit'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ),
                );
              },
              child: const Text('Read Policy'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('I Agree'),
            ),
          ],
        ),
      );
      await prefs.setBool('has_seen_privacy_policy', true);
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final updateService = ref.read(updateServiceProvider);
      await updateService.checkForUpdate(context);
    } catch (e) {
      debugPrint('Client update check failed: $e');
    }
  }

  Future<void> _loadCurrentLocation() async {
    try {
      // Apply a 10-second timeout to avoid infinite spinner
      final position = await ref
          .read(currentPositionProvider.future)
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          if (position != null) {
            _currentLocation = LatLng(position.latitude, position.longitude);
          } else {
            // Permission denied or GPS off — use default location
            _currentLocation = _defaultLocation;
            _locationError = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Location fetch failed: $e');
      if (mounted) {
        setState(() {
          // Fallback to default so the map still loads
          _currentLocation = _defaultLocation;
          _locationError = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get your location. Using default map view.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripStateProvider);

    // If there's an active trip, redirect to active trip screen
    if (tripState.hasActiveTrip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/client/trip/${tripState.activeTrip!.id}');
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // Map
          if (_currentLocation != null)
            _NearbyDriversMap(currentLocation: _currentLocation!)
          else
            const Center(child: CircularProgressIndicator()),

          // GPS unavailable warning banner
          if (_locationError)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.location_off, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GPS unavailable — showing default location',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Outfit'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top bar with user info
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Menu / Profile
                  _buildCircleButton(
                    icon: Icons.menu_rounded,
                    onPressed: () => _showDrawer(context),
                  ),
                  const Spacer(),
                  // Notifications
                  _buildCircleButton(
                    icon: Icons.notifications_outlined,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),

          // Bottom sheet with ride request
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.2,
            maxChildSize: 0.5,
            builder: (context, scrollController) {
              return _buildBottomSheet(context, scrollController);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: AppTheme.cardShadow,
      ),
      child: IconButton(
        icon: Icon(icon, color: AppTheme.neutral700),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildBottomSheet(
    BuildContext context,
    ScrollController scrollController,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.neutral300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Greeting
              Text(
                'Hello, ${ref.watch(currentUserProvider)?.name.split(' ').first ?? 'there'}! 👋',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.neutral900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Where would you like to go?',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 14,
                  color: AppTheme.neutral500,
                ),
              ),
              const SizedBox(height: 20),

              // Destination input (tap to go to request screen)
              GestureDetector(
                onTap: () => context.push(Routes.clientRequestRide),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.neutral100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.neutral200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search_rounded, color: AppTheme.neutral400),
                      SizedBox(width: 12),
                      Text(
                        'Enter destination',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 16,
                          color: AppTheme.neutral400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Quick actions
              const Text(
                'Quick actions',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.neutral600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildQuickAction(
                    icon: Icons.history_rounded,
                    label: 'History',
                    onTap: () => context.push(Routes.clientHistory),
                  ),
                  const SizedBox(width: 12),
                  _buildQuickAction(
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    onTap: () => context.push(Routes.clientProfile),
                  ),
                  const SizedBox(width: 12),
                  _buildQuickAction(
                    icon: Icons.help_outline_rounded,
                    label: 'Help',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Help & Support'),
                          content: const Text(
                            'For assistance, please contact support at:\n\nhatidsundo.tanauan@gmail.com',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.neutral100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppTheme.primaryColor),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.neutral700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ClientDrawer(),
    );
  }
}

class _NearbyDriversMap extends ConsumerWidget {
  final LatLng currentLocation;

  const _NearbyDriversMap({required this.currentLocation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearbyDrivers = ref.watch(
      nearbyDriversProvider((
        lat: currentLocation.latitude,
        lng: currentLocation.longitude,
      )),
    );

    return nearbyDrivers.when(
      data: (drivers) =>
          AppMapWidget(initialCenter: currentLocation, drivers: drivers),
      loading: () =>
          AppMapWidget(initialCenter: currentLocation, drivers: const []),
      error: (e, _) =>
          AppMapWidget(initialCenter: currentLocation, drivers: const []),
    );
  }
}

class _ClientDrawer extends ConsumerWidget {
  const _ClientDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.neutral300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // User info
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                  backgroundImage: user?.avatarUrl != null
                      ? NetworkImage(user!.avatarUrl!)
                      : null,
                  child: user?.avatarUrl == null
                      ? Text(
                          user?.name.substring(0, 1).toUpperCase() ?? 'U',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'User',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 13,
                          color: AppTheme.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Menu items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _buildMenuItem(
                  icon: Icons.person_outline_rounded,
                  label: 'My Profile',
                  onTap: () {
                    Navigator.pop(context);
                    context.push(Routes.clientProfile);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.history_rounded,
                  label: 'Trip History',
                  onTap: () {
                    Navigator.pop(context);
                    context.push(Routes.clientHistory);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.payment_rounded,
                  label: 'Payment Methods',
                  onTap: () {},
                ),
                _buildMenuItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    context.push(Routes.clientProfile);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.help_outline_rounded,
                  label: 'Help & Support',
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Help & Support'),
                        content: const Text(
                          'For assistance, please contact support at:\n\nsupport@hatidsundo.com',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(),
                _buildMenuItem(
                  icon: Icons.logout_rounded,
                  label: 'Sign Out',
                  isDestructive: true,
                  onTap: () async {
                    Navigator.pop(context);
                    await ref.read(authStateProvider.notifier).signOut();
                    if (context.mounted) {
                      context.go(Routes.login);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? AppTheme.errorColor : AppTheme.neutral600,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 15,
          color: isDestructive ? AppTheme.errorColor : AppTheme.neutral800,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
