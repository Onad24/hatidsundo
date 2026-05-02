import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../services/services.dart';
import '../../services/fare_settings_service.dart';
import '../../state/state.dart';
import '../../widgets/map_widget.dart';

/// Request ride screen with pickup and destination selection
class RequestRideScreen extends ConsumerStatefulWidget {
  const RequestRideScreen({super.key});

  @override
  ConsumerState<RequestRideScreen> createState() => _RequestRideScreenState();
}

class _RequestRideScreenState extends ConsumerState<RequestRideScreen> {
  final _pickupController = TextEditingController();
  final _destController = TextEditingController();

  LatLng? _pickupLocation;
  LatLng? _destLocation;
  String? _pickupAddress;
  String? _destAddress;
  RouteInfo? _routeInfo;
  double?
  _nearestDriverDistanceKm; // distance from nearest available rider to pickup
  bool _isLoading = false;
  bool _selectingPickup = true;

  // Search state
  List<LocationResult> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    final position = await ref.read(currentPositionProvider.future);
    if (position != null && mounted) {
      setState(() {
        _pickupLocation = LatLng(position.latitude, position.longitude);
        _pickupAddress = 'Current Location';
        _pickupController.text = 'Current Location';
      });
      // Optionally reverse geocode current location for accuracy
      _reverseGeocode(_pickupLocation!, isPickup: true);
    }
  }

  Future<void> _calculateRoute() async {
    if (_pickupLocation == null || _destLocation == null) return;

    setState(() => _isLoading = true);
    try {
      final osrmService = ref.read(osrmServiceProvider);
      final supabase = ref.read(supabaseServiceProvider);

      // Calculate the route
      final route = await osrmService.getRoute(
        startLat: _pickupLocation!.latitude,
        startLng: _pickupLocation!.longitude,
        endLat: _destLocation!.latitude,
        endLng: _destLocation!.longitude,
      );

      // Find nearest available active driver to pickup location
      double? nearestDriverKm;
      try {
        final driversRaw =
            await supabase.client.rpc(
                  'get_nearby_drivers',
                  params: {
                    'p_lat': _pickupLocation!.latitude,
                    'p_lng': _pickupLocation!.longitude,
                    'p_radius_km': 20.0, // wide radius for fare estimate
                  },
                )
                as List?;

        if (driversRaw != null && driversRaw.isNotEmpty) {
          // Drivers are sorted nearest-first by the RPC
          nearestDriverKm = (driversRaw.first['distance_km'] as num?)
              ?.toDouble();
        }
      } catch (e) {
        // Non-blocking: fare estimate will omit driver pickup distance
        debugPrint('Could not fetch nearby drivers for fare estimate: $e');
      }

      if (mounted) {
        setState(() {
          _routeInfo = route;
          _nearestDriverDistanceKm = nearestDriverKm;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error calculating route: $e')));
      }
    }
  }

  void _onMapTap(LatLng location) {
    // Determine which field we are setting
    final isPickup = _selectingPickup;

    setState(() {
      if (isPickup) {
        _pickupLocation = location;
        _pickupAddress = 'Loading address...'; // Temporary
        _pickupController.text =
            'Pin at ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';
        _selectingPickup = false; // Auto-advance
      } else {
        _destLocation = location;
        _destAddress = 'Loading address...'; // Temporary
        _destController.text =
            'Pin at ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';
      }
    });

    // Reverse geocode
    _reverseGeocode(location, isPickup: isPickup);

    if (_pickupLocation != null && _destLocation != null) {
      _calculateRoute();
    }
  }

  Future<void> _reverseGeocode(
    LatLng location, {
    required bool isPickup,
  }) async {
    try {
      final result = await ref
          .read(geocodingServiceProvider)
          .reverseGeocode(location.latitude, location.longitude);
      if (mounted && result != null) {
        setState(() {
          if (isPickup) {
            _pickupAddress = result.name.isNotEmpty
                ? result.name
                : result.address;
            // Ensure address isn't too long for the field
            _pickupController.text = _pickupAddress ?? '';
          } else {
            _destAddress = result.name.isNotEmpty
                ? result.name
                : result.address;
            _destController.text = _destAddress ?? '';
          }
        });
      }
    } catch (e) {
      print('Reverse geocode error: $e');
    }
  }

  // Handle search input changes
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Don't search if query is empty or just coordinate strings we set ourselves
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _isSearching = true);
      try {
        final results = await ref.read(geocodingServiceProvider).search(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _selectSearchResult(LocationResult result) {
    setState(() {
      final location = LatLng(result.lat, result.lng);

      if (_selectingPickup) {
        _pickupLocation = location;
        _pickupAddress = result.name.isNotEmpty ? result.name : result.address;
        _pickupController.text = _pickupAddress!;
        _selectingPickup = false; // Auto-advance
      } else {
        _destLocation = location;
        _destAddress = result.name.isNotEmpty ? result.name : result.address;
        _destController.text = _destAddress!;
      }

      _searchResults = []; // Clear results
      FocusScope.of(context).unfocus(); // Hide keyboard
    });

    if (_pickupLocation != null && _destLocation != null) {
      _calculateRoute();
    }
  }

  Future<void> _requestRide() async {
    if (_pickupLocation == null || _destLocation == null) return;

    setState(() => _isLoading = true);
    try {
      // If pickup is still "Current Location", re-fetch fresh GPS
      // so we don't send stale coordinates from when the screen opened
      if (_pickupAddress == 'Current Location') {
        final freshPos = await ref
            .read(locationServiceProvider)
            .getCurrentPosition();
        if (freshPos != null && mounted) {
          _pickupLocation = LatLng(freshPos.latitude, freshPos.longitude);
        }
      }

      final tripNotifier = ref.read(tripStateProvider.notifier);
      final trip = await tripNotifier.requestRide(
        pickupLat: _pickupLocation!.latitude,
        pickupLng: _pickupLocation!.longitude,
        pickupAddress: _pickupAddress,
        destLat: _destLocation!.latitude,
        destLng: _destLocation!.longitude,
        destAddress: _destAddress,
        nearestDriverDistanceKm: _nearestDriverDistanceKm,
      );

      if (trip != null && mounted) {
        context.go('/client/trip/${trip.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error requesting ride: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _routeInfo != null
        ? polylineToLatLng(_routeInfo!.polyline)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Ride'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Location inputs
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: AppTheme.cardShadow,
            ),
            child: Column(
              children: [
                // Pickup
                _buildLocationInput(
                  controller: _pickupController,
                  icon: Icons.circle,
                  iconColor: AppTheme.successColor,
                  hint: 'Pickup location',
                  isSelected: _selectingPickup,
                  onTap: () => setState(() => _selectingPickup = true),
                ),
                const SizedBox(height: 8),

                // Connector
                Row(
                  children: [
                    const SizedBox(width: 11),
                    Container(width: 2, height: 20, color: AppTheme.neutral300),
                  ],
                ),
                const SizedBox(height: 8),

                // Destination
                _buildLocationInput(
                  controller: _destController,
                  icon: Icons.location_on_rounded,
                  iconColor: AppTheme.errorColor,
                  hint: 'Where to?',
                  isSelected: !_selectingPickup,
                  onTap: () => setState(() => _selectingPickup = false),
                ),
              ],
            ),
          ),

          // Search Results Overlay
          if (_searchResults.isNotEmpty)
            Expanded(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(
                        result.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        result.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectSearchResult(result),
                    );
                  },
                ),
              ),
            )
          else
            // Map
            Expanded(
              child: Stack(
                children: [
                  AppMapWidget(
                    initialCenter:
                        _pickupLocation ?? const LatLng(14.5995, 120.9842),
                    pickupMarker: _pickupLocation,
                    destinationMarker: _destLocation,
                    routePoints: routePoints,
                    onTap: _onMapTap,
                  ),

                  // Selection hint
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectingPickup
                                ? 'Tap map to set pickup'
                                : 'Tap map to set destination',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 14,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_isSearching)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),

          // Route info and request button (only show if not searching and route exists)
          if (_searchResults.isEmpty) ...[
            if (_routeInfo != null)
              _buildRouteInfoPanel()
            else if (_pickupLocation != null &&
                _destLocation != null &&
                _isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationInput({
    required TextEditingController controller,
    required IconData icon,
    required Color iconColor,
    required String hint,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primaryColor.withValues(alpha: 0.05)
            : Theme.of(context).brightness == Brightness.dark
            ? AppTheme.neutral800
            : AppTheme.neutral100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 12),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              onTap: onTap,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                hintStyle: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 15,
                  color: Theme.of(context).hintColor,
                ),
              ),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.normal,
                fontSize: 15,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () {
                controller.clear();
                _onSearchChanged(''); // Clear search
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoPanel() {
    // Use dynamic fare settings from database
    final fareSettingsAsync = ref.watch(fareSettingsProvider);
    final fareSettings = fareSettingsAsync.valueOrNull ?? const FareSettings();

    final destKm = _routeInfo!.distanceKm;
    final driverKm = _nearestDriverDistanceKm ?? 0.0;
    final estimatedFare = fareSettings.calculateFare(
      destKm: destKm,
      driverPickupKm: driverKm,
    );
    final isNight = fareSettings.isNightTime(DateTime.now());
    final bool noDriversNearby = _nearestDriverDistanceKm == null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Route stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRouteStat(
                  icon: Icons.straighten_rounded,
                  value: '${_routeInfo!.distanceKm.toStringAsFixed(1)} km',
                  label: 'Distance',
                ),
                Container(width: 1, height: 40, color: AppTheme.neutral200),
                _buildRouteStat(
                  icon: Icons.schedule_rounded,
                  value: '${_routeInfo!.durationMinutes} min',
                  label: 'Duration',
                ),
                Container(width: 1, height: 40, color: AppTheme.neutral200),
                _buildRouteStat(
                  icon: Icons.payments_rounded,
                  value: noDriversNearby
                      ? '₱${estimatedFare.toStringAsFixed(0)}+'
                      : '₱${estimatedFare.toStringAsFixed(0)}',
                  label: noDriversNearby ? 'Est. Fare*' : 'Est. Fare',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Night rate indicator
            if (isNight)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🌙 ', style: TextStyle(fontSize: 14)),
                      Text(
                        'Night rate applied (+20% distance fare)',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.warningColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Disclaimer if no nearby driver found
            if (noDriversNearby)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '* No active riders found nearby. Fare estimate excludes pickup distance.',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 11,
                    color: AppTheme.neutral500,
                  ),
                ),
              ),

            // Request button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _requestRide,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Request Ride'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteStat({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.neutral900,
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
    );
  }
}
