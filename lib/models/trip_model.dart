import 'package:json_annotation/json_annotation.dart';

part 'trip_model.g.dart';

/// Trip status enum
enum TripStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('offered')
  offered,
  @JsonValue('accepted')
  accepted,
  @JsonValue('driver_arriving')
  driverArriving,
  @JsonValue('in_progress')
  inProgress,
  @JsonValue('completed')
  completed,
  @JsonValue('cancelled')
  cancelled,
}

/// Payment status enum
enum PaymentStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('completed')
  completed,
  @JsonValue('failed')
  failed,
}

/// Location point
@JsonSerializable()
class LocationPoint {
  final double lat;
  final double lng;
  final String? address;

  const LocationPoint({required this.lat, required this.lng, this.address});

  factory LocationPoint.fromJson(Map<String, dynamic> json) =>
      _$LocationPointFromJson(json);

  Map<String, dynamic> toJson() => _$LocationPointToJson(this);
}

/// Trip model
@JsonSerializable()
class TripModel {
  final String id;
  @JsonKey(name: 'client_id')
  final String clientId;
  @JsonKey(name: 'rider_id')
  final String? riderId;
  @JsonKey(name: 'pickup_lat')
  final double pickupLat;
  @JsonKey(name: 'pickup_lng')
  final double pickupLng;
  @JsonKey(name: 'pickup_address')
  final String? pickupAddress;
  @JsonKey(name: 'dest_lat')
  final double destLat;
  @JsonKey(name: 'dest_lng')
  final double destLng;
  @JsonKey(name: 'dest_address')
  final String? destAddress;
  final TripStatus status;
  @JsonKey(name: 'distance_km')
  final double? distanceKm;
  @JsonKey(name: 'duration_min')
  final int? durationMin;
  @JsonKey(name: 'fare_estimated')
  final double fareEstimated;
  @JsonKey(name: 'fare_final')
  final double? fareFinal;
  @JsonKey(name: 'payment_status')
  final PaymentStatus paymentStatus;
  @JsonKey(name: 'payment_method')
  final String paymentMethod;
  @JsonKey(name: 'route_polyline')
  final String? routePolyline;
  @JsonKey(name: 'cancellation_reason')
  final String? cancellationReason;
  @JsonKey(name: 'cancelled_by')
  final String? cancelledBy;
  final int? rating;
  @JsonKey(name: 'rating_comment')
  final String? ratingComment;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'offered_at')
  final DateTime? offeredAt;
  @JsonKey(name: 'accepted_at')
  final DateTime? acceptedAt;
  @JsonKey(name: 'started_at')
  final DateTime? startedAt;
  @JsonKey(name: 'completed_at')
  final DateTime? completedAt;

  const TripModel({
    required this.id,
    required this.clientId,
    this.riderId,
    required this.pickupLat,
    required this.pickupLng,
    this.pickupAddress,
    required this.destLat,
    required this.destLng,
    this.destAddress,
    required this.status,
    this.distanceKm,
    this.durationMin,
    required this.fareEstimated,
    this.fareFinal,
    required this.paymentStatus,
    required this.paymentMethod,
    this.routePolyline,
    this.cancellationReason,
    this.cancelledBy,
    this.rating,
    this.ratingComment,
    required this.createdAt,
    this.offeredAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
  });

  factory TripModel.fromJson(Map<String, dynamic> json) =>
      _$TripModelFromJson(json);

  Map<String, dynamic> toJson() => _$TripModelToJson(this);

  TripModel copyWith({
    String? id,
    String? clientId,
    String? riderId,
    double? pickupLat,
    double? pickupLng,
    String? pickupAddress,
    double? destLat,
    double? destLng,
    String? destAddress,
    TripStatus? status,
    double? distanceKm,
    int? durationMin,
    double? fareEstimated,
    double? fareFinal,
    PaymentStatus? paymentStatus,
    String? paymentMethod,
    String? routePolyline,
    String? cancellationReason,
    String? cancelledBy,
    int? rating,
    String? ratingComment,
    DateTime? createdAt,
    DateTime? offeredAt,
    DateTime? acceptedAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return TripModel(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      riderId: riderId ?? this.riderId,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      destLat: destLat ?? this.destLat,
      destLng: destLng ?? this.destLng,
      destAddress: destAddress ?? this.destAddress,
      status: status ?? this.status,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMin: durationMin ?? this.durationMin,
      fareEstimated: fareEstimated ?? this.fareEstimated,
      fareFinal: fareFinal ?? this.fareFinal,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      routePolyline: routePolyline ?? this.routePolyline,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      rating: rating ?? this.rating,
      ratingComment: ratingComment ?? this.ratingComment,
      createdAt: createdAt ?? this.createdAt,
      offeredAt: offeredAt ?? this.offeredAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  LocationPoint get pickupLocation =>
      LocationPoint(lat: pickupLat, lng: pickupLng, address: pickupAddress);

  LocationPoint get destLocation =>
      LocationPoint(lat: destLat, lng: destLng, address: destAddress);

  bool get isPending => status == TripStatus.pending;
  bool get isOffered => status == TripStatus.offered;
  bool get isAccepted => status == TripStatus.accepted;
  bool get isDriverArriving => status == TripStatus.driverArriving;
  bool get isInProgress => status == TripStatus.inProgress;
  bool get isCompleted => status == TripStatus.completed;
  bool get isCancelled => status == TripStatus.cancelled;
  bool get isActive => !isCompleted && !isCancelled;
}
