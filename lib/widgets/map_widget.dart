import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../config/env.dart';

import '../models/driver_location_model.dart';
import '../services/osrm_service.dart';

/// MapLibre map widget wrapper
class AppMapWidget extends ConsumerStatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final bool showUserLocation;
  final List<DriverLocationModel> drivers;
  final List<LatLng>? routePoints;
  final Function(LatLng)? onTap;
  final Function(LatLng)? onLongPress;
  final Function(MapLibreMapController)? onMapCreated;
  final LatLng? pickupMarker;
  final LatLng? destinationMarker;

  const AppMapWidget({
    super.key,
    required this.initialCenter,
    this.initialZoom = 15.0,
    this.showUserLocation = true,
    this.drivers = const [],
    this.routePoints,
    this.onTap,
    this.onLongPress,
    this.onMapCreated,
    this.pickupMarker,
    this.destinationMarker,
    this.isInteractive = true,
  });

  final bool isInteractive;

  @override
  ConsumerState<AppMapWidget> createState() => _AppMapWidgetState();
}

class _AppMapWidgetState extends ConsumerState<AppMapWidget> {
  MapLibreMapController? _controller;
  final Map<String, Symbol> _driverSymbols = {};
  Symbol? _pickupSymbol;
  Symbol? _destinationSymbol;
  Line? _routeLine;
  bool _isStyleLoaded = false;

  @override
  void didUpdateWidget(AppMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only update if style is loaded
    if (!_isStyleLoaded) return;

    // Update drivers if changed
    if (widget.drivers != oldWidget.drivers) {
      _updateDriverMarkers();
    }

    // Update route if changed
    if (widget.routePoints != oldWidget.routePoints) {
      _updateRoute();
    }

    // Update markers
    if (widget.pickupMarker != oldWidget.pickupMarker) {
      _updatePickupMarker();
    }
    if (widget.destinationMarker != oldWidget.destinationMarker) {
      _updateDestinationMarker();
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    widget.onMapCreated?.call(controller);
    // Don't add markers here - wait for style to load via onStyleLoadedCallback
  }

  void _onStyleLoaded() {
    _isStyleLoaded = true;
    // Now safe to add markers and routes
    _updateDriverMarkers();
    _updateRoute();
    _updatePickupMarker();
    _updateDestinationMarker();
  }

  void _onMapClick(Point<double> point, LatLng coordinates) {
    widget.onTap?.call(coordinates);
  }

  void _onMapLongClick(Point<double> point, LatLng coordinates) {
    widget.onLongPress?.call(coordinates);
  }

  Future<void> _updateDriverMarkers() async {
    if (_controller == null) return;

    // Remove old markers for drivers no longer present
    final currentDriverIds = widget.drivers.map((d) => d.driverId).toSet();
    final toRemove = _driverSymbols.keys
        .where((id) => !currentDriverIds.contains(id))
        .toList();

    for (final id in toRemove) {
      await _controller!.removeSymbol(_driverSymbols[id]!);
      _driverSymbols.remove(id);
    }

    // Add/update driver markers
    for (final driver in widget.drivers) {
      if (_driverSymbols.containsKey(driver.driverId)) {
        // Update existing
        await _controller!.updateSymbol(
          _driverSymbols[driver.driverId]!,
          SymbolOptions(
            geometry: LatLng(driver.lat, driver.lng),
            iconRotate: driver.heading,
          ),
        );
      } else {
        // Add new
        final symbol = await _controller!.addSymbol(
          SymbolOptions(
            geometry: LatLng(driver.lat, driver.lng),
            iconImage: 'car-icon',
            iconSize: 0.3,
            iconRotate: driver.heading,
          ),
        );
        _driverSymbols[driver.driverId] = symbol;
      }
    }
  }

  Future<void> _updateRoute() async {
    if (_controller == null) return;

    // Remove existing route
    if (_routeLine != null) {
      await _controller!.removeLine(_routeLine!);
      _routeLine = null;
    }

    // Add new route
    if (widget.routePoints != null && widget.routePoints!.length >= 2) {
      _routeLine = await _controller!.addLine(
        LineOptions(
          geometry: widget.routePoints,
          lineColor: '#4F46E5',
          lineWidth: 5.0,
          lineOpacity: 0.8,
        ),
      );
    }
  }

  Future<void> _updatePickupMarker() async {
    if (_controller == null) return;

    if (_pickupSymbol != null) {
      await _controller!.removeSymbol(_pickupSymbol!);
      _pickupSymbol = null;
    }

    if (widget.pickupMarker != null) {
      _pickupSymbol = await _controller!.addSymbol(
        SymbolOptions(
          geometry: widget.pickupMarker,
          iconImage: 'pickup-marker',
          iconSize: 0.4,
          iconAnchor: 'bottom',
        ),
      );
    }
  }

  Future<void> _updateDestinationMarker() async {
    if (_controller == null) return;

    if (_destinationSymbol != null) {
      await _controller!.removeSymbol(_destinationSymbol!);
      _destinationSymbol = null;
    }

    if (widget.destinationMarker != null) {
      _destinationSymbol = await _controller!.addSymbol(
        SymbolOptions(
          geometry: widget.destinationMarker,
          iconImage: 'destination-marker',
          iconSize: 0.4,
          iconAnchor: 'bottom',
        ),
      );
    }
  }

  Future<void> animateTo(LatLng target, {double? zoom}) async {
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(target, zoom ?? widget.initialZoom),
    );
  }

  Future<void> fitBounds(LatLngBounds bounds, {double padding = 50}) async {
    await _controller?.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: padding,
        right: padding,
        top: padding,
        bottom: padding,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: EnvConfig.mapStyleUrl,
      initialCameraPosition: CameraPosition(
        target: widget.initialCenter,
        zoom: widget.initialZoom,
      ),
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: _onMapClick,
      onMapLongClick: _onMapLongClick,
      myLocationEnabled: widget.showUserLocation,
      myLocationRenderMode: MyLocationRenderMode.compass,
      myLocationTrackingMode: MyLocationTrackingMode.tracking,
      trackCameraPosition: true,
      compassEnabled: true,
      rotateGesturesEnabled: widget.isInteractive,
      scrollGesturesEnabled: widget.isInteractive,
      tiltGesturesEnabled: widget.isInteractive,
      zoomGesturesEnabled: widget.isInteractive,
      attributionButtonMargins: const Point(-100, -100), // Hide attribution
      logoViewMargins: const Point(-100, -100), // Hide logo
    );
  }
}

/// Utility to convert OSRM polyline to LatLng list
List<LatLng> polylineToLatLng(String encoded) {
  final coords = OsrmService.decodePolyline(encoded);
  return coords.map((c) => LatLng(c.lat, c.lng)).toList();
}
