import 'package:flutter/foundation.dart';

const String _apiFromEnv =
    String.fromEnvironment('API_BASE_URL', defaultValue: '');
const String _wsFromEnv =
    String.fromEnvironment('WS_BASE_URL', defaultValue: '');

String get apiBaseUrl {
  if (_apiFromEnv.isNotEmpty) return _apiFromEnv;

  if (kIsWeb) return 'http://127.0.0.1:4000';

  if (defaultTargetPlatform == TargetPlatform.android) {
    // Android emulator reaches host machine via 10.0.2.2.
    return 'http://10.0.2.2:4000';
  }

  // iOS simulator and macOS app can use localhost directly.
  return 'http://127.0.0.1:4000';
}

String get wsBaseUrl {
  if (_wsFromEnv.isNotEmpty) return _wsFromEnv;

  if (apiBaseUrl.startsWith('https://')) {
    return 'wss://${apiBaseUrl.substring(8)}';
  }
  if (apiBaseUrl.startsWith('http://')) {
    return 'ws://${apiBaseUrl.substring(7)}';
  }
  return apiBaseUrl;
}
