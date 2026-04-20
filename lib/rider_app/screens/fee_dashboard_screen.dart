import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../state/state.dart';

/// Rider fee dashboard screen
class FeeDashboardScreen extends ConsumerWidget {
  const FeeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feeState = ref.watch(riderFeeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fee Dashboard'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: feeState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : feeState.error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: AppTheme.errorColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Unable to load fee data',
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.neutral900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      feeState.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 14,
                        color: AppTheme.neutral500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.read(riderFeeProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref.read(riderFeeProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Outstanding dues warning
                  if (feeState.hasOutstandingDues)
                    _buildOutstandingDuesCard(feeState),

                  // Current week summary
                  _buildCurrentWeekCard(feeState),
                  const SizedBox(height: 20),

                  // Fee breakdown
                  _buildFeeBreakdown(feeState),
                  const SizedBox(height: 20),

                  // Recent fee events
                  _buildRecentEvents(feeState),
                ],
              ),
            ),
    );
  }

  Widget _buildOutstandingDuesCard(RiderFeeState feeState) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded, color: Colors.white),
              const SizedBox(width: 8),
              const Text(
                'Outstanding Dues',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '₱${feeState.totalOutstanding.toStringAsFixed(0)}',
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You cannot go online until these dues are settled. Please contact admin for settlement.',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentWeekCard(RiderFeeState feeState) {
    final now = DateTime.now();
    // ISO week number
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final weekNumber = ((dayOfYear - now.weekday + 10) / 7).floor();
    final weekLabel = 'Week $weekNumber, ${now.year}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.elevatedShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            weekLabel,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${feeState.currentWeekFee?.accruedFee.toStringAsFixed(0) ?? '0'}',
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'accrued this week',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  '10% platform fee per trip — settled weekly',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeBreakdown(RiderFeeState feeState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fee Breakdown',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _buildBreakdownRow(
            'Current Week Accrued',
            feeState.currentWeekFee?.accruedFee ?? 0,
          ),
          const Divider(height: 24),
          _buildBreakdownRow(
            'Previous Dues',
            feeState.currentWeekFee?.dueAmount ?? 0,
            isHighlight: true,
          ),
          const Divider(height: 24),
          _buildBreakdownRow(
            'Total Outstanding',
            feeState.totalOutstanding,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(
    String label,
    double amount, {
    bool isHighlight = false,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 14,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            color: isHighlight ? AppTheme.errorColor : AppTheme.neutral700,
          ),
        ),
        Text(
          '₱${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 16,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            color: isHighlight ? AppTheme.errorColor : AppTheme.neutral900,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentEvents(RiderFeeState feeState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (feeState.feeEvents.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.neutral100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'No fee events yet',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  color: AppTheme.neutral500,
                ),
              ),
            ),
          )
        else
          ...feeState.feeEvents.take(10).map((event) {
            final dateFormat = DateFormat('MMM d, h:mm a');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: event.amount >= 0
                          ? AppTheme.errorColor.withValues(alpha: 0.1)
                          : AppTheme.successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      event.amount >= 0
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: event.amount >= 0
                          ? AppTheme.errorColor
                          : AppTheme.successColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.description,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          dateFormat.format(event.createdAt),
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 12,
                            color: AppTheme.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${event.amount >= 0 ? '+' : ''}₱${event.amount.abs().toStringAsFixed(0)}',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: event.amount >= 0
                          ? AppTheme.errorColor
                          : AppTheme.successColor,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
