import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../state/state.dart';
import '../../services/fare_settings_service.dart';
import '../widgets/admin_sidebar.dart';

/// Admin screen for editing fare calculation parameters.
class FareSettingsScreen extends ConsumerStatefulWidget {
  const FareSettingsScreen({super.key});

  @override
  ConsumerState<FareSettingsScreen> createState() => _FareSettingsScreenState();
}

class _FareSettingsScreenState extends ConsumerState<FareSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _baseFareCtrl;
  late TextEditingController _perKmRateCtrl;
  late TextEditingController _nightMultiplierCtrl;
  late TextEditingController _nightStartCtrl;
  late TextEditingController _nightEndCtrl;
  late TextEditingController _platformFeeCtrl;

  // Preview inputs
  final _previewDestKmCtrl = TextEditingController(text: '5');
  final _previewDriverKmCtrl = TextEditingController(text: '2');

  bool _isSaving = false;
  bool _isInitialized = false;

  @override
  void dispose() {
    _baseFareCtrl.dispose();
    _perKmRateCtrl.dispose();
    _nightMultiplierCtrl.dispose();
    _nightStartCtrl.dispose();
    _nightEndCtrl.dispose();
    _platformFeeCtrl.dispose();
    _previewDestKmCtrl.dispose();
    _previewDriverKmCtrl.dispose();
    super.dispose();
  }

  void _initControllers(FareSettings settings) {
    if (_isInitialized) return;
    _baseFareCtrl = TextEditingController(
      text: settings.baseFare.toStringAsFixed(0),
    );
    _perKmRateCtrl = TextEditingController(
      text: settings.perKmRate.toStringAsFixed(0),
    );
    _nightMultiplierCtrl = TextEditingController(
      text: settings.nightRateMultiplier.toStringAsFixed(2),
    );
    _nightStartCtrl = TextEditingController(
      text: settings.nightStartHour.toString(),
    );
    _nightEndCtrl = TextEditingController(
      text: settings.nightEndHour.toString(),
    );
    _platformFeeCtrl = TextEditingController(
      text: (settings.platformFeePercent * 100).toStringAsFixed(0),
    );
    _isInitialized = true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final userId = ref.read(currentUserProvider)?.id;
      await Supabase.instance.client
          .from('fare_settings')
          .update({
            'base_fare': double.parse(_baseFareCtrl.text),
            'per_km_rate': double.parse(_perKmRateCtrl.text),
            'night_rate_multiplier': double.parse(_nightMultiplierCtrl.text),
            'night_start_hour': int.parse(_nightStartCtrl.text),
            'night_end_hour': int.parse(_nightEndCtrl.text),
            'platform_fee_percent': double.parse(_platformFeeCtrl.text) / 100,
            'updated_by': userId,
          })
          .eq('id', 1);

      // Invalidate cached settings so all consumers pick up the new values
      ref.invalidate(fareSettingsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fare settings saved successfully!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Build a live fare preview based on current form values.
  Widget _buildPreview() {
    final baseFare = double.tryParse(_baseFareCtrl.text) ?? 25;
    final perKmRate = double.tryParse(_perKmRateCtrl.text) ?? 8;
    final nightMult = double.tryParse(_nightMultiplierCtrl.text) ?? 1.2;
    final platformPct = (double.tryParse(_platformFeeCtrl.text) ?? 10) / 100;
    final destKm = double.tryParse(_previewDestKmCtrl.text) ?? 5;
    final driverKm = double.tryParse(_previewDriverKmCtrl.text) ?? 2;

    final dayFare =
        baseFare +
        (driverKm.floorToDouble() * perKmRate) +
        (destKm.floorToDouble() * perKmRate);
    final nightFare =
        baseFare +
        (driverKm.floorToDouble() * perKmRate) +
        (destKm.floorToDouble() * perKmRate * nightMult);
    final dayPlatformFee = dayFare * platformPct;
    final nightPlatformFee = nightFare * platformPct;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fare Preview',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPreviewInput(
                  label: 'Pickup → Dest (km)',
                  controller: _previewDestKmCtrl,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPreviewInput(
                  label: 'Driver → Pickup (km)',
                  controller: _previewDriverKmCtrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildPreviewCard(
                  icon: Icons.wb_sunny_rounded,
                  iconColor: AppTheme.warningColor,
                  title: 'Day Fare',
                  fare: dayFare,
                  platformFee: dayPlatformFee,
                  driverEarnings: dayFare - dayPlatformFee,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPreviewCard(
                  icon: Icons.nightlight_round,
                  iconColor: Colors.indigo,
                  title: 'Night Fare',
                  fare: nightFare,
                  platformFee: nightPlatformFee,
                  driverEarnings: nightFare - nightPlatformFee,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewInput({
    required String label,
    required TextEditingController controller,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: const InputDecorationTheme(),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        onChanged: (_) => setState(() {}),
        style: const TextStyle(
          fontSize: 14,
          color: AppTheme.neutral900,
          fontFamily: 'Outfit',
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontSize: 12,
            color: AppTheme.neutral600,
            fontFamily: 'Outfit',
          ),
          floatingLabelStyle: const TextStyle(
            fontSize: 14,
            color: AppTheme.primaryColor,
            fontFamily: 'Outfit',
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.neutral300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.neutral300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required double fare,
    required double platformFee,
    required double driverEarnings,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _previewRow('Total Fare', '₱${fare.toStringAsFixed(0)}', bold: true),
          _previewRow('Platform Fee', '₱${platformFee.toStringAsFixed(0)}'),
          _previewRow(
            'Driver Earnings',
            '₱${driverEarnings.toStringAsFixed(0)}',
            color: AppTheme.successColor,
          ),
        ],
      ),
    );
  }

  Widget _previewRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.neutral500),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final fareSettingsAsync = ref.watch(fareSettingsProvider);

    return Scaffold(
      backgroundColor: AppTheme.neutral50,
      body: Row(
        children: [
          const AdminSidebar(activeItem: 'Fare Settings'),
          Expanded(
            child: Container(
              color: AppTheme.neutral50,
              child: Column(
                children: [
                  // Top bar
                  _buildTopBar(user),
                  // Content
                  Expanded(
                    child: fareSettingsAsync.when(
                      data: (settings) {
                        _initControllers(settings);
                        return _buildContent();
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) =>
                          Center(child: Text('Error loading settings: $e')),
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

  Widget _buildTopBar(dynamic user) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Spacer(),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
            child: Text(
              user?.name.substring(0, 1).toUpperCase() ?? 'A',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            user?.name ?? 'Admin',
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Fare Settings',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Configure the fare formula: Base Fare + floor(driver→pickup km) × Per-Km Rate + floor(pickup→dest km) × Per-Km Rate × Night Multiplier',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 13,
                color: AppTheme.neutral500,
              ),
            ),
            const SizedBox(height: 24),

            // Settings form
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column — fare parameters
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fare Parameters',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildFormField(
                          label: 'Base Fare (₱)',
                          controller: _baseFareCtrl,
                          hint: 'e.g. 25',
                          icon: Icons.attach_money_rounded,
                        ),
                        const SizedBox(height: 16),
                        _buildFormField(
                          label: 'Per-Km Rate (₱)',
                          controller: _perKmRateCtrl,
                          hint: 'e.g. 8',
                          icon: Icons.straighten_rounded,
                        ),
                        const SizedBox(height: 16),
                        _buildFormField(
                          label: 'Platform Fee (%)',
                          controller: _platformFeeCtrl,
                          hint: 'e.g. 10',
                          icon: Icons.percent_rounded,
                          suffix: '%',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),

                // Right column — night rate settings
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Night Rate Settings',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildFormField(
                          label: 'Night Rate Multiplier',
                          controller: _nightMultiplierCtrl,
                          hint: 'e.g. 1.2',
                          icon: Icons.nightlight_round,
                        ),
                        const SizedBox(height: 16),
                        _buildFormField(
                          label: 'Night Start Hour (0-23)',
                          controller: _nightStartCtrl,
                          hint: 'e.g. 21 (9 PM)',
                          icon: Icons.schedule_rounded,
                          isInteger: true,
                        ),
                        const SizedBox(height: 16),
                        _buildFormField(
                          label: 'Night End Hour (0-23)',
                          controller: _nightEndCtrl,
                          hint: 'e.g. 5 (5 AM)',
                          icon: Icons.schedule_rounded,
                          isInteger: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Live preview
            _buildPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? suffix,
    bool isInteger = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: const InputDecorationTheme(),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          if (isInteger)
            FilteringTextInputFormatter.digitsOnly
          else
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
        ],
        onChanged: (_) => setState(() {}), // refresh preview
        style: const TextStyle(
          fontSize: 14,
          color: AppTheme.neutral900,
          fontFamily: 'Outfit',
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Required';
          final num = double.tryParse(value);
          if (num == null || num < 0) return 'Enter a valid number';
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(
            fontSize: 14,
            color: AppTheme.neutral600,
            fontFamily: 'Outfit',
          ),
          floatingLabelStyle: const TextStyle(
            fontSize: 14,
            color: AppTheme.primaryColor,
            fontFamily: 'Outfit',
          ),
          hintStyle: const TextStyle(
            fontSize: 13,
            color: AppTheme.neutral400,
            fontFamily: 'Outfit',
          ),
          prefixIcon: Icon(icon, size: 20, color: AppTheme.neutral500),
          suffixText: suffix,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.neutral300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.neutral300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
