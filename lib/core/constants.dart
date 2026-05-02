/// App-wide constants
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Hatid Sundo';
  static const String appVersion = '1.0.0';

  // Supabase Tables
  static const String usersTable = 'users';
  static const String ridersProfilesTable = 'rider_profiles';
  static const String driversLocationsTable = 'driver_locations';
  static const String tripsTable = 'trips';
  static const String transactionsTable = 'transactions';
  static const String messagesTable = 'messages';
  static const String monthlyFeesTable = 'monthly_fees';
  static const String feeEventsTable = 'fee_events';
  static const String notificationsTable = 'notifications';

  // User Roles
  static const String roleClient = 'client';
  static const String roleRider = 'rider';
  static const String roleAdmin = 'admin';

  // Rider Status
  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';
  static const String statusSuspended = 'suspended';

  // Trip Status
  static const String tripStatusPending = 'pending';
  static const String tripStatusOffered = 'offered';
  static const String tripStatusAccepted = 'accepted';
  static const String tripStatusDriverArriving = 'driver_arriving';
  static const String tripStatusInProgress = 'in_progress';
  static const String tripStatusCompleted = 'completed';
  static const String tripStatusCancelled = 'cancelled';

  // Payment Status
  static const String paymentPending = 'pending';
  static const String paymentCompleted = 'completed';
  static const String paymentFailed = 'failed';

  // Realtime Channels
  static const String channelDriversPositions = 'drivers_positions';
  static const String channelTripPrefix = 'trip:';
  static const String channelChatPrefix = 'chat:';
  static const String channelAdminFees = 'admin_fees';

  // GPS Settings
  static const int gpsUpdateIntervalMs = 5000; // 5 seconds
  static const int gpsBatchingDurationMs = 3000; // 3 seconds batch
  static const double gpsMinDistanceMeters = 10.0;

  // Fee Settings
  // @deprecated — use fare_settings table via fareSettingsProvider instead
  static const double platformFeePercent = 0.10; // 10%

  // Map Settings
  static const double defaultMapZoom = 15.0;
  static const double nearbyDriversRadius = 5000.0; // 5km

  // Timeouts
  static const int matchDriverTimeoutSeconds = 60;
  static const int rideRequestTimeoutSeconds = 30;

  // Storage Buckets
  static const String documentsBucket = 'driver_documents';
  static const String profileImagesBucket = 'profile_images';

  // Notification Types
  static const String notifRideRequest = 'ride_request';
  static const String notifDriverAssigned = 'driver_assigned';
  static const String notifDriverArriving = 'driver_arriving';
  static const String notifTripStarted = 'trip_started';
  static const String notifTripCompleted = 'trip_completed';
  static const String notifFeeDueReminder = 'fee_due_reminder';
  static const String notifAdminMessage = 'admin_message';

  // Night Rate Settings
  // @deprecated — use fare_settings table via fareSettingsProvider instead
  static const double nightRateMultiplier = 1.2;
  static const int nightRateStartHour = 21; // 9 PM
  static const int nightRateEndHour = 5; // 5 AM

  /// Returns true if [dt] falls within the night rate window (9 PM – 5 AM).
  static bool isNightTime(DateTime dt) {
    final hour = dt.hour;
    return hour >= nightRateStartHour || hour < nightRateEndHour;
  }
}
