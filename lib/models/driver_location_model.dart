import 'package:json_annotation/json_annotation.dart';

part 'driver_location_model.g.dart';

/// Driver location for realtime tracking
@JsonSerializable()
class DriverLocationModel {
  @JsonKey(name: 'driver_id')
  final String driverId;
  final double lat;
  final double lng;
  final double? heading;
  final double? speed;
  @JsonKey(name: 'is_online')
  final bool isOnline;
  @JsonKey(name: 'is_available')
  final bool isAvailable; // Online and not on a trip
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const DriverLocationModel({
    required this.driverId,
    required this.lat,
    required this.lng,
    this.heading,
    this.speed,
    this.isOnline = false,
    this.isAvailable = false,
    required this.updatedAt,
  });

  factory DriverLocationModel.fromJson(Map<String, dynamic> json) =>
      _$DriverLocationModelFromJson(json);

  Map<String, dynamic> toJson() => _$DriverLocationModelToJson(this);

  DriverLocationModel copyWith({
    String? driverId,
    double? lat,
    double? lng,
    double? heading,
    double? speed,
    bool? isOnline,
    bool? isAvailable,
    DateTime? updatedAt,
  }) {
    return DriverLocationModel(
      driverId: driverId ?? this.driverId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      isOnline: isOnline ?? this.isOnline,
      isAvailable: isAvailable ?? this.isAvailable,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Batch of location updates for GPS batching
@JsonSerializable()
class LocationBatch {
  @JsonKey(name: 'driver_id')
  final String driverId;
  final List<LocationUpdate> updates;
  final DateTime timestamp;

  const LocationBatch({
    required this.driverId,
    required this.updates,
    required this.timestamp,
  });

  factory LocationBatch.fromJson(Map<String, dynamic> json) =>
      _$LocationBatchFromJson(json);

  Map<String, dynamic> toJson() => _$LocationBatchToJson(this);
}

/// Single location update within a batch
@JsonSerializable()
class LocationUpdate {
  final double lat;
  final double lng;
  final double? heading;
  final double? speed;
  final DateTime timestamp;

  const LocationUpdate({
    required this.lat,
    required this.lng,
    this.heading,
    this.speed,
    required this.timestamp,
  });

  factory LocationUpdate.fromJson(Map<String, dynamic> json) =>
      _$LocationUpdateFromJson(json);

  Map<String, dynamic> toJson() => _$LocationUpdateToJson(this);
}
