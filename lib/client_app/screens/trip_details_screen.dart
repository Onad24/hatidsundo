import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../../models/trip_model.dart';
import '../../widgets/map_widget.dart';

class TripDetailsScreen extends StatelessWidget {
  final TripModel trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final routePoints = trip.routePolyline != null
        ? polylineToLatLng(trip.routePolyline!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Map Snapshot
          SizedBox(
            height: 250,
            child: AppMapWidget(
              initialCenter: LatLng(trip.pickupLat, trip.pickupLng),
              pickupMarker: LatLng(trip.pickupLat, trip.pickupLng),
              destinationMarker: LatLng(trip.destLat, trip.destLng),
              routePoints: routePoints,
              isInteractive: true,
            ),
          ),

          // Details List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Date and Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(trip.createdAt),
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        color: AppTheme.neutral500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: trip.isCompleted
                            ? AppTheme.successColor.withValues(alpha: 0.1)
                            : AppTheme.errorColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        trip.status.name.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: trip.isCompleted
                              ? AppTheme.successColor
                              : AppTheme.errorColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Locations
                _buildLocationItem(
                  icon: Icons.my_location_rounded,
                  color: AppTheme.successColor,
                  label: 'Pickup',
                  address: trip.pickupAddress ?? 'Pickup Location',
                ),
                const SizedBox(height: 24),
                _buildLocationItem(
                  icon: Icons.location_on_rounded,
                  color: AppTheme.errorColor,
                  label: 'Destination',
                  address: trip.destAddress ?? 'Destination',
                ),
                const SizedBox(height: 32),

                const Divider(),
                const SizedBox(height: 16),

                // Fare Breakdown
                const Text(
                  'Payment Details',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _buildFareItem(
                  'Base Fare',
                  (trip.fareEstimated * 0.8).toStringAsFixed(2),
                ),
                if (trip.fareFinal != null)
                  _buildFareItem(
                    'Total',
                    trip.fareFinal!.toStringAsFixed(2),
                    isTotal: true,
                  )
                else
                  _buildFareItem(
                    'Estimated',
                    trip.fareEstimated.toStringAsFixed(2),
                    isTotal: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationItem({
    required IconData icon,
    required Color color,
    required String label,
    required String address,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 12,
                  color: AppTheme.neutral500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFareItem(String label, String amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
              color: isTotal ? AppTheme.neutral900 : AppTheme.neutral600,
            ),
          ),
          Text(
            '₱$amount',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
              color: isTotal ? AppTheme.neutral900 : AppTheme.neutral600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Simple placeholder formatting, use intl in prod
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
