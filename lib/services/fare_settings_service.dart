import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Model representing the fare calculation settings from the database.
class FareSettings {
  final double baseFare; // legacy fallback
  final double baseFareMotorcycle;
  final double baseFareSedan;
  final double baseFareSuv;
  final double perKmRate; // legacy fallback
  final double perKmRateMotorcycle;
  final double perKmRateSedan;
  final double perKmRateSuv;
  final double nightRateMultiplier;
  final int nightStartHour;
  final int nightEndHour;
  final double platformFeePercent;

  const FareSettings({
    this.baseFare = 25.0,
    this.baseFareMotorcycle = 20.0,
    this.baseFareSedan = 25.0,
    this.baseFareSuv = 35.0,
    this.perKmRate = 8.0,
    this.perKmRateMotorcycle = 6.0,
    this.perKmRateSedan = 8.0,
    this.perKmRateSuv = 12.0,
    this.nightRateMultiplier = 1.2,
    this.nightStartHour = 21,
    this.nightEndHour = 5,
    this.platformFeePercent = 0.10,
  });

  factory FareSettings.fromJson(Map<String, dynamic> json) {
    return FareSettings(
      baseFare: (json['base_fare'] as num?)?.toDouble() ?? 25.0,
      baseFareMotorcycle:
          (json['base_fare_motorcycle'] as num?)?.toDouble() ?? 20.0,
      baseFareSedan:
          (json['base_fare_sedan'] as num?)?.toDouble() ?? 25.0,
      baseFareSuv:
          (json['base_fare_suv'] as num?)?.toDouble() ?? 35.0,
      perKmRate: (json['per_km_rate'] as num?)?.toDouble() ?? 8.0,
      perKmRateMotorcycle:
          (json['per_km_rate_motorcycle'] as num?)?.toDouble() ?? 6.0,
      perKmRateSedan:
          (json['per_km_rate_sedan'] as num?)?.toDouble() ?? 8.0,
      perKmRateSuv:
          (json['per_km_rate_suv'] as num?)?.toDouble() ?? 12.0,
      nightRateMultiplier:
          (json['night_rate_multiplier'] as num?)?.toDouble() ?? 1.2,
      nightStartHour: (json['night_start_hour'] as int?) ?? 21,
      nightEndHour: (json['night_end_hour'] as int?) ?? 5,
      platformFeePercent:
          (json['platform_fee_percent'] as num?)?.toDouble() ?? 0.10,
    );
  }

  /// Returns true if [dt] falls within the night rate window.
  bool isNightTime(DateTime dt) {
    final hour = dt.hour;
    return hour >= nightStartHour || hour < nightEndHour;
  }

  /// Get the base fare for a given vehicle type.
  double getBaseFare(String? vehicleType) {
    switch (vehicleType) {
      case 'motorcycle':
        return baseFareMotorcycle;
      case 'sedan':
        return baseFareSedan;
      case 'suv':
        return baseFareSuv;
      default:
        return baseFare; // fallback to legacy rate
    }
  }

  /// Get the per-km rate for a given vehicle type.
  double getPerKmRate(String? vehicleType) {
    switch (vehicleType) {
      case 'motorcycle':
        return perKmRateMotorcycle;
      case 'sedan':
        return perKmRateSedan;
      case 'suv':
        return perKmRateSuv;
      default:
        return perKmRate; // fallback to legacy rate
    }
  }

  /// Calculate the fare given distances.
  ///
  /// [destKm] — pickup→destination distance in km
  /// [driverPickupKm] — driver→pickup distance in km (0 if unknown)
  /// [vehicleType] — 'motorcycle', 'sedan', or 'suv'
  /// [at] — the time of the trip (for night rate check)
  double calculateFare({
    required double destKm,
    double driverPickupKm = 0.0,
    String? vehicleType,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    final nightMultiplier = isNightTime(now) ? nightRateMultiplier : 1.0;
    final rate = getPerKmRate(vehicleType);
    final base = getBaseFare(vehicleType);

    return base +
        (driverPickupKm.floorToDouble() * rate) +
        (destKm.floorToDouble() * rate * nightMultiplier);
  }

  /// Calculate the platform fee for a given fare amount.
  double calculatePlatformFee(double fare) {
    return fare * platformFeePercent;
  }
}

/// Provider that fetches fare settings from the database.
/// Falls back to defaults if the table doesn't exist yet.
final fareSettingsProvider = FutureProvider<FareSettings>((ref) async {
  try {
    final supabase = Supabase.instance.client;
    final response =
        await supabase.from('fare_settings').select().eq('id', 1).single();
    return FareSettings.fromJson(response);
  } catch (e) {
    // Table may not exist yet — return defaults
    return const FareSettings();
  }
});

