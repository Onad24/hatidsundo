import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/fee_model.dart';
import '../services/fee_service.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';

/// Fee state for rider
class RiderFeeState {
  final MonthlyFeeModel? currentWeekFee;
  final List<MonthlyFeeModel> feeHistory;
  final List<FeeEventModel> feeEvents;
  final bool hasOutstandingDues;
  final double totalOutstanding;
  final bool isLoading;
  final String? error;

  const RiderFeeState({
    this.currentWeekFee,
    this.feeHistory = const [],
    this.feeEvents = const [],
    this.hasOutstandingDues = false,
    this.totalOutstanding = 0.0,
    this.isLoading = false,
    this.error,
  });

  RiderFeeState copyWith({
    MonthlyFeeModel? currentWeekFee,
    List<MonthlyFeeModel>? feeHistory,
    List<FeeEventModel>? feeEvents,
    bool? hasOutstandingDues,
    double? totalOutstanding,
    bool? isLoading,
    String? error,
  }) {
    return RiderFeeState(
      currentWeekFee: currentWeekFee ?? this.currentWeekFee,
      feeHistory: feeHistory ?? this.feeHistory,
      feeEvents: feeEvents ?? this.feeEvents,
      hasOutstandingDues: hasOutstandingDues ?? this.hasOutstandingDues,
      totalOutstanding: totalOutstanding ?? this.totalOutstanding,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Rider fee notifier
class RiderFeeNotifier extends StateNotifier<RiderFeeState> {
  final FeeService _feeService;
  final String? _riderId;

  RiderFeeNotifier(this._feeService, this._riderId)
    : super(const RiderFeeState()) {
    _loadFeeData();
  }

  Future<void> _loadFeeData() async {
    if (_riderId == null) return;

    final riderId = _riderId; // Local non-nullable copy after null check
    state = state.copyWith(isLoading: true);
    try {
      final currentFee = await _feeService.getCurrentWeekFee(riderId);
      final history = await _feeService.getFeeHistory(riderId);
      final events = await _feeService.getFeeEvents(riderId);
      final hasOutstanding = await _feeService.hasOutstandingDues(riderId);
      final totalOutstanding = await _feeService.getTotalOutstandingDues(
        riderId,
      );

      // Check mounted after async gap to avoid post-dispose crash
      if (!mounted) return;

      state = state.copyWith(
        currentWeekFee: currentFee,
        feeHistory: history,
        feeEvents: events,
        hasOutstandingDues: hasOutstanding,
        totalOutstanding: totalOutstanding,
        isLoading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Refresh fee data
  Future<void> refresh() async {
    await _loadFeeData();
  }
}

/// Rider fee state provider
final riderFeeProvider = StateNotifierProvider<RiderFeeNotifier, RiderFeeState>(
  (ref) {
    final feeService = ref.watch(feeServiceProvider);
    final user = ref.watch(currentUserProvider);
    return RiderFeeNotifier(feeService, user?.id);
  },
);

/// Can go online provider (checks outstanding dues)
final canGoOnlineProvider = Provider<bool>((ref) {
  final feeState = ref.watch(riderFeeProvider);
  return !feeState.hasOutstandingDues;
});

/// Rider profile status provider — fetches the rider's approval status
final riderProfileStatusProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.isRider) return null;

  final supabase = ref.watch(supabaseServiceProvider);
  final result = await supabase.client
      .from(AppConstants.ridersProfilesTable)
      .select('status')
      .eq('user_id', user.id)
      .maybeSingle();

  return result?['status'] as String?;
});

/// Whether the rider can accept ride requests.
/// Returns false if rider is not approved OR has outstanding dues.
final canAcceptRidesProvider = Provider<bool>((ref) {
  final profileStatus = ref.watch(riderProfileStatusProvider);
  final feeState = ref.watch(riderFeeProvider);

  final isApproved = profileStatus.whenOrNull(data: (status) => status == 'approved') ?? false;
  final hasNoDues = !feeState.hasOutstandingDues;

  return isApproved && hasNoDues;
});

/// Reason why rider cannot accept rides (for UI prompts)
final cannotAcceptReason = Provider<String?>((ref) {
  final profileStatus = ref.watch(riderProfileStatusProvider);
  final feeState = ref.watch(riderFeeProvider);

  final status = profileStatus.valueOrNull;
  if (status == null) return null; // Still loading
  if (status != 'approved') {
    return 'Your account is pending approval. You cannot accept ride requests yet.';
  }
  if (feeState.hasOutstandingDues) {
    return 'You have unsettled fees (₱${feeState.totalOutstanding.toStringAsFixed(0)}). Please settle your balance to accept rides.';
  }
  return null;
});
