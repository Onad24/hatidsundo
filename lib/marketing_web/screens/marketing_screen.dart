import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router.dart';
import '../../core/theme.dart';

class MarketingScreen extends StatefulWidget {
  const MarketingScreen({super.key});

  @override
  State<MarketingScreen> createState() => _MarketingScreenState();
}

class _MarketingScreenState extends State<MarketingScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.offset > 50 && !_isScrolled) {
        setState(() => _isScrolled = true);
      } else if (_scrollController.offset <= 50 && _isScrolled) {
        setState(() => _isScrolled = false);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isDownloading = false;

  Future<void> _downloadApk() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final dio = Dio();
      final response = await dio.get(
        'https://api.github.com/repos/Onad24/hatidsundo/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final assets = response.data['assets'] as List<dynamic>? ?? [];
        String? apkUrl;

        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String?;
            break;
          }
        }

        if (apkUrl != null) {
          if (!await launchUrl(
            Uri.parse(apkUrl),
            mode: LaunchMode.externalApplication,
          )) {
            if (mounted) _showError('Could not open download link');
          }
        } else {
          if (mounted) _showError('No APK found in the latest release');
        }
      } else {
        if (mounted) _showError('Could not fetch the latest release');
      }
    } catch (e) {
      if (mounted) _showError('Failed to check for updates. Please try again.');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // For web, we force dark theme styling for the marketing page
    // to match the sleek marketing aesthetic.
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F1A),
        body: Stack(
          children: [
            // Background Orbs
            Positioned(
              top: -200,
              right: -100,
              child: Container(
                width: 600,
                height: 600,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              left: -100,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                ),
              ),
            ),

            // Content
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                _buildAppBar(),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _buildHero(context),
                      _buildFeatures(),
                      _buildHowItWorks(),
                      _buildDownloadCTA(),
                      _buildFooter(),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      elevation: _isScrolled ? 8 : 0,
      backgroundColor: _isScrolled
          ? const Color(0xFF0B0F1A).withValues(alpha: 0.95)
          : Colors.transparent,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset("assets/icons/new logo 2.png", width: 32, height: 32),
          const SizedBox(width: 12),
          const Text(
            'Hatid Sundo',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.go(Routes.login),
          child: const Text('Login', style: TextStyle(color: Colors.white70)),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: ElevatedButton(
            onPressed: _downloadApk,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Download APK'),
          ),
        ),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Flex(
        direction: isDesktop ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: isDesktop ? 1 : 0,
            child: Column(
              crossAxisAlignment: isDesktop
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.successColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Available Now',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Your Ride,\nYour Way.',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                  ),
                  textAlign: isDesktop ? TextAlign.left : TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  'Book a safe, affordable motorcycle ride in seconds. '
                  'Track your driver in real time, chat along the way, '
                  'and arrive at your destination with confidence.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white60,
                    height: 1.6,
                  ),
                  textAlign: isDesktop ? TextAlign.left : TextAlign.center,
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: isDesktop
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isDownloading ? null : _downloadApk,
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.android),
                      label: Text(
                        _isDownloading ? 'Locating APK...' : 'Download APK',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 20,
                        ),
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isDesktop) const SizedBox(width: 60),
          Expanded(
            flex: isDesktop ? 1 : 0,
            child: Padding(
              padding: EdgeInsets.only(top: isDesktop ? 0 : 60),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      "assets/icons/new logo 2.png", // Fallback to logo if hero missing
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatures() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Column(
        children: [
          const Text(
            'Everything You Need',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'A complete ride-hailing experience designed for your community.',
            style: TextStyle(fontSize: 18, color: Colors.white60),
          ),
          const SizedBox(height: 60),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 800
                  ? 3
                  : constraints.maxWidth > 500
                  ? 2
                  : 1;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 24,
                crossAxisSpacing: 24,
                childAspectRatio: 1.2,
                children: [
                  _FeatureCard(
                    icon: Icons.map,
                    title: 'Real-Time Tracking',
                    description: 'Watch your driver approach on a live map.',
                  ),
                  _FeatureCard(
                    icon: Icons.chat_bubble_outline,
                    title: 'In-Trip Chat',
                    description:
                        'Communicate directly with your driver through built-in messaging.',
                  ),
                  _FeatureCard(
                    icon: Icons.attach_money,
                    title: 'Transparent Pricing',
                    description:
                        'See the estimated fare before you book. No hidden charges.',
                  ),
                  _FeatureCard(
                    icon: Icons.verified_user_outlined,
                    title: 'Verified Drivers',
                    description:
                        'Travel with confidence knowing your driver is vetted.',
                  ),
                  _FeatureCard(
                    icon: Icons.history,
                    title: 'Trip History',
                    description:
                        'Access your complete ride history with detailed route summaries.',
                  ),
                  _FeatureCard(
                    icon: Icons.dashboard_outlined,
                    title: 'Admin Dashboard',
                    description:
                        'Operators get a full web dashboard to manage the platform.',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Container(
      width: double.infinity,
      color: Colors.white.withValues(alpha: 0.02),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Column(
        children: [
          const Text(
            'Get a Ride in 3 Easy Steps',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 60),
          Wrap(
            spacing: 40,
            runSpacing: 40,
            alignment: WrapAlignment.center,
            children: [
              _StepCard(
                number: '01',
                title: 'Set Destination',
                desc: 'Open the app and enter where you want to go.',
              ),
              _StepCard(
                number: '02',
                title: 'Get Matched',
                desc: 'A nearby verified driver accepts your request.',
              ),
              _StepCard(
                number: '03',
                title: 'Enjoy Ride',
                desc: 'Track your trip in real time and arrive safely.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCTA() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 100),
      child: Column(
        children: [
          Image.asset("assets/icons/new logo 2.png", width: 100, height: 100),
          const SizedBox(height: 24),
          const Text(
            'Ready to Ride?',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Download Hatid Sundo now and experience the most convenient way to get around.',
            style: TextStyle(fontSize: 18, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _isDownloading ? null : _downloadApk,
            icon: _isDownloading
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.android, size: 28),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isDownloading ? 'Locating...' : 'Download for',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _isDownloading ? 'Latest APK' : 'Android',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'You may need to allow "Install from Unknown Sources" in your settings.',
            style: TextStyle(fontSize: 14, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: const Center(
        child: Text(
          '© 2026 Hatid Sundo. All rights reserved.',
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryLight, size: 28),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(fontSize: 15, color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String number;
  final String title;
  final String desc;

  const _StepCard({
    required this.number,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            number,
            style: TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.white60),
          ),
        ],
      ),
    );
  }
}
