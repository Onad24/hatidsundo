import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hatid_sundo/admin_web/widgets/admin_sidebar.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

import '../../core/theme.dart';

/// Provider for riders with fees
final ridersWithFeesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final supabase = Supabase.instance.client;

  // Step 1: Get rider profiles with user info (no enum filter to avoid 22P02)
  final allRiders = await supabase
      .from('rider_profiles')
      .select('*, users!user_id(*)')
      .order('created_at', ascending: false);

  // Filter approved riders in Dart to avoid PostgREST enum cast issues
  final riders = (allRiders as List).where((r) {
    final status = r['status']?.toString() ?? '';
    return status == 'approved' && r['users'] != null;
  }).toList();

  // Step 2: Get all monthly_fees separately
  final riderUserIds = riders.map((r) => r['user_id'] as String).toList();

  if (riderUserIds.isEmpty) {
    return <Map<String, dynamic>>[];
  }

  final fees = await supabase
      .from('monthly_fees')
      .select()
      .inFilter('rider_id', riderUserIds);

  // Step 3: Group fees by rider_id
  final feesByRider = <String, List<Map<String, dynamic>>>{};
  for (final fee in (fees as List)) {
    final riderId = fee['rider_id'] as String;
    feesByRider.putIfAbsent(riderId, () => []);
    feesByRider[riderId]!.add(Map<String, dynamic>.from(fee));
  }

  // Step 4: Merge rider data with fees
  return riders.map((rider) {
    final userId = rider['user_id'] as String;
    return {
      ...rider as Map<String, dynamic>,
      'monthly_fees': feesByRider[userId] ?? [],
    };
  }).toList();
});

/// Admin fee management screen
class FeeManagementScreen extends ConsumerStatefulWidget {
  const FeeManagementScreen({super.key});

  @override
  ConsumerState<FeeManagementScreen> createState() =>
      _FeeManagementScreenState();
}

