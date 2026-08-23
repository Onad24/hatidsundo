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

// Default fallback location (Tanauan, Leyte - app's home city)
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
            content: Text(
              'Could not get your location. Using default map view.',
            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top floating bar with user greeting and menu
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Menu button
                  _buildGlassCircleButton(
                    icon: Icons.menu_rounded,
                    onPressed: () => _showDrawer(context),
                  ),
                  const Spacer(),
                  // Notification bell
                  _buildGlassCircleButton(
                    icon: Icons.notifications_none_rounded,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),

          // Bottom sheet with ride request & quick actions
          DraggableScrollableSheet(
            initialChildSize: 0.38,
            minChildSize: 0.22,
            maxChildSize: 0.65,
            builder: (context, scrollController) {
              return _buildBottomSheet(context, scrollController);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.neutral200.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: AppTheme.floatingShadow,
      ),
      child: IconButton(
        icon: Icon(icon, color: AppTheme.neutral800, size: 22),
        onPressed: onPressed,
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildBottomSheet(
    BuildContext context,
    ScrollController scrollController,
  ) {
    final user = ref.watch(currentUserProvider);
    final firstName = user?.name.split(' ').first ?? 'there';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.neutral300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Dynamic Greeting with user name
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_getGreeting()}, $firstName 👋',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.neutral900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Ready to ride? Find a driver nearby.',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 14,
                          color: AppTheme.neutral500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // High-End Destination Search Box
              GestureDetector(
                onTap: () => context.push(Routes.clientRequestRide),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.neutral100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.neutral200.withValues(alpha: 0.9),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Where are you heading?',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.neutral700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusFull,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Go',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Quick Action Services Grid
              const Text(
                'Services & Shortcuts',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.neutral800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  _buildServiceTile(
                    title: 'Book Ride',
                    icon: Icons.local_taxi_rounded,
                    gradient: AppTheme.primaryGradient,
                    onTap: () => context.push(Routes.clientRequestRide),
                  ),
                  const SizedBox(width: 12),
                  _buildServiceTile(
                    title: 'Ride History',
                    icon: Icons.receipt_long_rounded,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                    ),
                    onTap: () => context.push(Routes.clientHistory),
                  ),
                  const SizedBox(width: 12),
                  _buildServiceTile(
                    title: 'My Profile',
                    icon: Icons.person_rounded,
                    gradient: AppTheme.emeraldGradient,
                    onTap: () => context.push(Routes.clientProfile),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Trust & Safety Badge Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.06),
                      AppTheme.secondaryColor.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: AppTheme.primaryColor,
                      size: 24,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Safe & Verified Rides',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.neutral800,
                            ),
                          ),
                          Text(
                            'All drivers are verified & trips tracked in real-time.',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12,
                              color: AppTheme.neutral500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceTile({
    required String title,
    required IconData icon,
    required LinearGradient gradient,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: AppTheme.neutral50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.neutral200.withValues(alpha: 0.8),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: gradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.neutral800,
                ),
                textAlign: TextAlign.center,
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
                  onTap: () {
                    Navigator.pop(context);
                    _showPaymentMethodsModal(context);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  onTap: () {
                    Navigator.pop(context);
                    PrivacyPolicyScreen.show(context);
                  },
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

  void _showPaymentMethodsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.payment_rounded,
                      color: AppTheme.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Payment Methods',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.neutral900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildPaymentOption(
                'Cash Payment',
                'Pay directly to driver upon arrival',
                Icons.money_rounded,
                isDefault: true,
              ),
              _buildPaymentOption(
                'GCash',
                'Scan driver QR code or direct number (Soon!)',
                Icons.account_balance_wallet_outlined,
              ),
              _buildPaymentOption(
                'Maya',
                'Pay via Maya QR or transfer (Soon!)',
                Icons.credit_card_rounded,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildPaymentOption(
    String title,
    String subtitle,
    IconData icon, {
    bool isDefault = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDefault
              ? AppTheme.primaryColor.withValues(alpha: 0.05)
              : AppTheme.neutral100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDefault
                ? AppTheme.primaryColor.withValues(alpha: 0.3)
                : AppTheme.neutral200,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDefault ? AppTheme.primaryColor : AppTheme.neutral600,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDefault
                          ? AppTheme.primaryColor
                          : AppTheme.neutral900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      color: AppTheme.neutral600,
                    ),
                  ),
                ],
              ),
            ),
            if (isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Default',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
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
