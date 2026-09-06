import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

export 'device_identity.dart';

/// URL base do ERP (sem barra no final). Configurável em runtime.
class ApiConfig {
  static const _prefsUrlKey = 'unitec_os_erp_base_url';

  /// Candidatos típicos em desenvolvimento local.
  static List<String> get devCandidates {
    final list = <String>[
      'http://127.0.0.1:8000',
      'http://localhost:8000',
      'http://10.0.2.2:8000', // emulador Android → host
    ];
    final current = erpBaseUrl.trim();
    if (current.isNotEmpty && !list.contains(current)) {
      return [current, ...list];
    }
    if (Platform.isAndroid) {
      return [
        'http://10.0.2.2:8000',
        'http://127.0.0.1:8000',
        'http://localhost:8000',
      ];
    }
    return list;
  }

  static String erpBaseUrl = _defaultForPlatform();

  static String _defaultForPlatform() {
    const fromEnv = String.fromEnvironment('ERP_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  static String get apiBase => '${erpBaseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/unitec-os';

  static void setErpBaseUrl(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isNotEmpty && !u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    erpBaseUrl = u;
  }

  static Future<void> loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsUrlKey);
    if (saved != null && saved.trim().isNotEmpty) {
      setErpBaseUrl(saved);
    }
  }

  static Future<void> saveUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsUrlKey, erpBaseUrl);
  }
}
