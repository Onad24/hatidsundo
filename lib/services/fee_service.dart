import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/fee_model.dart';
import 'supabase_service.dart';

/// Fee service for managing rider fees
class FeeService {
  final SupabaseService _supabaseService;

  FeeService(this._supabaseService);

  /// Get the ISO week number for a given date
  int _isoWeekNumber(DateTime date) {
    // ISO 8601 week number calculation
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final weekday = date.weekday; // 1=Mon, 7=Sun
    return ((dayOfYear - weekday + 10) / 7).floor();
  }

  /// Get current week fee record for a rider
  Future<MonthlyFeeModel?> getCurrentWeekFee(String riderId) async {
    final now = DateTime.now();
    final week = _isoWeekNumber(now);

    final result = await _supabaseService
        .from(AppConstants.monthlyFeesTable)
        .select()
        .eq('rider_id', riderId)
        .eq('year', now.year)
        .eq('week', week)
        .maybeSingle();

    if (result == null) return null;
    return MonthlyFeeModel.fromJson(result);
  }

  /// Get fee history for a rider
  Future<List<MonthlyFeeModel>> getFeeHistory(
    String riderId, {
    int limit = 12,
  }) async {
    final result = await _supabaseService
        .from(AppConstants.monthlyFeesTable)
        .select()
        .eq('rider_id', riderId)
        .order('year', ascending: false)
        .order('month', ascending: false)
        .limit(limit);

    return (result as List).map((j) => MonthlyFeeModel.fromJson(j)).toList();
  }

  /// Check if rider has outstanding dues (for lockout)
  Future<bool> hasOutstandingDues(String riderId) async {
    final result = await _supabaseService
        .from(AppConstants.monthlyFeesTable)
        .select('due_amount, is_settled')
        .eq('rider_id', riderId)
        .gt('due_amount', 0)
        .eq('is_settled', false)
        .limit(1)
        .maybeSingle();

    return result != null;
  }

  /// Get total outstanding dues
  Future<double> getTotalOutstandingDues(String riderId) async {
    final result = await _supabaseService.client.rpc(
      'get_total_outstanding_dues',
      params: {'p_rider_id': riderId},
    );
    return (result as num?)?.toDouble() ?? 0.0;
  }

  /// Get fee events for a rider
  Future<List<FeeEventModel>> getFeeEvents(
    String riderId, {
    int limit = 50,
    String? month,
  }) async {
    var query = _supabaseService
        .from(AppConstants.feeEventsTable)
        .select()
        .eq('rider_id', riderId)
        .order('created_at', ascending: false)
        .limit(limit);

    final result = await query;
    return (result as List).map((j) => FeeEventModel.fromJson(j)).toList();
  }

  /// Admin: Settle fees for a rider
  Future<void> settleFees(
    String riderId,
    String month, {
    required String adminId,
    String? notes,
  }) async {
    await _supabaseService.callFunction(
      'settle_fees',
      body: {
        'rider_id': riderId,
        'year': int.tryParse(month.split('-')[0]) ?? DateTime.now().year,
        'month': int.tryParse(month.split('-')[1]) ?? DateTime.now().month,
        'admin_id': adminId,
        'notes': notes,
      },
    );
  }

  /// Admin: Add manual adjustment
  Future<void> addAdjustment(
    String riderId, {
    required double amount,
    required String description,
    required String adminId,
  }) async {
    await _supabaseService.from(AppConstants.feeEventsTable).insert({
      'rider_id': riderId,
      'amount': amount,
      'event_type': 'adjustment',
      'description': description,
      'created_by': adminId,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Update monthly fee accrued amount
    final now = DateTime.now();
    await _supabaseService.client.rpc(
      'add_fee_adjustment',
      params: {
        'p_rider_id': riderId,
        'p_year': now.year,
        'p_month': now.month,
        'p_amount': amount,
      },
    );
  }

  /// Admin: Add credit (negative adjustment)
  Future<void> addCredit(
    String riderId, {
    required double amount,
    required String description,
    required String adminId,
  }) async {
    await addAdjustment(
      riderId,
      amount: -amount.abs(), // Credits are negative
      description: 'Credit: $description',
      adminId: adminId,
    );
  }

  /// Admin: Get all riders with outstanding dues
  Future<List<Map<String, dynamic>>> getRidersWithOutstandingDues() async {
    final result = await _supabaseService.client.rpc(
      'get_riders_with_outstanding_dues',
    );
    return List<Map<String, dynamic>>.from(result ?? []);
  }

  /// Admin: Get monthly statistics
  Future<Map<String, dynamic>> getMonthlyStatistics(String month) async {
    final result = await _supabaseService.client.rpc(
      'get_monthly_fee_statistics',
      params: {'p_month': month},
    );
    return Map<String, dynamic>.from(result ?? {});
  }

  /// Admin: Export fee data as CSV
  Future<String> exportFeesAsCsv({
    required String startMonth,
    required String endMonth,
  }) async {
    final result = await _supabaseService.client.rpc(
      'export_fee_data',
      params: {'start_month': startMonth, 'end_month': endMonth},
    );
    return result ?? '';
  }
}

/// Fee service provider
final feeServiceProvider = Provider<FeeService>((ref) {
  final supabaseService = ref.watch(supabaseServiceProvider);
  return FeeService(supabaseService);
});
