import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';

import '../widgets/admin_sidebar.dart';

/// Provider for pending rider approvals
final pendingRidersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('rider_profiles')
      .select('*, users!user_id!inner(*)')
      .eq('status', 'pending')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(response);
});

/// Admin rider approval screen
class RiderApprovalScreen extends ConsumerWidget {
  const RiderApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingRiders = ref.watch(pendingRidersProvider);

    return Scaffold(
      body: Row(
        children: [
          const AdminSidebar(activeItem: 'Rider Approvals'),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Rider Approvals'),
                automaticallyImplyLeading:
                    false, // Hide back button as we have sidebar
              ),
              body: pendingRiders.when(
                data: (riders) => riders.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(24),
                        itemCount: riders.length,
                        itemBuilder: (context, index) {
                          return _RiderApprovalCard(
                            rider: riders[index],
                            onApprove: () =>
                                _approveRider(ref, riders[index]['id']),
                            onReject: () => _showRejectDialog(
                              context,
                              ref,
                              riders[index]['id'],
                            ),
                          );
                        },
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 64,
            color: AppTheme.successColor,
          ),
          SizedBox(height: 16),
          Text(
            'All caught up!',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'No pending rider approvals',
            style: TextStyle(color: AppTheme.neutral500),
          ),
        ],
      ),
    );
  }

  Future<void> _approveRider(WidgetRef ref, String profileId) async {
    final supabase = Supabase.instance.client;
    await supabase
        .from('rider_profiles')
        .update({
          'status': 'approved',
          'approved_at': DateTime.now().toIso8601String(),
          'approved_by': supabase.auth.currentUser?.id,
        })
        .eq('id', profileId);
    ref.invalidate(pendingRidersProvider);
  }

  void _showRejectDialog(
    BuildContext context,
    WidgetRef ref,
    String profileId,
  ) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Application'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Rejection reason',
            hintText: 'Enter reason for rejection',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final supabase = Supabase.instance.client;
              await supabase
                  .from('rider_profiles')
                  .update({
                    'status': 'rejected',
                    'rejection_reason': reasonController.text,
                  })
                  .eq('id', profileId);
              ref.invalidate(pendingRidersProvider);
              if (context.mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}

class _RiderApprovalCard extends StatelessWidget {
  final Map<String, dynamic> rider;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RiderApprovalCard({
    required this.rider,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final user = rider['users'] as Map<String, dynamic>;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                backgroundImage: user['avatar_url'] != null
                    ? NetworkImage(user['avatar_url'])
                    : null,
                child: user['avatar_url'] == null
                    ? Text(
                        (user['name'] as String).substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['name'] ?? 'Unknown',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      user['email'] ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.neutral500,
                      ),
                    ),
                    if (user['phone'] != null)
                      Text(
                        user['phone'],
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.neutral500,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warningColor,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 32),

          // Vehicle info
          const Text(
            'Vehicle Information',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.neutral600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildInfoItem(
                'Type',
                rider['vehicle_type']?.toString().toUpperCase() ?? 'N/A',
              ),
              _buildInfoItem('Make', rider['vehicle_make'] ?? 'N/A'),
              _buildInfoItem('Model', rider['vehicle_model'] ?? 'N/A'),
              _buildInfoItem(
                'Year',
                rider['vehicle_year']?.toString() ?? 'N/A',
              ),
              _buildInfoItem('Color', rider['vehicle_color'] ?? 'N/A'),
              _buildInfoItem('Plate', rider['plate_number'] ?? 'N/A'),
            ],
          ),
          const SizedBox(height: 16),

          // License info
          const Text(
            'License Information',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.neutral600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildInfoItem('License #', rider['license_number'] ?? 'N/A'),
              _buildInfoItem('Expiry', rider['license_expiry'] ?? 'N/A'),
            ],
          ),
          const SizedBox(height: 16),

          // Documents
          const Text(
            'Uploaded Documents',
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
              _buildDocumentTile('License', rider['license_photo_url'] != null),
              const SizedBox(width: 12),
              _buildDocumentTile('OR/CR', rider['or_cr_photo_url'] != null),
              const SizedBox(width: 12),
              _buildDocumentTile('Vehicle', rider['vehicle_photo_url'] != null),
              const SizedBox(width: 12),
              _buildDocumentTile('Selfie', rider['selfie_url'] != null),
            ],
          ),
          const SizedBox(height: 24),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                  side: const BorderSide(color: AppTheme.errorColor),
                ),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: onApprove,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successColor,
                ),
                child: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.neutral500),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile(String label, bool hasDocument) {
    return Container(
      width: 80,
      height: 60,
      decoration: BoxDecoration(
        color: hasDocument
            ? AppTheme.successColor.withValues(alpha: 0.1)
            : AppTheme.neutral100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDocument ? AppTheme.successColor : AppTheme.neutral300,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasDocument
                ? Icons.check_circle_rounded
                : Icons.image_not_supported_rounded,
            color: hasDocument ? AppTheme.successColor : AppTheme.neutral400,
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: hasDocument ? AppTheme.successColor : AppTheme.neutral500,
            ),
          ),
        ],
      ),
    );
  }
}
