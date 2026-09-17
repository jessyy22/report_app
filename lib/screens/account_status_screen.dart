import 'package:flutter/material.dart';

class AccountStatusScreen extends StatelessWidget {
  final String status;
  final String? rejectionReason;
  final VoidCallback? onRefresh;

  const AccountStatusScreen({
    super.key,
    required this.status,
    this.rejectionReason,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();

    late final IconData icon;
    late final Color color;
    late final String title;
    late final String message;

    switch (normalized) {
      case 'approved':
      case 'active':
        icon = Icons.verified_rounded;
        color = Colors.green;
        title = 'Account Approved';
        message = 'Your RTODA account is ready to use.';
        break;
      case 'rejected':
        icon = Icons.cancel_rounded;
        color = Colors.red;
        title = 'Application Rejected';
        message = rejectionReason?.trim().isNotEmpty == true
            ? rejectionReason!.trim()
            : 'Your driver application was not approved. Please contact RTODA/LGU for more information.';
        break;
      case 'suspended':
        icon = Icons.block_rounded;
        color = Colors.orange;
        title = 'Account Suspended';
        message = 'Your account is currently suspended. Please contact RTODA/LGU for assistance.';
        break;
      default:
        icon = Icons.hourglass_top_rounded;
        color = Colors.amber.shade800;
        title = 'Waiting for Verification';
        message = 'Your driver application is being reviewed by an authorized RTODA/LGU administrator.';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 52, color: color),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 24),
                if (normalized == 'pending' || normalized == 'approved' || normalized == 'active')
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('CHECK STATUS AGAIN'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false),
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
