import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// ID estável do aparelho — validar 1x no ERP e pronto.
///
/// Prioridade:
/// 1) ANDROID_ID (sobrevive reinstall / flutter run)
/// 2) Arquivo sticky em /sdcard/UnitecOS (emulador)
/// 3) SharedPreferences + arquivo interno
class DeviceIdentity {
  static const _prefsUuidKey = 'unitec_os_device_uuid_v2';
  static const _prefsApprovedKey = 'unitec_os_device_approved';
  static const _fileName = 'unitec_os_device_id.txt';

  static String? _uuid;
  static bool _ready = false;
  static bool approvedCached = false;
  static Future<void>? _loading;

  static Future<void> ensureReady() async {
    if (_ready && _uuid != null && _uuid!.isNotEmpty) return;
    _loading ??= _load();
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  static Future<void> _load() async {
    String? saved = await _androidStableId();
    saved ??= await _readStickyExternal();

    final prefs = await SharedPreferences.getInstance();
    saved ??= prefs.getString(_prefsUuidKey)?.trim();
    saved ??= await _readInternalFile();

    if (saved == null || saved.isEmpty) {
      saved = 'gen-${const Uuid().v4()}';
    }

    await prefs.setString(_prefsUuidKey, saved);
    await _writeInternalFile(saved);
    await _writeStickyExternal(saved);

    _uuid = saved;
    approvedCached = prefs.getBool(_prefsApprovedKey) ?? false;
    _ready = true;
  }

  static Future<String?> _androidStableId() async {
    if (!Platform.isAndroid) return null;

    try {
      final id = await const AndroidId().getId();
      final clean = (id ?? '').trim();
      if (clean.isNotEmpty) return 'android-$clean';
    } catch (_) {}

    try {
      final info = DeviceInfoPlugin();
      final a = await info.androidInfo;
      final id = a.id.trim();
      if (id.isNotEmpty) return 'android-$id';
      final fp = a.fingerprint.trim();
      if (fp.isNotEmpty) {
        return 'android-fp-${fp.hashCode.abs()}';
      }
    } catch (_) {}

    return null;
  }

  /// Fora do sandbox do app — sobrevive a uninstall no emulador.
  static Future<String?> _readStickyExternal() async {
    if (!Platform.isAndroid) return null;
    for (final path in const [
      '/sdcard/UnitecOS/device_id.txt',
      '/storage/emulated/0/UnitecOS/device_id.txt',
    ]) {
      try {
        final f = File(path);
        if (await f.exists()) {
          final t = (await f.readAsString()).trim();
          if (t.isNotEmpty) return t;
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<void> _writeStickyExternal(String value) async {
    if (!Platform.isAndroid) return;
    for (final path in const [
      '/sdcard/UnitecOS/device_id.txt',
      '/storage/emulated/0/UnitecOS/device_id.txt',
    ]) {
      try {
        final f = File(path);
        await f.parent.create(recursive: true);
        await f.writeAsString(value, flush: true);
        return;
      } catch (_) {}
    }
  }

  static String get uuid {
    if (_uuid == null || _uuid!.isEmpty) {
      throw StateError('DeviceIdentity.ensureReady() deve ser chamado antes do uso.');
    }
    return _uuid!;
  }

  static String get shortId {
    final u = uuid.replaceAll('-', '');
    if (u.length <= 8) return u.toUpperCase();
    return u.substring(u.length - 8).toUpperCase();
  }

  static String get deviceName {
    if (Platform.isAndroid) return 'Android Unitec OS';
    if (Platform.isIOS) return 'iOS Unitec OS';
    return 'Windows Unitec OS';
  }

  static String get platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  static Future<void> setApproved(bool value) async {
    approvedCached = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsApprovedKey, value);
  }

  static Future<String?> _readInternalFile() async {
    try {
      final file = await _idFile();
      if (!await file.exists()) return null;
      final text = (await file.readAsString()).trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeInternalFile(String value) async {
    try {
      final file = await _idFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(value, flush: true);
    } catch (_) {}
  }

  static Future<File> _idFile() async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return File(p.join(appData, 'UnitecOS', _fileName));
      }
    }
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }
}
