import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../widgets/loading_overlay.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/stat_card.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {
    'active_trips': 0,
    'active_drivers': 0,
    'total_revenue': 0.0,
    'total_outstanding': 0.0,
    'recent_trips_24h': 0,
  };

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      final supabase = Supabase.instance.client;

      // 1. Get active trips count
      final activeTripsRes = await supabase.from('trips').select('id').inFilter(
        'status',
        ['pending', 'accepted', 'driver_arriving', 'in_progress'],
      );

      // 2. Get active drivers count
      final activeDriversRes = await supabase
          .from('driver_locations')
          .select('driver_id')
          .eq('is_online', true);

      // 3. Get total revenue (accrued fees) & outstanding
      final feesRes = await supabase
          .from('monthly_fees')
          .select('accrued_fee, due_amount');

      double totalRevenue = 0;
      double totalOutstanding = 0;

      for (var row in feesRes) {
        totalRevenue += (row['accrued_fee'] as num?)?.toDouble() ?? 0;
        totalOutstanding += (row['due_amount'] as num?)?.toDouble() ?? 0;
      }

      // 4. Get recent trips (last 24h)
      final yesterday = DateTime.now()
          .subtract(const Duration(days: 1))
          .toUtc()
          .toIso8601String();
      final recentTripsRes = await supabase
          .from('trips')
          .select('id')
          .gte('created_at', yesterday);

      if (mounted) {
        setState(() {
          _stats = {
            'active_trips': (activeTripsRes as List).length,
            'active_drivers': (activeDriversRes as List).length,
            'total_revenue': totalRevenue,
            'total_outstanding': totalOutstanding,
            'recent_trips_24h': (recentTripsRes as List).length,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading stats: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const AdminSidebar(activeItem: 'Statistics'),
          Expanded(
            child: _isLoading
                ? const LoadingOverlay()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Platform Statistics',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 24),
                        _buildSummaryCards(),
                        const SizedBox(height: 32),
                        _buildRevenueChart(),
                        const SizedBox(height: 32),
                        _buildTripActivityChart(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            StatCard(
              title: 'Total Revenue',
              value: '₱${_stats['total_revenue']}',
              icon: Icons.attach_money,
              color: Colors.green,
            ),
            StatCard(
              title: 'Outstanding Fees',
              value: '₱${_stats['total_outstanding']}',
              icon: Icons.money_off,
              color: Colors.orange,
            ),
            StatCard(
              title: 'Active Trips',
              value: '${_stats['active_trips']}',
              icon: Icons.directions_car,
              color: Colors.blue,
            ),
            StatCard(
              title: 'Active Drivers',
              value: '${_stats['active_drivers']}',
              icon: Icons.people,
              color: Colors.purple,
            ),
          ],
        );
      },
    );
  }

  Widget _buildRevenueChart() {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Revenue Trends',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text('Day ${value.toInt()}'),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      const FlSpot(0, 3000),
                      const FlSpot(1, 4500),
                      const FlSpot(2, 3200),
                      const FlSpot(3, 5800),
                      const FlSpot(4, 4200),
                      const FlSpot(5, 6000),
                      const FlSpot(6, 7500),
                    ],
                    isCurved: true,
                    color: AppTheme.primaryColor,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripActivityChart() {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trip Activity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: BarChart(
              BarChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = [
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                          'Sun',
                        ];
                        if (value >= 0 && value < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(days[value.toInt()]),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  _makeGroupData(0, 12, 5),
                  _makeGroupData(1, 15, 8),
                  _makeGroupData(2, 18, 6),
                  _makeGroupData(3, 14, 4),
                  _makeGroupData(4, 22, 10),
                  _makeGroupData(5, 28, 12),
                  _makeGroupData(6, 25, 9),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _makeGroupData(int x, double y1, double y2) {
    return BarChartGroupData(
      barsSpace: 4,
      x: x,
      barRods: [
        BarChartRodData(toY: y1, color: Colors.blue, width: 16),
        BarChartRodData(toY: y2, color: Colors.orange, width: 16),
      ],
    );
  }
}
