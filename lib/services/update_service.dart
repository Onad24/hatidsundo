import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/theme.dart';

/// Service to check GitHub releases for app updates
class UpdateService {
  static const String _githubOwner = 'Onad24';
  static const String _githubRepo = 'hatidsundo';
  static const String _apiUrl =
      'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest';

  final Dio _dio = Dio();

  /// Check for updates and show a dialog if a newer version is available.
  /// Returns true if an update is available.
  Future<bool> checkForUpdate(BuildContext context) async {
    try {
      final response = await _dio.get(
        _apiUrl,
        options: Options(
          headers: {'Accept': 'application/vnd.github.v3+json'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode != 200 || response.data == null) return false;

      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final releaseName = data['name'] as String? ?? tagName;
      final body = data['body'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '';
      final assets = data['assets'] as List<dynamic>? ?? [];

      // Parse the version from the tag (strip leading 'v' if present)
      final latestVersion = tagName.startsWith('v')
          ? tagName.substring(1)
          : tagName;

      if (latestVersion.isEmpty) return false;

      final currentVersion = AppConstants.appVersion;

      if (_isNewerVersion(latestVersion, currentVersion)) {
        // Find APK download URL from assets
        String? apkUrl;
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String?;
            break;
          }
        }

        if (context.mounted) {
          _showUpdateDialog(
            context,
            latestVersion: latestVersion,
            releaseName: releaseName,
            releaseNotes: body,
            apkUrl: apkUrl,
            releasePageUrl: htmlUrl,
          );
        }
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Update check failed (non-blocking): $e');
      return false;
    }
  }

  /// Compare two semantic version strings (e.g., "1.2.0" vs "1.1.0").
  /// Returns true if [latest] is newer than [current].
  bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      // Pad shorter list with zeros
      while (latestParts.length < 3) latestParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);

      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false; // versions are equal
    } catch (_) {
      // If parsing fails, do a simple string comparison
      return latest != current;
    }
  }

  /// Show a Material 3 styled update dialog
  void _showUpdateDialog(
    BuildContext context, {
    required String latestVersion,
    required String releaseName,
    required String releaseNotes,
    String? apkUrl,
    required String releasePageUrl,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryColor,
                AppTheme.primaryColor.withValues(alpha: 0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.system_update_rounded,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'Update Available',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'v${AppConstants.appVersion} → v$latestVersion',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            if (releaseName.isNotEmpty) ...[
              Text(
                releaseName,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (releaseNotes.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    releaseNotes,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Later',
              style: TextStyle(
                fontFamily: 'Outfit',
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              final url = apkUrl ?? releasePageUrl;
              if (url.isNotEmpty) {
                launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text(
              'Update Now',
              style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Update service provider
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());
