import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../state/state.dart';
import '../widgets/admin_sidebar.dart';

/// Provider for admin dashboard stats — uses the admin_actions Edge Function
final dashboardStatsProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final supabase = Supabase.instance.client;

  // Fetch in parallel
  final results = await Future.wait([
    // Active trips count
    supabase.from('trips').select('id').inFilter('status', [
      'pending',
      'accepted',
      'driver_arriving',
      'in_progress',
    ]),
    // Active drivers count
    supabase.from('driver_locations').select('driver_id').eq('is_online', true),
    // Pending approvals count
    supabase.from('rider_profiles').select('id').eq('status', 'pending'),
    // Today's completed trips for revenue
    supabase
        .from('trips')
        .select('fare_final, platform_fee')
        .eq('status', 'completed')
        .gte(
          'completed_at',
          DateTime.now().toUtc().toIso8601String().substring(0, 10),
        ),
  ]);

  final activeTrips = (results[0] as List).length;
  final activeDrivers = (results[1] as List).length;
  final pendingApprovals = (results[2] as List).length;

  // Sum today's revenue
  double todayRevenue = 0;
  for (final trip in (results[3] as List)) {
    todayRevenue += (trip['platform_fee'] as num?)?.toDouble() ?? 0;
  }

  return {
    'active_trips': activeTrips,
    'active_drivers': activeDrivers,
    'pending_approvals': pendingApprovals,
    'today_revenue': todayRevenue,
  };
});

/// Provider for recent trips
final recentTripsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('trips')
      .select(
        'id, status, fare_final, fare_estimated, created_at, client:client_id(name), rider:rider_id(name)',
      )
      .order('created_at', ascending: false)
      .limit(5);
  return List<Map<String, dynamic>>.from(response);
});

/// Provider for pending approvals (brief list for dashboard)
final dashboardPendingProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('rider_profiles')
      .select('id, created_at, users!user_id!inner(name)')
      .eq('status', 'pending')
      .order('created_at', ascending: false)
      .limit(5);
  return List<Map<String, dynamic>>.from(response);
});

/// Admin dashboard main screen
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          const AdminSidebar(activeItem: 'Dashboard'),

          // Main content
          Expanded(
            child: Container(
              color: AppTheme.neutral50,
              child: Column(
                children: [
                  // Top bar
                  _buildTopBar(context, user),

                  // Dashboard content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dashboard',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Stats cards (real data)
                          _buildStatsRow(ref),
                          const SizedBox(height: 24),

                          // Quick actions and recent activity
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 2, child: _buildRecentTrips(ref)),
                              const SizedBox(width: 24),
                              Expanded(child: _buildPendingApprovals(ref)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, dynamic user) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Spacer(),
          // Notifications
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          // User avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
            child: Text(
              user?.name.substring(0, 1).toUpperCase() ?? 'A',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            user?.name ?? 'Admin',
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);

    return stats.when(
      data: (data) => Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Active Drivers',
              '${data['active_drivers']}',
              Icons.local_taxi_rounded,
              AppTheme.successColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStatCard(
              'Active Trips',
              '${data['active_trips']}',
              Icons.route_rounded,
              AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStatCard(
              'Pending Approvals',
              '${data['pending_approvals']}',
              Icons.pending_rounded,
              AppTheme.warningColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStatCard(
              'Today\'s Revenue',
              '₱${(data['today_revenue'] as double).toStringAsFixed(0)}',
              Icons.payments_rounded,
              AppTheme.secondaryColor,
            ),
          ),
        ],
      ),
      loading: () => const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Error loading stats: $e'),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  color: AppTheme.neutral500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTrips(WidgetRef ref) {
    final trips = ref.watch(recentTripsProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Trips',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('View All')),
            ],
          ),
          const SizedBox(height: 16),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.neutral200)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Trip ID',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Client',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Driver',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Fare',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Status',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // Rows from real data
          trips.when(
            data: (tripList) {
              if (tripList.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No trips yet',
                      style: TextStyle(color: AppTheme.neutral500),
                    ),
                  ),
                );
              }
              return Column(
                children: tripList.map((trip) => _buildTripRow(trip)).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripRow(Map<String, dynamic> trip) {
    final status =
        (trip['status'] as String?)?.replaceAll('_', ' ') ?? 'unknown';
    final statusCapitalized = status[0].toUpperCase() + status.substring(1);
    final clientName = (trip['client'] as Map?)?['name'] ?? 'Unknown';
    final riderName = (trip['rider'] as Map?)?['name'] ?? 'Unassigned';
    final fare =
        (trip['fare_final'] as num?)?.toDouble() ??
        (trip['fare_estimated'] as num?)?.toDouble() ??
        0;
    final tripId = (trip['id'] as String).substring(0, 8);

    final isCompleted = trip['status'] == 'completed';
    final isCancelled = trip['status'] == 'cancelled';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.neutral100)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('#$tripId', style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text(clientName, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text(riderName, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Text(
              '₱${fare.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppTheme.successColor.withValues(alpha: 0.1)
                    : isCancelled
                    ? AppTheme.errorColor.withValues(alpha: 0.1)
                    : AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusCapitalized,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isCompleted
                      ? AppTheme.successColor
                      : isCancelled
                      ? AppTheme.errorColor
                      : AppTheme.primaryColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingApprovals(WidgetRef ref) {
    final pending = ref.watch(dashboardPendingProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pending Approvals',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          pending.when(
            data: (list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'No pending approvals',
                      style: TextStyle(color: AppTheme.neutral500),
                    ),
                  ),
                );
              }
              return Column(
                children: list
                    .map((rider) => _buildApprovalItem(rider))
                    .toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e', style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalItem(Map<String, dynamic> rider) {
    final name = (rider['users'] as Map?)?['name'] ?? 'Unknown';
    final createdAt = DateTime.tryParse(rider['created_at'] ?? '');
    final timeAgo = createdAt != null
        ? _formatTimeAgo(DateTime.now().difference(createdAt))
        : 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.neutral50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.warningColor.withValues(alpha: 0.2),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppTheme.warningColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Submitted $timeAgo',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.neutral500,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(Duration duration) {
    if (duration.inDays > 0) return '${duration.inDays}d ago';
    if (duration.inHours > 0) return '${duration.inHours}h ago';
    if (duration.inMinutes > 0) return '${duration.inMinutes}m ago';
    return 'just now';
  }
}
