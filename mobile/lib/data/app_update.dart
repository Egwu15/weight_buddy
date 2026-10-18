import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../utils/app_version.dart';

class AppUpdate {
  const AppUpdate({
    required this.minimumVersion,
    required this.storeUrl,
    required this.message,
  });

  final String minimumVersion;
  final String storeUrl;
  final String message;

  static AppUpdate? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final minimum = value['minimum_version'];
    final storeUrl = value['store_url'];
    final message = value['message'];
    if (minimum is! String ||
        storeUrl is! String ||
        message is! String ||
        parseAppVersion(minimum) == null) {
      return null;
    }
    final uri = Uri.tryParse(storeUrl);
    if (uri == null || !uri.hasAuthority || !uri.isScheme('https')) {
      return null;
    }
    if (message.trim().isEmpty) return null;
    return AppUpdate(
      minimumVersion: minimum.trim(),
      storeUrl: storeUrl.trim(),
      message: message.trim(),
    );
  }
}

class AppUpdateService {
  AppUpdateService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? kBackendBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 6);

  Future<AppUpdate?> fetch() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/v1/app/version'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      return AppUpdate.fromJson(jsonDecode(response.body));
    } catch (_) {
      return null;
    }
  }
}
