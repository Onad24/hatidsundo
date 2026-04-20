import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../services/services.dart';
import '../../state/auth_provider.dart';

/// Driver registration screen with document upload
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vehicleMakeController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleYearController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  DateTime? _licenseExpiryDate;

  String _vehicleType = 'sedan';
  bool _isLoading = false;

  XFile? _licensePhoto;
  XFile? _vehiclePhoto;
  XFile? _orCrPhoto;
  XFile? _selfiePhoto;

  Future<void> _pickPhoto(String type) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // Reduce size to prevent timeouts
      maxWidth: 1920, // Resize large photos
      maxHeight: 1920,
    );
    if (image != null) {
      setState(() {
        switch (type) {
          case 'license':
            _licensePhoto = image;
            break;
          case 'vehicle':
            _vehiclePhoto = image;
            break;
          case 'orcr':
            _orCrPhoto = image;
            break;
          case 'selfie':
            _selfiePhoto = image;
            break;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_licenseExpiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select license expiry date')),
      );
      return;
    }
    if (_licensePhoto == null ||
        _vehiclePhoto == null ||
        _orCrPhoto == null ||
        _selfiePhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload all required photos')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        throw Exception('User not logged in');
      }

      final riderService = ref.read(riderServiceProvider);

      // Upload documents
      final licenseUrl = await riderService.uploadDocument(
        _licensePhoto!,
        user.id,
      );
      final vehicleUrl = await riderService.uploadDocument(
        _vehiclePhoto!,
        user.id,
      );
      final orCrUrl = await riderService.uploadDocument(_orCrPhoto!, user.id);
      final selfieUrl = await riderService.uploadDocument(
        _selfiePhoto!,
        user.id,
      );

      // Register rider
      await riderService.registerRider(
        userId: user.id,
        vehicleMake: _vehicleMakeController.text,
        vehicleModel: _vehicleModelController.text,
        vehicleYear: _vehicleYearController.text,
        vehicleColor: _vehicleColorController.text,
        plateNumber: _plateNumberController.text,
        vehicleType: _vehicleType,
        licenseNumber: _licenseNumberController.text,
        licenseExpiry: _licenseExpiryDate!,
        licensePhotoUrl: licenseUrl,
        vehiclePhotoUrl: vehicleUrl,
        orCrPhotoUrl: orCrUrl,
        selfieUrl: selfieUrl,
      );

      // Refresh auth state to update role
      await ref.read(authStateProvider.notifier).refreshProfile();

      if (mounted) {
        context.go(Routes.riderPendingApproval);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _vehicleMakeController.dispose();
    _vehicleModelController.dispose();
    _vehicleYearController.dispose();
    _vehicleColorController.dispose();
    _plateNumberController.dispose();
    _licenseNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Registration')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header
            const Text(
              'Complete your driver profile',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.neutral900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please provide your vehicle and license information',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                color: AppTheme.neutral500,
              ),
            ),
            const SizedBox(height: 32),

            // Vehicle Type
            const Text(
              'Vehicle Type',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.neutral600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildVehicleTypeOption(
                  'motorcycle',
                  Icons.two_wheeler_rounded,
                ),
                const SizedBox(width: 12),
                _buildVehicleTypeOption('sedan', Icons.directions_car_rounded),
                const SizedBox(width: 12),
                _buildVehicleTypeOption(
                  'suv',
                  Icons.directions_car_filled_rounded,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Vehicle Details
            _buildTextField(
              controller: _vehicleMakeController,
              label: 'Vehicle Make',
              hint: 'e.g. Toyota',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _vehicleModelController,
              label: 'Vehicle Model',
              hint: 'e.g. Vios',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _vehicleYearController,
                    label: 'Year',
                    hint: '2020',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    controller: _vehicleColorController,
                    label: 'Color',
                    hint: 'White',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _plateNumberController,
              label: 'Plate Number',
              hint: 'ABC 123',
            ),
            const SizedBox(height: 24),

            // License
            _buildTextField(
              controller: _licenseNumberController,
              label: 'License Number',
              hint: 'N01-23-456789',
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: now.add(const Duration(days: 365)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365 * 10)),
                );
                if (picked != null) {
                  setState(() => _licenseExpiryDate = picked);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).inputDecorationTheme.fillColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.transparent),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      color: AppTheme.neutral500,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _licenseExpiryDate == null
                          ? 'License Expiry Date'
                          : DateFormat(
                              'MMMM d, yyyy',
                            ).format(_licenseExpiryDate!),
                      style: _licenseExpiryDate == null
                          ? Theme.of(context).inputDecorationTheme.hintStyle
                          : Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Document Upload
            const Text(
              'Required Photos',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.neutral600,
              ),
            ),
            const SizedBox(height: 16),
            _buildPhotoUploadItem(
              'Driver\'s License Photo',
              'license',
              _licensePhoto,
            ),
            const SizedBox(height: 12),
            _buildPhotoUploadItem('Vehicle Photo', 'vehicle', _vehiclePhoto),
            const SizedBox(height: 12),
            _buildPhotoUploadItem(
              'Official Receipt / Reg (OR/CR)',
              'orcr',
              _orCrPhoto,
            ),
            const SizedBox(height: 12),
            _buildPhotoUploadItem('Clear Selfie', 'selfie', _selfiePhoto),

            const SizedBox(height: 32),

            // Submit button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit for Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTypeOption(String type, IconData icon) {
    final isSelected = _vehicleType == type;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _vehicleType = type),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                  : AppTheme.neutral100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.neutral400,
                ),
                const SizedBox(height: 8),
                Text(
                  type.capitalize(),
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.neutral600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Theme.of(context).inputDecorationTheme.fillColor,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '$label is required';
        }
        return null;
      },
    );
  }

  Widget _buildPhotoUploadItem(String label, String type, XFile? file) {
    return InkWell(
      onTap: () => _pickPhoto(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: file == null ? AppTheme.neutral300 : AppTheme.successColor,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: file == null
                    ? AppTheme.neutral100
                    : AppTheme.successColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                file == null ? Icons.add_a_photo_rounded : Icons.check_rounded,
                color: file == null
                    ? AppTheme.neutral400
                    : AppTheme.successColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (file != null)
                    Text(
                      'Photo selected',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 12,
                        color: AppTheme.successColor,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
