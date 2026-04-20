import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/auth_provider.dart';
import '../models/user_model.dart';
import '../models/trip_model.dart';

// Client App Screens
import '../client_app/screens/home_screen.dart';
import '../client_app/screens/onboarding_screen.dart';
import '../client_app/screens/profile_screen.dart';
import '../client_app/screens/request_ride_screen.dart';
import '../client_app/screens/active_trip_screen.dart';
import '../client_app/screens/chat_screen.dart' as client_chat;
import '../client_app/screens/history_screen.dart' as client_history;
import '../client_app/screens/trip_details_screen.dart';

// Rider App Screens
import '../rider_app/screens/home_screen.dart' as rider;
import '../rider_app/screens/registration_screen.dart';
import '../rider_app/screens/pending_approval_screen.dart';
import '../rider_app/screens/navigation_screen.dart';
import '../rider_app/screens/chat_screen.dart' as rider_chat;
import '../rider_app/screens/earnings_screen.dart';
import '../rider_app/screens/fee_dashboard_screen.dart';
import '../rider_app/screens/history_screen.dart' as rider_history;

// Admin Web Screens
import '../admin_web/screens/dashboard_screen.dart';
import '../admin_web/screens/rider_approval_screen.dart';
import '../admin_web/screens/fee_management_screen.dart';
import '../admin_web/screens/live_map_screen.dart';
import '../admin_web/screens/messaging_screen.dart';
import '../admin_web/screens/statistics_screen.dart';
import '../admin_web/screens/trips_monitor_screen.dart';

// Shared Screens
import '../widgets/login_screen.dart';
import '../widgets/splash_screen.dart';
import '../widgets/role_selection_screen.dart';

// Marketing Web Screen
import '../marketing_web/screens/marketing_screen.dart';

/// Route names
class Routes {
  Routes._();

  // Auth Routes
  static const String splash = '/';
  static const String login = '/login';
  static const String onboarding = '/onboarding';
  static const String roleSelection = '/role_selection';

  // Marketing Route
  static const String marketing = '/marketing';

  // Client Routes
  static const String clientHome = '/client';
  static const String clientProfile = '/client/profile';
  static const String clientRequestRide = '/client/request';
  static const String clientActiveTrip = '/client/trip/:tripId';

  static const String clientChat = '/client/trip/:tripId/chat';
  static const String clientHistory = '/client/history';
  static const String clientHistoryDetails = '/client/history/:tripId';

  // Rider Routes
  static const String riderHome = '/rider';
  static const String riderRegister = '/rider/register';
  static const String riderPendingApproval = '/rider/pending';
  static const String riderNavigation = '/rider/trip/:tripId/navigation';
  static const String riderChat = '/rider/trip/:tripId/chat';
  static const String riderEarnings = '/rider/earnings';
  static const String riderFees = '/rider/fees';
  static const String riderHistory = '/rider/history';

  // Admin Routes
  static const String adminDashboard = '/admin';
  static const String adminApprovals = '/admin/approvals';
  static const String adminLiveMap = '/admin/map';
  static const String adminTrips = '/admin/trips';
  static const String adminMessaging = '/admin/messaging';
  static const String adminFees = '/admin/fees';
  static const String adminCompliance = '/admin/compliance';
  static const String adminStatistics = '/admin/statistics';
}

