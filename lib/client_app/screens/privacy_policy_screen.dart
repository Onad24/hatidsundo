import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// In-app Privacy Policy screen & bottom sheet helper
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  /// Helper to show privacy policy as a modal bottom sheet
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _PrivacyPolicySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy & Data Safety',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.neutral900,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.neutral200, height: 1),
        ),
      ),
      body: const _PrivacyPolicyContent(),
    );
  }
}

class _PrivacyPolicySheet extends StatelessWidget {
  const _PrivacyPolicySheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.neutral300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Privacy & Data Safety',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.neutral900,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                  color: AppTheme.neutral600,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: _PrivacyPolicyContent(),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPolicyContent extends StatelessWidget {
  const _PrivacyPolicyContent();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trust Badge
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.08),
                  AppTheme.secondaryColor.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  color: AppTheme.primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Philippine DPA (RA 10173) Compliant',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your personal data is encrypted, strictly guarded, and never sold to third parties.',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 12,
                          color: AppTheme.neutral700,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Key Highlights Cards
          const Text(
            'Core Commitments',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.neutral900,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildPillarCard(
                  icon: Icons.location_on_outlined,
                  title: 'Location Transparency',
                  desc: 'Used only during active rides for matching & route safety.',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPillarCard(
                  icon: Icons.lock_outline_rounded,
                  title: 'Encrypted Records',
                  desc: 'Supabase TLS 1.3 encryption for accounts and chats.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Detailed Sections
          _buildPolicySection(
            stepNumber: '1',
            title: 'Information We Collect',
            content:
                '• Account Info: Name, email address, phone number, and avatar provided via Google Sign-In.\n'
                '• Trip & Geolocation: Real-time GPS coordinates during ride booking and trip execution to calculate fair fares and enable driver navigation.\n'
                '• Communication: In-trip chat messages exchanged between passengers and assigned drivers.\n'
                '• Vehicle / Licensing Data (Drivers): Vehicle model, year, plate number, OR/CR documents, and driver license photos for identity verification.',
          ),
          _buildPolicySection(
            stepNumber: '2',
            title: 'How We Use Your Data',
            content:
                '• Connecting passengers with nearby drivers in Tanauan and Leyte.\n'
                '• Calculating transparent, rate-card accurate trip fares.\n'
                '• Ensuring passenger and driver safety through real-time tracking.\n'
                '• Sending essential trip notifications via Firebase Cloud Messaging.',
          ),
          _buildPolicySection(
            stepNumber: '3',
            title: 'Data Sharing & Protection',
            content:
                '• Drivers only see passenger pickup location and contact name during an active booking.\n'
                '• We do not sell or monetize personal information to advertising brokers.\n'
                '• Data is secured with Row Level Security (RLS) policies ensuring users only access their own authorized records.',
          ),
          _buildPolicySection(
            stepNumber: '4',
            title: 'Your Rights & Data Deletion',
            content:
                'Under the Data Privacy Act of 2012, you have the right to access, correct, or request the complete deletion of your account and personal records.\n\n'
                'To request account deletion or data export, email our Data Protection Officer at: privacy@hatidsundo.com',
          ),
          const SizedBox(height: 16),

          // Contact Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.neutral100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.neutral200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.mail_outline_rounded, size: 18, color: AppTheme.primaryColor),
                    SizedBox(width: 8),
                    Text(
                      'Data Protection Inquiries',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.neutral900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Hatid Sundo Mobility Services\nTanauan, Leyte, Philippines\nEmail: privacy@hatidsundo.com',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 13,
                    color: AppTheme.neutral600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Version 1.1.8 • Last Updated August 2026',
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
    );
  }

  static Widget _buildPillarCard({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.neutral100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryColor),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.neutral900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 11,
              color: AppTheme.neutral600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildPolicySection({
    required String stepNumber,
    required String title,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    stepNumber,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.neutral900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              content,
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 13,
                color: AppTheme.neutral700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
