import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';

/// Route information from OSRM
class RouteInfo {
  final double distanceMeters;
  final int durationSeconds;
  final String polyline;
  final List<RouteLeg> legs;
  final List<RouteStep> steps;

  const RouteInfo({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.polyline,
    this.legs = const [],
    this.steps = const [],
  });

  double get distanceKm => distanceMeters / 1000;
  int get durationMinutes => (durationSeconds / 60).ceil();

  factory RouteInfo.fromOsrmJson(Map<String, dynamic> json) {
    final route = json['routes']?[0];
    if (route == null) {
      throw Exception('No route found');
    }

    final legs =
        (route['legs'] as List?)?.map((l) => RouteLeg.fromJson(l)).toList() ??
        [];

    final steps = legs.expand((leg) => leg.steps).toList();

    return RouteInfo(
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toInt(),
      polyline: route['geometry'] as String,
      legs: legs,
      steps: steps,
    );
  }
}

/// Route leg (segment between waypoints)
class RouteLeg {
  final double distanceMeters;
  final int durationSeconds;
  final String summary;
  final List<RouteStep> steps;

  const RouteLeg({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.summary,
    this.steps = const [],
  });

  factory RouteLeg.fromJson(Map<String, dynamic> json) {
    return RouteLeg(
      distanceMeters: (json['distance'] as num).toDouble(),
      durationSeconds: (json['duration'] as num).toInt(),
      summary: json['summary'] ?? '',
      steps:
          (json['steps'] as List?)
              ?.map((s) => RouteStep.fromJson(s))
              .toList() ??
          [],
    );
  }
}

/// Route step (individual navigation instruction)
class RouteStep {
  final double distanceMeters;
  final int durationSeconds;
  final String instruction;
  final String maneuverType;
  final String maneuverModifier;
  final double startLat;
  final double startLng;
  final String polyline;

  const RouteStep({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.instruction,
    required this.maneuverType,
    this.maneuverModifier = '',
    required this.startLat,
    required this.startLng,
    required this.polyline,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final maneuver = json['maneuver'] as Map<String, dynamic>? ?? {};
    final location = maneuver['location'] as List? ?? [0.0, 0.0];

    return RouteStep(
      distanceMeters: (json['distance'] as num?)?.toDouble() ?? 0,
      durationSeconds: (json['duration'] as num?)?.toInt() ?? 0,
      instruction: json['name'] ?? '',
      maneuverType: maneuver['type'] ?? '',
      maneuverModifier: maneuver['modifier'] ?? '',
      startLng: (location[0] as num).toDouble(),
      startLat: (location[1] as num).toDouble(),
      polyline: json['geometry'] ?? '',
    );
  }

  String get humanInstruction {
    final modifier = maneuverModifier.isNotEmpty ? maneuverModifier : '';
    switch (maneuverType) {
      case 'turn':
        return 'Turn $modifier onto $instruction';
      case 'new name':
        return 'Continue onto $instruction';
      case 'depart':
        return 'Head $modifier on $instruction';
      case 'arrive':
        return 'Arrive at destination';
      case 'merge':
        return 'Merge $modifier onto $instruction';
      case 'roundabout':
        return 'Enter roundabout and take $modifier exit';
      case 'fork':
        return 'Take the $modifier fork onto $instruction';
      default:
        return instruction.isNotEmpty ? instruction : 'Continue';
    }
  }
}

/// OSRM routing service
class OsrmService {
  final Dio _dio;
  final String _baseUrl;

  OsrmService({String? baseUrl})
    : _baseUrl = baseUrl ?? EnvConfig.osrmBaseUrl,
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

  /// Get route between two points
  Future<RouteInfo> getRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    bool alternatives = false,
    bool steps = true,
    String geometries = 'polyline6', // More precise polyline
    String overview = 'full',
  }) async {
    try {
      final uri =
          Uri.parse(
            '$_baseUrl/route/v1/driving/$startLng,$startLat;$endLng,$endLat',
          ).replace(
            queryParameters: {
              'alternatives': alternatives.toString(),
              'steps': steps.toString(),
              'geometries': geometries,
              'overview': overview,
              'annotations': 'true',
            },
          );

      final response = await _dio.getUri(uri);

      if (response.statusCode != 200) {
        throw Exception('OSRM error: ${response.statusCode}');
      }

      final data = response.data as Map<String, dynamic>;

      if (data['code'] != 'Ok') {
        throw Exception('OSRM error: ${data['code']} - ${data['message']}');
      }

      return RouteInfo.fromOsrmJson(data);
    } catch (e) {
      debugPrint('OSRM routing error: $e');
      rethrow;
    }
  }

  /// Get route with multiple waypoints
  Future<RouteInfo> getRouteWithWaypoints({
    required List<({double lat, double lng})> waypoints,
    bool steps = true,
  }) async {
    if (waypoints.length < 2) {
      throw Exception('At least 2 waypoints required');
    }

    try {
      final coordinates = waypoints.map((w) => '${w.lng},${w.lat}').join(';');

      final uri = Uri.parse('$_baseUrl/route/v1/driving/$coordinates').replace(
        queryParameters: {
          'steps': steps.toString(),
          'geometries': 'polyline6',
          'overview': 'full',
        },
      );

      final response = await _dio.getUri(uri);

      if (response.statusCode != 200) {
        throw Exception('OSRM error: ${response.statusCode}');
      }

      return RouteInfo.fromOsrmJson(response.data);
    } catch (e) {
      debugPrint('OSRM routing error: $e');
      rethrow;
    }
  }

  /// Get estimated time of arrival
  Future<Duration> getEta({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    final route = await getRoute(
      startLat: startLat,
      startLng: startLng,
      endLat: endLat,
      endLng: endLng,
      steps: false,
    );

    return Duration(seconds: route.durationSeconds);
  }

  /// Decode polyline6 to list of coordinates
  static List<({double lat, double lng})> decodePolyline(String encoded) {
    final List<({double lat, double lng})> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;

      // Decode latitude
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      // Decode longitude
      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      // Polyline6 uses 1e6 precision
      points.add((lat: lat / 1e6, lng: lng / 1e6));
    }

    return points;
  }
}

/// OSRM service provider
final osrmServiceProvider = Provider<OsrmService>((ref) {
  return OsrmService();
});
