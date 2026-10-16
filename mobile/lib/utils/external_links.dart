import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the platform's browser and reports whether it launched.
///
/// Any failure (malformed URL, no handler, platform error) returns false rather
/// than throwing, so callers can surface a message without a try/catch.
Future<bool> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
