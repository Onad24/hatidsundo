// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rider_profile_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RiderProfileModel _$RiderProfileModelFromJson(Map<String, dynamic> json) =>
    RiderProfileModel(
      userId: json['user_id'] as String,
      vehicleMake: json['vehicle_make'] as String,
      vehicleModel: json['vehicle_model'] as String,
      vehicleYear: (json['vehicle_year'] as num?)?.toInt(),
      vehicleColor: json['vehicle_color'] as String?,
      plateNumber: json['plate_number'] as String,
      vehicleType: json['vehicle_type'] as String,
      licenseNumber: json['license_number'] as String,
      licenseExpiry: json['license_expiry'] == null
          ? null
          : DateTime.parse(json['license_expiry'] as String),
      licensePhotoUrl: json['license_photo_url'] as String?,
      vehiclePhotoUrl: json['vehicle_photo_url'] as String?,
      orCrPhotoUrl: json['or_cr_photo_url'] as String?,
      selfieUrl: json['selfie_url'] as String?,
      status: $enumDecode(_$RiderStatusEnumMap, json['status']),
      rejectionReason: json['rejection_reason'] as String?,
      avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 0.0,
      totalTrips: (json['total_trips'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      approvedAt: json['approved_at'] == null
          ? null
          : DateTime.parse(json['approved_at'] as String),
    );

Map<String, dynamic> _$RiderProfileModelToJson(RiderProfileModel instance) =>
    <String, dynamic>{
      'user_id': instance.userId,
      'vehicle_make': instance.vehicleMake,
      'vehicle_model': instance.vehicleModel,
      'vehicle_year': instance.vehicleYear,
      'vehicle_color': instance.vehicleColor,
      'plate_number': instance.plateNumber,
      'vehicle_type': instance.vehicleType,
      'license_number': instance.licenseNumber,
      'license_expiry': instance.licenseExpiry?.toIso8601String(),
      'license_photo_url': instance.licensePhotoUrl,
      'vehicle_photo_url': instance.vehiclePhotoUrl,
      'or_cr_photo_url': instance.orCrPhotoUrl,
      'selfie_url': instance.selfieUrl,
      'status': _$RiderStatusEnumMap[instance.status]!,
      'rejection_reason': instance.rejectionReason,
      'avg_rating': instance.avgRating,
      'total_trips': instance.totalTrips,
      'created_at': instance.createdAt.toIso8601String(),
      'approved_at': instance.approvedAt?.toIso8601String(),
    };

const _$RiderStatusEnumMap = {
  RiderStatus.pending: 'pending',
  RiderStatus.approved: 'approved',
  RiderStatus.rejected: 'rejected',
  RiderStatus.suspended: 'suspended',
};