class _FeeManagementScreenState extends ConsumerState<FeeManagementScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final ridersWithFees = ref.watch(ridersWithFeesProvider);

    return Scaffold(
      body: Row(
        children: [
          const AdminSidebar(activeItem: 'Fee Management'),
          Expanded(
            child: ridersWithFees.when(
              data: (riders) {
                final filtered = riders.where((r) {
                  final name = (r['users']['name'] as String).toLowerCase();
                  return name.contains(_searchQuery.toLowerCase());
                }).toList();

                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Fee Management'),
                    automaticallyImplyLeading: false,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.download_rounded),
                        onPressed: () => _exportToCsv(filtered),
                        tooltip: 'Export CSV',
                      ),
                    ],
                  ),
                  body: Column(
                    children: [
                      // Search and filters
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Colors.white,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                onChanged: (value) =>
                                    setState(() => _searchQuery = value),
                                decoration: const InputDecoration(
                                  hintText: 'Search riders...',
                                  prefixIcon: Icon(Icons.search),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: () => _showSettlementDialog(context),
                              icon: const Icon(Icons.payments_rounded),
                              label: const Text('Batch Settlement'),
                            ),
                          ],
                        ),
                      ),

                      // Table
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: _buildDataTable(filtered),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable(List<Map<String, dynamic>> riders) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: DataTable(
        columnSpacing: 24,
        headingRowColor: WidgetStateProperty.all(AppTheme.neutral50),
        columns: const [
          DataColumn(
            label: Text('Rider', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          DataColumn(
            label: Text(
              'Status',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          DataColumn(
            label: Text(
              'Current Month',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            numeric: true,
          ),
          DataColumn(
            label: Text(
              'Outstanding',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            numeric: true,
          ),
          DataColumn(
            label: Text(
              'Total Paid',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            numeric: true,
          ),
          DataColumn(
            label: Text(
              'Actions',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
        rows: riders.map((rider) => _buildDataRow(rider)).toList(),
      ),
    );
  }

  DataRow _buildDataRow(Map<String, dynamic> rider) {
    final user = rider['users'] as Map<String, dynamic>;
    final fees = (rider['monthly_fees'] as List?) ?? [];

    // Calculate totals
    double currentMonth = 0;
    double outstanding = 0;
    double totalPaid = 0;

    for (final fee in fees) {
      final accrued = (fee['accrued_fee'] as num?)?.toDouble() ?? 0;
      final due = (fee['due_amount'] as num?)?.toDouble() ?? 0;
      final paid = (fee['paid_amount'] as num?)?.toDouble() ?? 0;

      if (!fee['is_settled']) {
        outstanding += (accrued + due - paid);
      }
      totalPaid += paid;

      // Check if current month
      final now = DateTime.now();
      if (fee['year'] == now.year && fee['month'] == now.month) {
        currentMonth = accrued;
      }
    }

    // Use a small epsilon for floating point comparison
    final hasOutstanding = outstanding > 0.01;

    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                child: Text(
                  (user['name'] as String).substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    user['name'],
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    user['email'],
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.neutral500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hasOutstanding
                  ? AppTheme.errorColor.withValues(alpha: 0.1)
                  : AppTheme.successColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              hasOutstanding ? 'Has Dues' : 'Clear',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: hasOutstanding
                    ? AppTheme.errorColor
                    : AppTheme.successColor,
              ),
            ),
          ),
        ),
        DataCell(Text('₱${currentMonth.toStringAsFixed(0)}')),
        DataCell(
          Text(
            '₱${outstanding.toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: hasOutstanding ? FontWeight.w600 : FontWeight.normal,
              color: hasOutstanding ? AppTheme.errorColor : null,
            ),
          ),
        ),
        DataCell(Text('₱${totalPaid.toStringAsFixed(0)}')),
        DataCell(
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.visibility_rounded, size: 18),
                onPressed: () => _showFeeHistory(rider),
                tooltip: 'View History',
              ),
              if (hasOutstanding)
                IconButton(
                  icon: const Icon(Icons.payments_rounded, size: 18),
                  onPressed: () => _showSettleDialog(rider, outstanding),
                  tooltip: 'Settle Dues',
                  color: AppTheme.successColor,
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showFeeHistory(Map<String, dynamic> rider) {
    final user = rider['users'] as Map<String, dynamic>;
    final fees = (rider['monthly_fees'] as List?) ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Fee History - ${user['name']}'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: fees.isEmpty
              ? const Center(child: Text('No fee records'))
              : ListView.builder(
                  itemCount: fees.length,
                  itemBuilder: (context, index) {
                    final fee = fees[index];
                    final monthName = DateFormat(
                      'MMMM yyyy',
                    ).format(DateTime(fee['year'], fee['month']));
                    return ListTile(
                      title: Text(monthName),
                      subtitle: Text(
                        'Accrued: ₱${fee['accrued_fee']} | Due: ₱${fee['due_amount']} | Paid: ₱${fee['paid_amount']}',
                      ),
                      trailing: fee['is_settled']
                          ? const Chip(
                              label: Text('Settled'),
                              backgroundColor: Colors.greenAccent,
                            )
                          : const Chip(
                              label: Text('Pending'),
                              backgroundColor: Colors.orangeAccent,
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSettleDialog(Map<String, dynamic> rider, double outstanding) {
    final amountController = TextEditingController(
      text: outstanding.toStringAsFixed(0),
    );
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settle Fees'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₱',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text) ?? 0;
              if (amount > 0) {
                try {
                  // Call the new RPC function to bypass Edge Function 401 errors
                  final supabase = Supabase.instance.client;
                  await supabase.rpc(
                    'admin_settle_fees',
                    params: {
                      'p_rider_id': rider['user_id'],
                      'p_amount': amount,
                      'p_notes': notesController.text.isNotEmpty
                          ? notesController.text
                          : null,
                    },
                  );
                  ref.invalidate(ridersWithFeesProvider);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Fees settled successfully'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error settling fees: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Settle'),
          ),
        ],
      ),
    );
  }

  void _showSettlementDialog(BuildContext context) {
    // TODO: Implement batch settlement dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Batch settlement coming soon')),
    );
  }

  Future<void> _exportToCsv(List<Map<String, dynamic>> riders) async {
    try {
      final rows = <List<dynamic>>[
        [
          'Rider Name',
          'Email',
          'Status',
          'Current Month Accrued',
          'Outstanding Balance',
          'Total Paid',
        ],
      ];

      for (final rider in riders) {
        final user = rider['users'] as Map<String, dynamic>;
        final fees = (rider['monthly_fees'] as List?) ?? [];

        double currentMonth = 0;
        double outstanding = 0;
        double totalPaid = 0;

        for (final fee in fees) {
          final accrued = (fee['accrued_fee'] as num?)?.toDouble() ?? 0;
          final due = (fee['due_amount'] as num?)?.toDouble() ?? 0;
          final paid = (fee['paid_amount'] as num?)?.toDouble() ?? 0;

          if (!fee['is_settled']) {
            outstanding += (accrued + due - paid);
          }
          totalPaid += paid;

          final now = DateTime.now();
          if (fee['year'] == now.year && fee['month'] == now.month) {
            currentMonth = accrued;
          }
        }

        rows.add([
          user['name'],
          user['email'],
          rider['status'],
          currentMonth.toStringAsFixed(2),
          outstanding.toStringAsFixed(2),
          totalPaid.toStringAsFixed(2),
        ]);
      }

      final csvData = const ListToCsvConverter().convert(rows);

      // Download
      final bytes = utf8.encode(csvData);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute(
          'download',
          'fee_report_${DateTime.now().toIso8601String()}.csv',
        )
        ..click();

      html.Url.revokeObjectUrl(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export downloaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}
