import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/trip_model.dart';
import 'package:intl/intl.dart';

/// Trip history card widget
class TripCard extends StatelessWidget {
  final TripModel trip;
  final VoidCallback? onTap;

  const TripCard({super.key, required this.trip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, y • h:mm a');
    final currencyFormat = NumberFormat.currency(symbol: '₱');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          children: [
            // Header with status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _getStatusColor().withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusLg),
                ),
              ),
              child: Row(
                children: [
                  Icon(_getStatusIcon(), size: 18, color: _getStatusColor()),
                  const SizedBox(width: 8),
                  Text(
                    _getStatusText(),
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateFormat.format(trip.createdAt),
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      color: AppTheme.neutral500,
                    ),
                  ),
                ],
              ),
            ),

            // Trip details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Pickup
                  _buildLocationRow(
                    icon: Icons.circle,
                    iconColor: AppTheme.successColor,
                    iconSize: 12,
                    text: trip.pickupAddress ?? 'Pickup location',
                    isPickup: true,
                  ),

                  // Connector line
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 2,
                          height: 24,
                          color: AppTheme.neutral200,
                        ),
                      ],
                    ),
                  ),

                  // Destination
                  _buildLocationRow(
                    icon: Icons.location_on,
                    iconColor: AppTheme.errorColor,
                    iconSize: 16,
                    text: trip.destAddress ?? 'Destination',
                    isPickup: false,
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Footer with fare and distance
                  Row(
                    children: [
                      _buildInfoChip(
                        icon: Icons.straighten_rounded,
                        text:
                            '${trip.distanceKm?.toStringAsFixed(1) ?? '—'} km',
                      ),
                      const SizedBox(width: 12),
                      _buildInfoChip(
                        icon: Icons.schedule_rounded,
                        text: '${trip.durationMin ?? '—'} min',
                      ),
                      const Spacer(),
                      Text(
                        currencyFormat.format(
                          trip.fareFinal ?? trip.fareEstimated,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.neutral900,
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
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required Color iconColor,
    required double iconSize,
    required String text,
    required bool isPickup,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 12,
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 14,
              color: AppTheme.neutral700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.neutral100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.neutral500),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 12,
              color: AppTheme.neutral600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (trip.status) {
      case TripStatus.completed:
        return AppTheme.successColor;
      case TripStatus.cancelled:
        return AppTheme.errorColor;
      case TripStatus.inProgress:
        return AppTheme.primaryColor;
      default:
        return AppTheme.warningColor;
    }
  }

  IconData _getStatusIcon() {
    switch (trip.status) {
      case TripStatus.completed:
        return Icons.check_circle_rounded;
      case TripStatus.cancelled:
        return Icons.cancel_rounded;
      case TripStatus.inProgress:
        return Icons.directions_car_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  String _getStatusText() {
    switch (trip.status) {
      case TripStatus.completed:
        return 'Completed';
      case TripStatus.cancelled:
        return 'Cancelled';
      case TripStatus.inProgress:
        return 'In Progress';
      case TripStatus.pending:
        return 'Finding Driver';
      case TripStatus.accepted:
        return 'Driver Assigned';
      case TripStatus.driverArriving:
        return 'Driver Arriving';
    }
  }
}
