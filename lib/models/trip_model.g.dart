// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocationPoint _$LocationPointFromJson(Map<String, dynamic> json) =>
    LocationPoint(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      address: json['address'] as String?,
    );

Map<String, dynamic> _$LocationPointToJson(LocationPoint instance) =>
    <String, dynamic>{
      'lat': instance.lat,
      'lng': instance.lng,
      'address': instance.address,
    };

TripModel _$TripModelFromJson(Map<String, dynamic> json) => TripModel(
  id: json['id'] as String,
  clientId: json['client_id'] as String,
  riderId: json['rider_id'] as String?,
  pickupLat: (json['pickup_lat'] as num).toDouble(),
  pickupLng: (json['pickup_lng'] as num).toDouble(),
  pickupAddress: json['pickup_address'] as String?,
  destLat: (json['dest_lat'] as num).toDouble(),
  destLng: (json['dest_lng'] as num).toDouble(),
  destAddress: json['dest_address'] as String?,
  status: $enumDecode(_$TripStatusEnumMap, json['status']),
  distanceKm: (json['distance_km'] as num?)?.toDouble(),
  durationMin: (json['duration_min'] as num?)?.toInt(),
  fareEstimated: (json['fare_estimated'] as num).toDouble(),
  fareFinal: (json['fare_final'] as num?)?.toDouble(),
  paymentStatus: $enumDecode(_$PaymentStatusEnumMap, json['payment_status']),
  paymentMethod: json['payment_method'] as String,
  routePolyline: json['route_polyline'] as String?,
  cancellationReason: json['cancellation_reason'] as String?,
  cancelledBy: json['cancelled_by'] as String?,
  rating: (json['rating'] as num?)?.toInt(),
  ratingComment: json['rating_comment'] as String?,
  createdAt: DateTime.parse(json['created_at'] as String),
  acceptedAt: json['accepted_at'] == null
      ? null
      : DateTime.parse(json['accepted_at'] as String),
  startedAt: json['started_at'] == null
      ? null
      : DateTime.parse(json['started_at'] as String),
  completedAt: json['completed_at'] == null
      ? null
      : DateTime.parse(json['completed_at'] as String),
);

Map<String, dynamic> _$TripModelToJson(TripModel instance) => <String, dynamic>{
  'id': instance.id,
  'client_id': instance.clientId,
  'rider_id': instance.riderId,
  'pickup_lat': instance.pickupLat,
  'pickup_lng': instance.pickupLng,
  'pickup_address': instance.pickupAddress,
  'dest_lat': instance.destLat,
  'dest_lng': instance.destLng,
  'dest_address': instance.destAddress,
  'status': _$TripStatusEnumMap[instance.status]!,
  'distance_km': instance.distanceKm,
  'duration_min': instance.durationMin,
  'fare_estimated': instance.fareEstimated,
  'fare_final': instance.fareFinal,
  'payment_status': _$PaymentStatusEnumMap[instance.paymentStatus]!,
  'payment_method': instance.paymentMethod,
  'route_polyline': instance.routePolyline,
  'cancellation_reason': instance.cancellationReason,
  'cancelled_by': instance.cancelledBy,
  'rating': instance.rating,
  'rating_comment': instance.ratingComment,
  'created_at': instance.createdAt.toIso8601String(),
  'accepted_at': instance.acceptedAt?.toIso8601String(),
  'started_at': instance.startedAt?.toIso8601String(),
  'completed_at': instance.completedAt?.toIso8601String(),
};

const _$TripStatusEnumMap = {
  TripStatus.pending: 'pending',
  TripStatus.accepted: 'accepted',
  TripStatus.driverArriving: 'driver_arriving',
  TripStatus.inProgress: 'in_progress',
  TripStatus.completed: 'completed',
  TripStatus.cancelled: 'cancelled',
};

const _$PaymentStatusEnumMap = {
  PaymentStatus.pending: 'pending',
  PaymentStatus.completed: 'completed',
  PaymentStatus.failed: 'failed',
};
