import 'package:shared_preferences/shared_preferences.dart';

/// Sessão do técnico — persiste token para uso offline e sync.
class AppSession {
  static const _kToken = 'unitec_os_token';
  static const _kUsuario = 'unitec_os_usuario';
  static const _kUserId = 'unitec_os_user_id';
  static const _kVendedorId = 'unitec_os_vendedor_id';
  static const _kEmpresaId = 'unitec_os_empresa_id';
  static const _kEmpresaNome = 'unitec_os_empresa_nome';
  static const _kManter = 'unitec_os_manter_conectado';

  static String usuario = 'USUÁRIO';
  static bool manterConectado = false;
  static String? token;
  static int? userId;
  static int? vendedorId;
  static int? empresaId;
  static String? empresaNome;

  static bool get isLoggedIn => token != null && token!.isNotEmpty;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_kToken);
    usuario = prefs.getString(_kUsuario) ?? 'USUÁRIO';
    userId = prefs.getInt(_kUserId);
    vendedorId = prefs.getInt(_kVendedorId);
    empresaId = prefs.getInt(_kEmpresaId);
    empresaNome = prefs.getString(_kEmpresaNome);
    manterConectado = prefs.getBool(_kManter) ?? false;
  }

  static Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token!.isEmpty) {
      await clearPersisted();
      return;
    }
    await prefs.setString(_kToken, token!);
    await prefs.setString(_kUsuario, usuario);
    await prefs.setBool(_kManter, manterConectado);
    if (userId != null) {
      await prefs.setInt(_kUserId, userId!);
    } else {
      await prefs.remove(_kUserId);
    }
    if (vendedorId != null) {
      await prefs.setInt(_kVendedorId, vendedorId!);
    } else {
      await prefs.remove(_kVendedorId);
    }
    if (empresaId != null) {
      await prefs.setInt(_kEmpresaId, empresaId!);
    } else {
      await prefs.remove(_kEmpresaId);
    }
    if (empresaNome != null) {
      await prefs.setString(_kEmpresaNome, empresaNome!);
    } else {
      await prefs.remove(_kEmpresaNome);
    }
  }

  static Future<void> clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUsuario);
    await prefs.remove(_kUserId);
    await prefs.remove(_kVendedorId);
    await prefs.remove(_kEmpresaId);
    await prefs.remove(_kEmpresaNome);
    await prefs.remove(_kManter);
  }

  static Future<void> clear() async {
    usuario = 'USUÁRIO';
    manterConectado = false;
    token = null;
    userId = null;
    vendedorId = null;
    empresaId = null;
    empresaNome = null;
    await clearPersisted();
  }
}
