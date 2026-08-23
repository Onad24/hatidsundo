import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../state/state.dart';
import '../../services/update_service.dart';
import '../../widgets/map_widget.dart';
import '../../client_app/screens/privacy_policy_screen.dart';

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

    // Check for app updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  Future<void> _checkForUpdate() async {
    try {
      final updateService = ref.read(updateServiceProvider);
      await updateService.checkForUpdate(context);
    } catch (e) {
      debugPrint('Rider update check failed: $e');
    }
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _buildCircleButton(
                    icon: Icons.menu_rounded,
                    onPressed: () => _showDrawer(context),
                  ),
                  const Spacer(),
                  // Earnings quick view pill
                  GestureDetector(
                    onTap: () => context.push(Routes.riderEarnings),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusFull,
                        ),
                        border: Border.all(color: AppTheme.neutral200),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppTheme.successColor.withValues(
                                alpha: 0.12,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_rounded,
                              size: 14,
                              color: AppTheme.successColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₱${feeState.currentWeekFee?.accruedFee.toStringAsFixed(0) ?? '0'}',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.neutral900,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 10,
                            color: AppTheme.neutral400,
                          ),
                        ],
                      ),
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
                  borderRadius: BorderRadius.circular(16),
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
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Outstanding dues: ₱${feeState.totalOutstanding.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.neutral300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),

                    // Online toggle hero card
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: driverState.isOnline
                            ? AppTheme.successColor.withValues(alpha: 0.08)
                            : AppTheme.neutral100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: driverState.isOnline
                              ? AppTheme.successColor.withValues(alpha: 0.3)
                              : AppTheme.neutral200,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Status indicator dot
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: driverState.isOnline
                                  ? AppTheme.successColor
                                  : AppTheme.neutral400,
                              shape: BoxShape.circle,
                              boxShadow: driverState.isOnline
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.successColor.withValues(
                                          alpha: 0.6,
                                        ),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driverState.isOnline
                                      ? 'You are Online'
                                      : 'You are Offline',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: driverState.isOnline
                                        ? AppTheme.successColor
                                        : AppTheme.neutral800,
                                  ),
                                ),
                                Text(
                                  driverState.isOnline
                                      ? 'Ready to accept incoming rides'
                                      : 'Slide toggle to start receiving rides',
                                  style: const TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 12,
                                    color: AppTheme.neutral500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Toggle switch
                          GestureDetector(
                            onTap: canGoOnline
                                ? () async {
                                    final notifier = ref.read(
                                      driverOnlineProvider.notifier,
                                    );
                                    final success = await notifier
                                        .toggleOnline();

                                    if (!success && context.mounted) {
                                      final error = ref
                                          .read(driverOnlineProvider)
                                          .error;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: 60,
                              height: 34,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: driverState.isOnline
                                    ? AppTheme.successColor
                                    : canGoOnline
                                    ? AppTheme.neutral300
                                    : AppTheme.neutral200,
                                borderRadius: BorderRadius.circular(17),
                              ),
                              child: AnimatedAlign(
                                duration: const Duration(milliseconds: 250),
                                alignment: driverState.isOnline
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Blocking banner for unapproved or unsettled riders
                    if (blockingReason != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.warningColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
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
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 13,
                                  color: AppTheme.warningColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (feeState.hasOutstandingDues)
                              TextButton(
                                onPressed: () => context.push(Routes.riderFees),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'View Fees',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 18,
                              ),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: AppTheme.neutral100,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.radar_rounded,
                                    color: AppTheme.primaryColor,
                                    size: 24,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Searching for ride requests nearby...',
                                      style: TextStyle(
                                        fontFamily: 'Outfit',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.neutral600,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 18,
                                    height: 18,
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
                              Row(
                                children: [
                                  const Text(
                                    'Available Rides',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.neutral800,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor,
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusFull,
                                      ),
                                    ),
                                    child: Text(
                                      '${trips.length}',
                                      style: const TextStyle(
                                        fontFamily: 'Outfit',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
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
                            borderRadius: BorderRadius.circular(16),
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
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Error loading rides: $e',
                            style: const TextStyle(color: AppTheme.errorColor),
                          ),
                        ),
                      ),

                    // Quick actions
                    Row(
                      children: [
                        _buildQuickAction(
                          icon: Icons.account_balance_wallet_rounded,
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
        border: Border.all(color: AppTheme.neutral200.withValues(alpha: 0.8)),
        boxShadow: AppTheme.floatingShadow,
      ),
      child: IconButton(
        icon: Icon(icon, color: AppTheme.neutral800, size: 22),
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
            color: AppTheme.neutral50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.neutral200.withValues(alpha: 0.8),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppTheme.primaryColor, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.neutral800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _vehicleTypeLabel(String type) {
    switch (type) {
      case 'motorcycle':
        return 'Motorcycle';
      case 'sedan':
        return 'Sedan (2-4)';
      case 'suv':
        return 'SUV (6-8)';
      default:
        return type;
    }
  }

  Widget _buildRideRequestCard(BuildContext context, dynamic trip) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 16,
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
                  gradient: AppTheme.emeraldGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.successColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '₱${trip.fareEstimated?.toStringAsFixed(0) ?? '0'}',
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (trip.vehicleType != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Text(
                    _vehicleTypeLabel(trip.vehicleType!),
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                '${trip.distanceKm?.toStringAsFixed(1) ?? '?'} km',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.neutral700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '~${trip.durationMin?.toStringAsFixed(0) ?? '?'} mins',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
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
                decoration: const BoxDecoration(
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
                    fontWeight: FontWeight.w600,
                    color: AppTheme.neutral800,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: SizedBox(
              height: 16,
              child: VerticalDivider(
                color: AppTheme.neutral300,
                thickness: 1.5,
              ),
            ),
          ),
          // Destination
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: AppTheme.errorColor,
                size: 14,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trip.destAddress ?? 'Destination',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.neutral800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Accept button
          Container(
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.elevatedShadow,
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
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
                                onPressed: () => context.push(Routes.riderFees),
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
                if (context.mounted) {
                  if (success) {
                    // Refresh the pending trips list
                    ref.invalidate(pendingTripsProvider);
                  } else {
                    // Show error (likely race condition - trip already taken)
                    final error = ref.read(tripStateProvider).error;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          error ?? 'Failed to accept ride. Try another one.',
                        ),
                        backgroundColor: AppTheme.errorColor,
                      ),
                    );
                    // Refresh list to remove the stale trip card
                    ref.invalidate(pendingTripsProvider);
                  }
                }
              },
              child: const Text(
                'Accept Ride',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
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
                  onTap: () {
                    Navigator.pop(context);
                    _showVehicleDetailsModal(context, ref);
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
                    _showSettingsModal(context);
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

  void _showVehicleDetailsModal(BuildContext context, WidgetRef ref) {
    final user = ref.read(currentUserProvider);
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
                      Icons.directions_car_rounded,
                      color: AppTheme.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registered Vehicle',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.neutral900,
                          ),
                        ),
                        Text(
                          'Verified Hatid Sundo Partner',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 13,
                            color: AppTheme.successColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildVehicleInfoTile('Owner / Driver', user?.name ?? 'Registered Partner', Icons.person_outline),
              _buildVehicleInfoTile('Vehicle Type', 'Motorcycle / Sedan', Icons.two_wheeler_rounded),
              _buildVehicleInfoTile('Status', 'Active & Approved', Icons.verified_user_outlined, isHighlight: true),
              _buildVehicleInfoTile('Region', 'Tanauan City, Leyte', Icons.location_on_outlined),
              const SizedBox(height: 20),
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
                    'Close',
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

  static Widget _buildVehicleInfoTile(String label, String value, IconData icon, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.neutral100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.neutral200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isHighlight ? AppTheme.successColor : AppTheme.neutral600),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                color: AppTheme.neutral600,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isHighlight ? AppTheme.successColor : AppTheme.neutral900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsModal(BuildContext context) {
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
                      color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.settings_outlined,
                      color: AppTheme.secondaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Driver Settings',
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined, color: AppTheme.primaryColor),
                title: const Text('Trip Request Sound', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                subtitle: const Text('Play alert chime for incoming rides', style: TextStyle(fontFamily: 'Outfit', fontSize: 12)),
                trailing: Switch(value: true, onChanged: (v) {}, activeThumbColor: AppTheme.primaryColor),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.map_outlined, color: AppTheme.secondaryColor),
                title: const Text('Offline Map Caching', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                subtitle: const Text('Preload Leyte map tiles for low data', style: TextStyle(fontFamily: 'Outfit', fontSize: 12)),
                trailing: Switch(value: true, onChanged: (v) {}, activeThumbColor: AppTheme.secondaryColor),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline_rounded, color: AppTheme.neutral600),
                title: const Text('App Version', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                trailing: const Text('1.1.8', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700, color: AppTheme.neutral600)),
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
