import 'package:url_launcher/url_launcher.dart';

Future<void> dialPhone(String? raw) async {
  if (raw == null || raw.trim().isEmpty) return;
  final uri = Uri(scheme: 'tel', path: raw.replaceAll(RegExp(r'\s'), ''));
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

Future<void> openWhatsAppContact(String? raw) async {
  if (raw == null || raw.trim().isEmpty) return;
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return;
  final uri = Uri.parse('https://wa.me/$d');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
