import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Location result from geocoding
class LocationResult {
  final String name;
  final String address;
  final double lat;
  final double lng;

  const LocationResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  factory LocationResult.fromJson(Map<String, dynamic> json) {
    return LocationResult(
      name: json['name'] ?? '',
      address: json['display_name'] ?? '',
      lat: double.parse(json['lat']),
      lng: double.parse(json['lon']),
    );
  }
}

/// Service for geocoding and reverse geocoding using Nominatim (OSM)
class GeocodingService {
  final Dio _dio;

  // Nominatim is free but requires a User-Agent.
  // Rate limit: 1 request per second.
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';

  GeocodingService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {
            'User-Agent': 'HatidSundo/1.0', // Required by Nominatim
          },
        ),
      );

  /// Search for a location by query string
  Future<List<LocationResult>> search(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'addressdetails': 1,
          'limit': 5,
        },
      );

      final List data = response.data as List;
      return data.map((item) => LocationResult.fromJson(item)).toList();
    } catch (e) {
      print('Geocoding search error: $e');
      return [];
    }
  }

  /// Get address from coordinates (Reverse Geocoding)
  Future<LocationResult?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _dio.get(
        '/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lng,
          'format': 'json',
          'addressdetails': 1,
        },
      );

      return LocationResult.fromJson(response.data);
    } catch (e) {
      print('Reverse geocoding error: $e');
      return null;
    }
  }
}

/// Geocoding service provider
final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  return GeocodingService();
});
