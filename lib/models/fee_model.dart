import 'package:json_annotation/json_annotation.dart';

/// Weekly fee record for a rider
class MonthlyFeeModel {
  final String id;
  @JsonKey(name: 'rider_id')
  final String riderId;
  final int year;
  final int month;
  final int week;
  @JsonKey(name: 'accrued_fee')
  final double accruedFee;
  @JsonKey(name: 'due_amount')
  final double dueAmount;
  @JsonKey(name: 'paid_amount')
  final double paidAmount;
  @JsonKey(name: 'is_settled')
  final bool isSettled;
  @JsonKey(name: 'settled_at')
  final DateTime? settledAt;
  @JsonKey(name: 'settled_by')
  final String? settledBy;
  final String? notes;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  const MonthlyFeeModel({
    required this.id,
    required this.riderId,
    required this.year,
    required this.month,
    required this.week,
    this.accruedFee = 0.0,
    this.dueAmount = 0.0,
    this.paidAmount = 0.0,
    this.isSettled = false,
    this.settledAt,
    this.settledBy,
    this.notes,
    required this.createdAt,
  });

  factory MonthlyFeeModel.fromJson(Map<String, dynamic> json) =>
      MonthlyFeeModel(
        id: json['id'] as String,
        riderId: json['rider_id'] as String,
        year: json['year'] as int,
        month: json['month'] as int,
        week: json['week'] as int? ?? 1,
        accruedFee: (json['accrued_fee'] as num?)?.toDouble() ?? 0.0,
        dueAmount: (json['due_amount'] as num?)?.toDouble() ?? 0.0,
        paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
        isSettled: json['is_settled'] as bool? ?? false,
        settledAt: json['settled_at'] == null
            ? null
            : DateTime.parse(json['settled_at'] as String),
        settledBy: json['settled_by'] as String?,
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'rider_id': riderId,
    'year': year,
    'month': month,
    'week': week,
    'accrued_fee': accruedFee,
    'due_amount': dueAmount,
    'paid_amount': paidAmount,
    'is_settled': isSettled,
    'settled_at': settledAt?.toIso8601String(),
    'settled_by': settledBy,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
  };

  MonthlyFeeModel copyWith({
    String? id,
    String? riderId,
    int? year,
    int? month,
    int? week,
    double? accruedFee,
    double? dueAmount,
    double? paidAmount,
    bool? isSettled,
    DateTime? settledAt,
    String? settledBy,
    String? notes,
    DateTime? createdAt,
  }) {
    return MonthlyFeeModel(
      id: id ?? this.id,
      riderId: riderId ?? this.riderId,
      year: year ?? this.year,
      month: month ?? this.month,
      week: week ?? this.week,
      accruedFee: accruedFee ?? this.accruedFee,
      dueAmount: dueAmount ?? this.dueAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      isSettled: isSettled ?? this.isSettled,
      settledAt: settledAt ?? this.settledAt,
      settledBy: settledBy ?? this.settledBy,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get hasOutstandingDues => dueAmount > 0 && !isSettled;
  double get totalOwed => accruedFee + dueAmount;
}

/// Fee event for tracking individual fee transactions
class FeeEventModel {
  final String id;
  @JsonKey(name: 'rider_id')
  final String riderId;
  @JsonKey(name: 'trip_id')
  final String? tripId;
  final double amount;
  @JsonKey(name: 'event_type')
  final String eventType; // platform_fee, adjustment, credit, settlement
  final String description;
  @JsonKey(name: 'created_by')
  final String? createdBy;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  const FeeEventModel({
    required this.id,
    required this.riderId,
    this.tripId,
    required this.amount,
    required this.eventType,
    required this.description,
    this.createdBy,
    required this.createdAt,
  });

  factory FeeEventModel.fromJson(Map<String, dynamic> json) => FeeEventModel(
    id: json['id'] as String,
    riderId: json['rider_id'] as String,
    tripId: json['trip_id'] as String?,
    amount: (json['amount'] as num).toDouble(),
    eventType: json['event_type'] as String,
    description: json['description'] as String,
    createdBy: json['created_by'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'rider_id': riderId,
    'trip_id': tripId,
    'amount': amount,
    'event_type': eventType,
    'description': description,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
  };

  bool get isPlatformFee => eventType == 'platform_fee';
  bool get isAdjustment => eventType == 'adjustment';
  bool get isCredit => eventType == 'credit';
  bool get isSettlement => eventType == 'settlement';
}
