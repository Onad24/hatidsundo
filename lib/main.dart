import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'services/fcm_service.dart';
import 'services/update_service.dart';

/// Main entry point for the Hatid Sundo ride-hailing application
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Validate environment configuration (skip in debug mode)
  if (!EnvConfig.isDebug) {
    EnvConfig.validate();
  }

  // Initialize Firebase (skip on web — no web app configured yet)
  if (!kIsWeb) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const ProviderScope(child: HatidSundoApp()));
}

/// Main application widget
class HatidSundoApp extends ConsumerStatefulWidget {
  const HatidSundoApp({super.key});

  @override
  ConsumerState<HatidSundoApp> createState() => _HatidSundoAppState();
}

class _HatidSundoAppState extends ConsumerState<HatidSundoApp> {
  @override
  void initState() {
    super.initState();
    // Initialize FCM after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFcm();
      _checkForUpdates();
    });
  }

  Future<void> _initFcm() async {
    try {
      final fcmService = ref.read(fcmServiceProvider);
      await fcmService.initialize();

      // Save token on login
      await fcmService.onUserLogin();

      // Subscribe riders to 'riders' topic for new ride notifications
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // We'll subscribe to user-specific and role-specific topics
        await fcmService.subscribeToTopic('user_${user.id}');
      }
    } catch (e) {
      debugPrint('FCM init error (non-blocking): $e');
    }
  }

  Future<void> _checkForUpdates() async {
    // Small delay to let the app fully render first
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    try {
      final updateService = ref.read(updateServiceProvider);
      await updateService.checkForUpdate(context);
    } catch (e) {
      debugPrint('Update check failed (non-blocking): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: _getAppTitle(),
      debugShowCheckedModeBanner: false,

      // Theme configuration
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      // Router configuration
      routerConfig: router,
    );
  }

  /// Get app title based on flavor
  String _getAppTitle() {
    switch (EnvConfig.appFlavor) {
      case 'client':
        return 'Hatid Sundo';
      case 'rider':
        return 'Hatid Sundo Driver';
      case 'admin':
        return 'Hatid Sundo Admin';
      default:
        return 'Hatid Sundo';
    }
  }
}
