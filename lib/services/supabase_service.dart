import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Supabase client provider
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Supabase service for database operations
class SupabaseService {
  final SupabaseClient _client;

  SupabaseService(this._client);

  SupabaseClient get client => _client;

  // Auth shortcuts
  GoTrueClient get auth => _client.auth;
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => currentUser?.id;

  // Database shortcuts
  SupabaseQueryBuilder from(String table) => _client.from(table);

  // Storage shortcuts
  SupabaseStorageClient get storage => _client.storage;

  // Realtime shortcuts
  RealtimeClient get realtime => _client.realtime;

  // Functions shortcuts
  FunctionsClient get functions => _client.functions;

  /// Initialize Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }

  /// Subscribe to a realtime channel
  RealtimeChannel channel(String name) {
    return _client.channel(name);
  }

  /// Call an Edge Function
  Future<FunctionResponse> callFunction(
    String functionName, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    return await _client.functions.invoke(
      functionName,
      body: body,
      headers: headers,
    );
  }
}

/// Supabase service provider
final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SupabaseService(client);
});
