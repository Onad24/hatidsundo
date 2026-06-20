import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// In-app Privacy Policy screen
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hatid Sundo Privacy Policy',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.neutral900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Last updated: June 20, 2026',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  color: AppTheme.neutral500,
                ),
              ),
              const SizedBox(height: 24),
              _buildSection(
                '1. Information We Collect',
                'We collect information you provide directly to us, such as when you create or modify your account, request on-demand services, contact customer support, or otherwise communicate with us. This information may include: name, email, phone number, profile picture, payment method, and other information you choose to provide.',
              ),
              _buildSection(
                '2. How We Use Your Information',
                'We may use the information we collect about you to provide, maintain, and improve our services, such as to facilitate payments, send receipts, provide products and services you request (and send related information), develop new features, provide customer support, develop safety features, authenticate users, and send product updates and administrative messages.',
              ),
              _buildSection(
                '3. Location Information',
                'When you use the services for transportation, we collect precise location data about the trip from the Hatid Sundo app. If you permit the Hatid Sundo app to access location services through the permission system used by your mobile operating system, we may also collect the precise location of your device when the app is running in the foreground or background.',
              ),
              _buildSection(
                '4. Sharing of Information',
                'We may share the information we collect about you with drivers to enable them to provide the services you request. For example, we share your name, photo (if you provide one), and pickup and/or drop-off locations with drivers.',
              ),
              _buildSection(
                '5. Data Retention',
                'We retain your information for as long as your account is active or as needed to provide you services. You may request deletion of your account and associated data at any time by contacting our support team.',
              ),
              _buildSection(
                '6. Security',
                'We take reasonable measures to help protect information about you from loss, theft, misuse and unauthorized access, disclosure, alteration, and destruction.',
              ),
              _buildSection(
                '7. Contact Us',
                'If you have any questions about this Privacy Policy, please contact us at:\n\nsupport@hatidsundo.com',
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  '© 2026 Hatid Sundo. All rights reserved.',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 12,
                    color: AppTheme.neutral400,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 14,
              color: AppTheme.neutral700,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