/// Router provider
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: Routes.splash,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      // Don't redirect while auth state is loading
      if (authState.isLoading) {
        return null;
      }

      final isLoggedIn = authState.valueOrNull != null;
      final currentPath = state.matchedLocation;
      final isAuthRoute =
          currentPath == Routes.login ||
          currentPath == Routes.splash ||
          currentPath == Routes.onboarding;

      final isPublicRoute = currentPath == Routes.marketing;

      // Not logged in and trying to access protected route
      if (!isLoggedIn && !isAuthRoute && !isPublicRoute) {
        return Routes.login;
      }

      // Logged in on auth route - redirect to appropriate home
      if (isLoggedIn && isAuthRoute && currentPath != Routes.onboarding) {
        final user = authState.valueOrNull;
        if (user != null) {
          if (user.role == UserRole.none) {
            return Routes.roleSelection;
          }
          return _getHomeRoute(user.role);
        }
      }

      return null;
    },
    routes: [
      // Marketing Route
      GoRoute(
        path: Routes.marketing,
        builder: (context, state) => const MarketingScreen(),
      ),
      // Auth Routes
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.roleSelection,
        builder: (context, state) => const RoleSelectionScreen(),
      ),

      // Client Routes
      GoRoute(
        path: Routes.clientHome,
        builder: (context, state) => const ClientHomeScreen(),
      ),
      GoRoute(
        path: Routes.clientProfile,
        builder: (context, state) => const ClientProfileScreen(),
      ),
      GoRoute(
        path: Routes.clientRequestRide,
        builder: (context, state) => const RequestRideScreen(),
      ),
      GoRoute(
        path: Routes.clientActiveTrip,
        builder: (context, state) {
          final tripId = state.pathParameters['tripId']!;
          return ActiveTripScreen(tripId: tripId);
        },
      ),
      GoRoute(
        path: Routes.clientChat,
        builder: (context, state) {
          final tripId = state.pathParameters['tripId']!;
          return client_chat.ChatScreen(tripId: tripId);
        },
      ),
      GoRoute(
        path: Routes.clientHistory,
        builder: (context, state) => const client_history.HistoryScreen(),
      ),
      GoRoute(
        path: Routes.clientHistoryDetails,
        builder: (context, state) {
          final trip = state.extra as TripModel?; // Cast safely? or check null
          if (trip == null) {
            // Fallback for deep link or refresh where extra is lost
            // Ideally fetch trip by ID here using a FutureBuilder wrapper or similar
            // For now, redirect back to history
            return const client_history.HistoryScreen();
          }
          return TripDetailsScreen(trip: trip);
        },
      ),

      // Rider Routes
      GoRoute(
        path: Routes.riderHome,
        builder: (context, state) => const rider.RiderHomeScreen(),
      ),
      GoRoute(
        path: Routes.riderRegister,
        builder: (context, state) => const RegistrationScreen(),
      ),
      GoRoute(
        path: Routes.riderPendingApproval,
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: Routes.riderNavigation,
        builder: (context, state) {
          final tripId = state.pathParameters['tripId']!;
          return NavigationScreen(tripId: tripId);
        },
      ),
      GoRoute(
        path: Routes.riderChat,
        builder: (context, state) {
          final tripId = state.pathParameters['tripId']!;
          return rider_chat.ChatScreen(tripId: tripId);
        },
      ),
      GoRoute(
        path: Routes.riderEarnings,
        builder: (context, state) => const EarningsScreen(),
      ),
      GoRoute(
        path: Routes.riderFees,
        builder: (context, state) => const FeeDashboardScreen(),
      ),
      GoRoute(
        path: Routes.riderHistory,
        builder: (context, state) => const rider_history.HistoryScreen(),
      ),

      // Admin Routes
      GoRoute(
        path: Routes.adminDashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: Routes.adminApprovals,
        builder: (context, state) => const RiderApprovalScreen(),
      ),
      GoRoute(
        path: Routes.adminLiveMap,
        builder: (context, state) => const LiveMapScreen(),
      ),
      GoRoute(
        path: Routes.adminTrips,
        builder: (context, state) => const TripsMonitorScreen(),
      ),
      GoRoute(
        path: Routes.adminMessaging,
        builder: (context, state) => const MessagingScreen(),
      ),
      GoRoute(
        path: Routes.adminFees,
        builder: (context, state) => const FeeManagementScreen(),
      ),
      GoRoute(
        path: Routes.adminCompliance,
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Compliance - Coming Soon')),
        ),
      ),
      GoRoute(
        path: Routes.adminStatistics,
        builder: (context, state) => const StatisticsScreen(),
      ),
    ],
  );
});

String _getHomeRoute(UserRole role) {
  switch (role) {
    case UserRole.client:
      return Routes.clientHome;
    case UserRole.rider:
      return Routes.riderHome;
    case UserRole.admin:
      return Routes.adminDashboard;
    case UserRole.none:
      return Routes.roleSelection;
  }
}
