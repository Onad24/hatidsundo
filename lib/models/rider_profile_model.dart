import 'package:json_annotation/json_annotation.dart';

part 'rider_profile_model.g.dart';

/// Rider approval status
enum RiderStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('approved')
  approved,
  @JsonValue('rejected')
  rejected,
  @JsonValue('suspended')
  suspended,
}

/// Rider profile model
@JsonSerializable()
class RiderProfileModel {
  @JsonKey(name: 'user_id')
  final String userId;

  // Flat vehicle details
  @JsonKey(name: 'vehicle_make')
  final String vehicleMake;
  @JsonKey(name: 'vehicle_model')
  final String vehicleModel;
  @JsonKey(name: 'vehicle_year')
  final int? vehicleYear;
  @JsonKey(name: 'vehicle_color')
  final String? vehicleColor;
  @JsonKey(name: 'plate_number')
  final String plateNumber;
  @JsonKey(name: 'vehicle_type')
  final String vehicleType;

  // License details
  @JsonKey(name: 'license_number')
  final String licenseNumber;
  @JsonKey(name: 'license_expiry')
  final DateTime? licenseExpiry;

  // Document URLs
  @JsonKey(name: 'license_photo_url')
  final String? licensePhotoUrl;
  @JsonKey(name: 'vehicle_photo_url')
  final String? vehiclePhotoUrl;
  @JsonKey(name: 'or_cr_photo_url')
  final String? orCrPhotoUrl;
  @JsonKey(name: 'selfie_url')
  final String? selfieUrl;

  final RiderStatus status;
  @JsonKey(name: 'rejection_reason')
  final String? rejectionReason;
  @JsonKey(name: 'avg_rating')
  final double avgRating;
  @JsonKey(name: 'total_trips')
  final int totalTrips;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'approved_at')
  final DateTime? approvedAt;

  const RiderProfileModel({
    required this.userId,
    required this.vehicleMake,
    required this.vehicleModel,
    this.vehicleYear,
    this.vehicleColor,
    required this.plateNumber,
    required this.vehicleType,
    required this.licenseNumber,
    this.licenseExpiry,
    this.licensePhotoUrl,
    this.vehiclePhotoUrl,
    this.orCrPhotoUrl,
    this.selfieUrl,
    required this.status,
    this.rejectionReason,
    this.avgRating = 0.0,
    this.totalTrips = 0,
    required this.createdAt,
    this.approvedAt,
  });

  factory RiderProfileModel.fromJson(Map<String, dynamic> json) =>
      _$RiderProfileModelFromJson(json);

  Map<String, dynamic> toJson() => _$RiderProfileModelToJson(this);

  RiderProfileModel copyWith({
    String? userId,
    String? vehicleMake,
    String? vehicleModel,
    int? vehicleYear,
    String? vehicleColor,
    String? plateNumber,
    String? vehicleType,
    String? licenseNumber,
    DateTime? licenseExpiry,
    String? licensePhotoUrl,
    String? vehiclePhotoUrl,
    String? orCrPhotoUrl,
    String? selfieUrl,
    RiderStatus? status,
    String? rejectionReason,
    double? avgRating,
    int? totalTrips,
    DateTime? createdAt,
    DateTime? approvedAt,
  }) {
    return RiderProfileModel(
      userId: userId ?? this.userId,
      vehicleMake: vehicleMake ?? this.vehicleMake,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleYear: vehicleYear ?? this.vehicleYear,
      vehicleColor: vehicleColor ?? this.vehicleColor,
      plateNumber: plateNumber ?? this.plateNumber,
      vehicleType: vehicleType ?? this.vehicleType,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      licenseExpiry: licenseExpiry ?? this.licenseExpiry,
      licensePhotoUrl: licensePhotoUrl ?? this.licensePhotoUrl,
      vehiclePhotoUrl: vehiclePhotoUrl ?? this.vehiclePhotoUrl,
      orCrPhotoUrl: orCrPhotoUrl ?? this.orCrPhotoUrl,
      selfieUrl: selfieUrl ?? this.selfieUrl,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      avgRating: avgRating ?? this.avgRating,
      totalTrips: totalTrips ?? this.totalTrips,
      createdAt: createdAt ?? this.createdAt,
      approvedAt: approvedAt ?? this.approvedAt,
    );
  }

  bool get isPending => status == RiderStatus.pending;
  bool get isApproved => status == RiderStatus.approved;
  bool get isRejected => status == RiderStatus.rejected;
  bool get isSuspended => status == RiderStatus.suspended;
  bool get canDrive => isApproved;
}
