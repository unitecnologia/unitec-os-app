import 'package:package_info_plus/package_info_plus.dart';

/// Versão do app (vem do `pubspec.yaml` / build do Codemagic).
class AppVersion {
  AppVersion._();

  static String name = '1.0.0';
  static String build = '2';

  /// Ex.: `1.0.0 (1)`
  static String get label => '$name ($build)';

  /// Ex.: `1.0.0+1` — envio ao ERP / registro de aparelho.
  static String get full => '$name+$build';

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      name = info.version.isNotEmpty ? info.version : name;
      build = info.buildNumber.isNotEmpty ? info.buildNumber : build;
    } catch (_) {
      // Mantém defaults se a plataforma não informar.
    }
  }
}
