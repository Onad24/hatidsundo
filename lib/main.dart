import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'core/router.dart';
import 'core/theme.dart';

/// Main entry point for the Hatid Sundo ride-hailing application
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Validate environment configuration (skip in debug mode)
  if (!EnvConfig.isDebug) {
    EnvConfig.validate();
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // FCM is initialized lazily when needed on mobile platforms

  runApp(const ProviderScope(child: HatidSundoApp()));
}

/// Main application widget
class HatidSundoApp extends ConsumerWidget {
  const HatidSundoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
