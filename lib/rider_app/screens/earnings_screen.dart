import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../state/state.dart';
import '../../services/fare_settings_service.dart';

/// Rider earnings screen
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripHistory = ref.watch(tripHistoryProvider(50));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Earnings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: tripHistory.when(
        data: (trips) {
          // Get platform fee from settings
          final fareSettingsAsync = ref.watch(fareSettingsProvider);
          final platformFeePct = fareSettingsAsync.valueOrNull?.platformFeePercent ?? 0.10;
          final driverSharePct = 1.0 - platformFeePct;

          // Calculate earnings (fare - platform fee)
          final totalEarnings = trips.fold<double>(0, (sum, trip) {
            final fare = trip.fareFinal ?? trip.fareEstimated;
            final platformFee = fare * platformFeePct;
            return sum + (fare - platformFee);
          });

          final todayTrips = trips.where((t) {
            return t.completedAt != null &&
                DateUtils.isSameDay(t.completedAt!, DateTime.now());
          }).toList();

          final todayEarnings = todayTrips.fold<double>(0, (sum, trip) {
            final fare = trip.fareFinal ?? trip.fareEstimated;
            return sum + (fare * driverSharePct);
          });

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Earnings summary card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppTheme.elevatedShadow,
                ),
                child: Column(
                  children: [
                    const Text(
                      'Total Earnings',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₱${totalEarnings.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${trips.length} trips completed',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Today's stats
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.today_rounded,
                      label: "Today's Earnings",
                      value: '₱${todayEarnings.toStringAsFixed(0)}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.local_taxi_rounded,
                      label: "Today's Trips",
                      value: '${todayTrips.length}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Recent trips
              const Text(
                'Recent Trips',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (trips.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.neutral100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'No trips yet',
                      style: TextStyle(color: AppTheme.neutral500),
                    ),
                  ),
                )
              else
                ...trips.take(10).map((trip) {
                  final fare = trip.fareFinal ?? trip.fareEstimated;
                  final earnings = fare * driverSharePct;
                  final dateFormat = DateFormat('MMM d, h:mm a');

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.successColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: AppTheme.successColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.destAddress ?? 'Trip completed',
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                dateFormat.format(
                                  trip.completedAt ?? trip.createdAt,
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 12,
                                  color: AppTheme.neutral500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '+₱${earnings.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.successColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryColor),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 12,
              color: AppTheme.neutral500,
            ),
          ),
        ],
      ),
    );
  }
}
