import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Model representing the fare calculation settings from the database.
class FareSettings {
  final double baseFare;
  final double perKmRate;
  final double nightRateMultiplier;
  final int nightStartHour;
  final int nightEndHour;
  final double platformFeePercent;

  const FareSettings({
    this.baseFare = 25.0,
    this.perKmRate = 8.0,
    this.nightRateMultiplier = 1.2,
    this.nightStartHour = 21,
    this.nightEndHour = 5,
    this.platformFeePercent = 0.10,
  });

  factory FareSettings.fromJson(Map<String, dynamic> json) {
    return FareSettings(
      baseFare: (json['base_fare'] as num?)?.toDouble() ?? 25.0,
      perKmRate: (json['per_km_rate'] as num?)?.toDouble() ?? 8.0,
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

  /// Calculate the fare given distances.
  ///
  /// [destKm] — pickup→destination distance in km
  /// [driverPickupKm] — driver→pickup distance in km (0 if unknown)
  /// [at] — the time of the trip (for night rate check)
  double calculateFare({
    required double destKm,
    double driverPickupKm = 0.0,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    final nightMultiplier = isNightTime(now) ? nightRateMultiplier : 1.0;

    return baseFare +
        (driverPickupKm.floorToDouble() * perKmRate) +
        (destKm.floorToDouble() * perKmRate * nightMultiplier);
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
