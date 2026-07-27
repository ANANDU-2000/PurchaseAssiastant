import 'package:flutter/material.dart';

/// Inline notice with [Retry] when the app cannot reach the server — not a SnackBar.
class AuthNetworkErrorBanner extends StatelessWidget {
  const AuthNetworkErrorBanner({
    super.key,
    required this.onRetry,
    this.title = "Can't reach server",
    this.detail,
  });

  final VoidCallback onRetry;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.orange.shade900, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900,
                    height: 1.25,
                  ),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
          if (detail != null && detail!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                detail!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade900,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
