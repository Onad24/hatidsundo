import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../state/state.dart';
import '../../widgets/map_widget.dart';

/// Rider home screen with online toggle and ride requests
class RiderHomeScreen extends ConsumerStatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  ConsumerState<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends ConsumerState<RiderHomeScreen> {
  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    final position = await ref.read(currentPositionProvider.future);
    if (position != null && mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(driverOnlineProvider);
    final canGoOnline = ref.watch(canGoOnlineProvider);
    final feeState = ref.watch(riderFeeProvider);
    final tripState = ref.watch(tripStateProvider);
    final pendingTripsAsync = ref.watch(pendingTripsProvider);
    final blockingReason = ref.watch(cannotAcceptReason);

    // If there's an active trip, show navigation
    if (tripState.hasActiveTrip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/rider/trip/${tripState.activeTrip!.id}/navigation');
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // Map
          if (_currentLocation != null)
            AppMapWidget(
              initialCenter: _currentLocation!,
              showUserLocation: true,
            )
          else
            const Center(child: CircularProgressIndicator()),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildCircleButton(
                    icon: Icons.menu_rounded,
                    onPressed: () => _showDrawer(context),
                  ),
                  const Spacer(),
                  // Earnings quick view
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 18,
                          color: AppTheme.successColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₱${feeState.currentWeekFee?.accruedFee.toStringAsFixed(0) ?? '0'}',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Lockout banner (if dues unpaid)
          if (!canGoOnline)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Account Restricted',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Outstanding dues: ₱${feeState.totalOutstanding.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push(Routes.riderFees),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Details'),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Online toggle
                    InkWell(
                      onTap: canGoOnline
                          ? () async {
                              final notifier = ref.read(
                                driverOnlineProvider.notifier,
                              );
                              final success = await notifier.toggleOnline();

                              if (!success && context.mounted) {
                                final error = ref
                                    .read(driverOnlineProvider)
                                    .error;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      error ??
                                          'Failed to go online. Check location permissions.',
                                    ),
                                    backgroundColor: AppTheme.errorColor,
                                  ),
                                );
                              }
                            }
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    driverState.isOnline
                                        ? 'You are online'
                                        : 'You are offline',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: driverState.isOnline
                                          ? AppTheme.successColor
                                          : AppTheme.neutral700,
                                    ),
                                  ),
                                  Text(
                                    driverState.isOnline
                                        ? 'Waiting for ride requests'
                                        : 'Go online to start receiving rides',
                                    style: const TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 13,
                                      color: AppTheme.neutral500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IgnorePointer(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 64,
                                height: 36,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: driverState.isOnline
                                      ? AppTheme.successColor
                                      : canGoOnline
                                      ? AppTheme.neutral300
                                      : AppTheme.neutral200,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: AnimatedAlign(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: driverState.isOnline
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Blocking banner for unapproved or unsettled riders
                    if (blockingReason != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.warningColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.warningColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: AppTheme.warningColor,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                blockingReason,
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 13,
                                  color: AppTheme.warningColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (feeState.hasOutstandingDues)
                              TextButton(
                                onPressed: () => context.push(Routes.riderFees),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'View Fees',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                    // Pending ride requests (when online)
                    if (driverState.isOnline)
                      pendingTripsAsync.when(
                        data: (trips) {
                          if (trips.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: AppTheme.neutral100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    color: AppTheme.neutral400,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Looking for ride requests nearby...',
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontSize: 14,
                                        color: AppTheme.neutral500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ride Requests (${trips.length})',
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.neutral700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...trips.map(
                                (trip) => _buildRideRequestCard(context, trip),
                              ),
                              const SizedBox(height: 8),
                            ],
                          );
                        },
                        loading: () => Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.neutral100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (e, _) => Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.errorColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Error loading rides: $e',
                            style: TextStyle(color: AppTheme.errorColor),
                          ),
                        ),
                      ),

                    // Quick actions
                    Row(
                      children: [
                        _buildQuickAction(
                          icon: Icons.attach_money_rounded,
                          label: 'Earnings',
                          onTap: () => context.push(Routes.riderEarnings),
                        ),
                        const SizedBox(width: 12),
                        _buildQuickAction(
                          icon: Icons.receipt_long_rounded,
                          label: 'Fees',
                          onTap: () => context.push(Routes.riderFees),
                        ),
                        const SizedBox(width: 12),
                        _buildQuickAction(
                          icon: Icons.history_rounded,
                          label: 'History',
                          onTap: () => context.push(Routes.riderHistory),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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

  Widget _buildRideRequestCard(BuildContext context, dynamic trip) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fare and distance
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.successColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '₱${trip.fareEstimated?.toStringAsFixed(0) ?? '0'}',
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${trip.distanceKm?.toStringAsFixed(1) ?? '?'} km',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 14,
                  color: AppTheme.neutral500,
                ),
              ),
              const Spacer(),
              Text(
                '${trip.durationMin?.toStringAsFixed(0) ?? '?'} min',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 14,
                  color: AppTheme.neutral500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Pickup
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppTheme.successColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  trip.pickupAddress ?? 'Pickup location',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 4.5),
            child: SizedBox(
              height: 20,
              child: VerticalDivider(color: AppTheme.neutral300, thickness: 1),
            ),
          ),
          // Destination
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppTheme.errorColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  trip.destAddress ?? 'Destination',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Accept button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                // Check if rider can accept rides
                final reason = ref.read(cannotAcceptReason);
                if (reason != null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(reason),
                        backgroundColor: AppTheme.warningColor,
                        action: ref.read(riderFeeProvider).hasOutstandingDues
                            ? SnackBarAction(
                                label: 'View Fees',
                                textColor: Colors.white,
                                onPressed: () =>
                                    context.push(Routes.riderFees),
                              )
                            : null,
                      ),
                    );
                  }
                  return;
                }
                final success = await ref
                    .read(tripStateProvider.notifier)
                    .acceptRide(trip.id);
                if (success && context.mounted) {
                  // Refresh the pending trips list
                  ref.invalidate(pendingTripsProvider);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ref.read(canAcceptRidesProvider)
                    ? AppTheme.primaryColor
                    : AppTheme.neutral300,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Accept Ride',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _RiderDrawer(),
    );
  }
}

class _RiderDrawer extends ConsumerWidget {
  const _RiderDrawer();

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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                  child: const Icon(Icons.person, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Driver',
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: AppTheme.warningColor,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          const Text('4.8'),
                          const SizedBox(width: 8),
                          Text(
                            '• Active Driver',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 13,
                              color: AppTheme.successColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _buildMenuItem(
                  icon: Icons.attach_money_rounded,
                  label: 'My Earnings',
                  onTap: () {
                    Navigator.pop(context);
                    context.push(Routes.riderEarnings);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Fee Dashboard',
                  onTap: () {
                    Navigator.pop(context);
                    context.push(Routes.riderFees);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.history_rounded,
                  label: 'Trip History',
                  onTap: () {
                    Navigator.pop(context);
                    context.push(Routes.riderHistory);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.directions_car_rounded,
                  label: 'Vehicle Details',
                  onTap: () {},
                ),
                _buildMenuItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () {},
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
