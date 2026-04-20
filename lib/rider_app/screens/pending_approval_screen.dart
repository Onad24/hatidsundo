import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';

/// Pending approval screen for drivers awaiting verification
class PendingApprovalScreen extends ConsumerWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Illustration
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    size: 80,
                    color: AppTheme.warningColor,
                  ),
                ),
                const SizedBox(height: 40),

                // Title
                const Text(
                  'Application Submitted!',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.neutral900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Description
                const Text(
                  'Your driver application is being reviewed by our team. We\'ll notify you once your account has been approved.',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 16,
                    color: AppTheme.neutral500,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Status card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Column(
                    children: [
                      _buildStatusRow(
                        icon: Icons.check_circle_rounded,
                        title: 'Application Received',
                        isComplete: true,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            height: 24,
                            child: VerticalDivider(
                              thickness: 2,
                              color: AppTheme.successColor,
                            ),
                          ),
                        ),
                      ),
                      _buildStatusRow(
                        icon: Icons.pending_rounded,
                        title: 'Document Verification',
                        isComplete: false,
                        isCurrent: true,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            height: 24,
                            child: VerticalDivider(
                              thickness: 2,
                              color: AppTheme.neutral300,
                            ),
                          ),
                        ),
                      ),
                      _buildStatusRow(
                        icon: Icons.circle_outlined,
                        title: 'Account Activation',
                        isComplete: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Estimated time
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.infoColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        color: AppTheme.infoColor,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Usually takes 24-48 hours',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 14,
                          color: AppTheme.infoColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String title,
    required bool isComplete,
    bool isCurrent = false,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: isComplete
              ? AppTheme.successColor
              : isCurrent
              ? AppTheme.warningColor
              : AppTheme.neutral300,
          size: 24,
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 15,
            fontWeight: isComplete || isCurrent
                ? FontWeight.w600
                : FontWeight.w400,
            color: isComplete || isCurrent
                ? AppTheme.neutral800
                : AppTheme.neutral400,
          ),
        ),
      ],
    );
  }
}
