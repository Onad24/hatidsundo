// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'driver_location_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DriverLocationModel _$DriverLocationModelFromJson(Map<String, dynamic> json) =>
    DriverLocationModel(
      driverId: json['driver_id'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      isOnline: json['is_online'] as bool? ?? false,
      isAvailable: json['is_available'] as bool? ?? false,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$DriverLocationModelToJson(
  DriverLocationModel instance,
) => <String, dynamic>{
  'driver_id': instance.driverId,
  'lat': instance.lat,
  'lng': instance.lng,
  'heading': instance.heading,
  'speed': instance.speed,
  'is_online': instance.isOnline,
  'is_available': instance.isAvailable,
  'updated_at': instance.updatedAt.toIso8601String(),
};

LocationBatch _$LocationBatchFromJson(Map<String, dynamic> json) =>
    LocationBatch(
      driverId: json['driver_id'] as String,
      updates: (json['updates'] as List<dynamic>)
          .map((e) => LocationUpdate.fromJson(e as Map<String, dynamic>))
          .toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$LocationBatchToJson(LocationBatch instance) =>
    <String, dynamic>{
      'driver_id': instance.driverId,
      'updates': instance.updates,
      'timestamp': instance.timestamp.toIso8601String(),
    };

LocationUpdate _$LocationUpdateFromJson(Map<String, dynamic> json) =>
    LocationUpdate(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$LocationUpdateToJson(LocationUpdate instance) =>
    <String, dynamic>{
      'lat': instance.lat,
      'lng': instance.lng,
      'heading': instance.heading,
      'speed': instance.speed,
      'timestamp': instance.timestamp.toIso8601String(),
    };
