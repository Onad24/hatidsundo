import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;

import '../core/constants.dart';
import '../models/user_model.dart';
import 'supabase_service.dart';

/// Service for handling rider-related operations
class RiderService {
  final SupabaseService _supabaseService;

  RiderService(this._supabaseService);

  /// Upload a document to storage
  Future<String> uploadDocument(XFile file, String userId) async {
    final bytes = await file.readAsBytes();
    final fileExt = path.extension(file.path);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '$timestamp$fileExt';

    // Determine mime type
    final ext = fileExt.toLowerCase();
    final mimeType = (ext == '.png')
        ? 'image/png'
        : (ext == '.jpg' || ext == '.jpeg')
        ? 'image/jpeg'
        : 'application/octet-stream';

    // Force folder structure: userId/filename
    final filePath = '$userId/$fileName';
    print('DEBUG: Starting upload for user: $userId');
    print('DEBUG: Attempting upload to path: $filePath ($mimeType)');

    int attempts = 0;
    while (attempts < 3) {
      try {
        attempts++;
        await _supabaseService.client.storage
            .from(AppConstants.documentsBucket)
            .uploadBinary(
              filePath,
              bytes,
              fileOptions: FileOptions(contentType: mimeType),
            );
        print('DEBUG: Upload success to $filePath');
        break; // Success, exit loop
      } catch (e) {
        print('DEBUG: Upload attempt $attempts failed: $e');
        if (attempts >= 3) {
          throw Exception(
            'Storage Error (Path: $filePath) after 3 attempts: $e',
          );
        }
        // Wait before retrying (1s, 2s, etc.)
        await Future.delayed(Duration(seconds: attempts));
      }
    }

    final imageUrl = _supabaseService.client.storage
        .from(AppConstants.documentsBucket)
        .getPublicUrl(filePath);

    return imageUrl;
  }

  /// Register a new rider
  /// Register a new rider
  Future<void> registerRider({
    required String userId,
    required String vehicleMake,
    required String vehicleModel,
    required String vehicleYear,
    required String vehicleColor,
    required String plateNumber,
    required String vehicleType,
    required String licenseNumber,
    required DateTime licenseExpiry,
    required String licensePhotoUrl,
    required String vehiclePhotoUrl,
    required String orCrPhotoUrl,
    required String selfieUrl,
  }) async {
    try {
      // 1. Create rider profile
      await _supabaseService.from(AppConstants.ridersProfilesTable).insert({
        'user_id': userId,
        'status': AppConstants.statusPending,
        'vehicle_make': vehicleMake,
        'vehicle_model': vehicleModel,
        'vehicle_year': int.tryParse(vehicleYear),
        'vehicle_color': vehicleColor,
        'plate_number': plateNumber,
        'vehicle_type': vehicleType,
        'license_number': licenseNumber,
        'license_expiry': licenseExpiry.toIso8601String(),
        'license_photo_url': licensePhotoUrl,
        'vehicle_photo_url': vehiclePhotoUrl,
        'or_cr_photo_url': orCrPhotoUrl,
        'selfie_url': selfieUrl,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 2. Update user role to rider
      await _supabaseService
          .from(AppConstants.usersTable)
          .update({
            'role': UserRole.rider.name,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      throw Exception('Failed to register rider: $e');
    }
  }

  /// Get public client info (user details for riders to view)
  Future<Map<String, dynamic>?> getClientInfo(String clientId) async {
    try {
      final response = await _supabaseService.client
          .from(AppConstants.usersTable)
          .select('name, avatar_url')
          .eq('id', clientId)
          .maybeSingle();

      if (response == null) return null;

      return {
        'name': response['name'] ?? 'Passenger',
        'avatar_url': response['avatar_url'],
      };
    } catch (e) {
      debugPrint('getClientInfo error: $e');
      return null;
    }
  }

  /// Get public driver info (profile + user details).
  /// Uses two separate queries to avoid RLS issues with nested joins.
  Future<Map<String, dynamic>?> getDriverInfo(String riderId) async {
    try {
      debugPrint('DEBUG getDriverInfo: fetching for riderId=$riderId');

      // 1. Get user row (name, avatar)
      final userRow = await _supabaseService.client
          .from(AppConstants.usersTable)
          .select('name, avatar_url')
          .eq('id', riderId)
          .maybeSingle();
      debugPrint('DEBUG getDriverInfo: userRow=$userRow');

      // 2. Get rider profile row (vehicle, rating, plate)
      final profileRow = await _supabaseService.client
          .from(AppConstants.ridersProfilesTable)
          .select(
            'rating, vehicle_color, vehicle_make, vehicle_model, plate_number',
          )
          .eq('user_id', riderId)
          .maybeSingle();
      debugPrint('DEBUG getDriverInfo: profileRow=$profileRow');

      if (userRow == null && profileRow == null) {
        debugPrint('DEBUG getDriverInfo: BOTH null — likely RLS blocking');
        return null;
      }

      final vehicleDesc = profileRow != null
          ? '${profileRow['vehicle_color'] ?? ''} '
                '${profileRow['vehicle_make'] ?? ''} '
                '${profileRow['vehicle_model'] ?? ''}'
                ' • ${profileRow['plate_number'] ?? ''}'
          : 'Unknown vehicle';

      return {
        'name': userRow?['name'] ?? 'Driver',
        'avatar_url': userRow?['avatar_url'],
        'rating': profileRow?['rating'] ?? 0.0,
        'vehicle': vehicleDesc.trim(),
        'plate_number': profileRow?['plate_number'] ?? '',
      };
    } catch (e) {
      debugPrint('getDriverInfo error: $e');
      return null;
    }
  }
}

/// Rider service provider
final riderServiceProvider = Provider<RiderService>((ref) {
  final supabaseService = ref.watch(supabaseServiceProvider);
  return RiderService(supabaseService);
});
