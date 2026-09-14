import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:unitec_os_app/config/erp_url.dart';

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
    final u = ErpUrl.normalize(url);
    if (u.isEmpty) return;
    erpBaseUrl = u;
  }

  static bool get urlEhTunel => ErpUrl.ehNuvemUrl(erpBaseUrl);

  static Future<void> loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsUrlKey);
    if (saved == null || saved.trim().isEmpty) return;
    setErpBaseUrl(saved);
    if (erpBaseUrl != saved.trim().replaceAll(RegExp(r'/+$'), '')) {
      await saveUrl();
    }
  }

  static Future<void> saveUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsUrlKey, erpBaseUrl);
  }
}
