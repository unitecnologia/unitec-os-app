import 'package:unitec_os_app/config/api_config.dart';
import 'package:unitec_os_app/services/api_client.dart';
import 'package:unitec_os_app/session/app_session.dart';

class EmpresaOption {
  const EmpresaOption({required this.id, required this.nome});

  final int id;
  final String nome;
}

class UserOption {
  const UserOption({
    required this.id,
    required this.name,
    this.empresaId,
    this.vendedorId,
  });

  final int id;
  final String name;
  final int? empresaId;
  final int? vendedorId;
}

class DeviceStatus {
  const DeviceStatus({
    required this.status,
    required this.approved,
    this.pairingCode,
  });

  final String status;
  final bool approved;
  final String? pairingCode;
}

class AuthService {
  AuthService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<bool> ping() async {
    try {
      final json = await _client.getJson('/ping', auth: false, device: false);
      return json['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Tenta URLs de desenvolvimento até o ping responder.
  Future<String?> discoverDevServer({String? preferred}) async {
    final tried = <String>{};
    final candidates = <String>[
      if (preferred != null && preferred.trim().isNotEmpty) preferred.trim(),
      ...ApiConfig.devCandidates,
    ];

    for (final raw in candidates) {
      var url = raw.trim().replaceAll(RegExp(r'/+$'), '');
      if (url.isEmpty) continue;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }
      if (!tried.add(url)) continue;

      ApiConfig.setErpBaseUrl(url);
      if (await ping()) return url;
    }
    return null;
  }

  Future<DeviceStatus> registerDevice() async {
    final json = await _client.postJson(
      '/devices/register',
      body: {
        'device_uuid': DeviceIdentity.uuid,
        'device_name': DeviceIdentity.deviceName,
        'platform': DeviceIdentity.platform,
        'app_version': '1.0.0',
      },
      auth: false,
      device: false,
    );
    return DeviceStatus(
      status: '${json['status'] ?? 'desconhecido'}',
      approved: json['approved'] == true,
      pairingCode: json['pairing_code']?.toString(),
    );
  }

  Future<DeviceStatus> deviceStatus() async {
    final json = await _client.getJson(
      '/devices/status?device_uuid=${Uri.encodeComponent(DeviceIdentity.uuid)}',
      auth: false,
      device: false,
    );
    return DeviceStatus(
      status: '${json['status'] ?? 'desconhecido'}',
      approved: json['approved'] == true,
      pairingCode: json['pairing_code']?.toString(),
    );
  }

  Future<List<EmpresaOption>> listarEmpresas() async {
    final json = await _client.getJson('/info', auth: false);
    final list = json['empresas'];
    if (list is! List) return [];
    return list.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return EmpresaOption(
        id: m['id'] is int ? m['id'] as int : int.parse('${m['id']}'),
        nome: '${m['nome'] ?? ''}',
      );
    }).toList();
  }

  Future<List<UserOption>> listarUsuarios({required int empresaId}) async {
    final json = await _client.getJson('/users?empresa_id=$empresaId', auth: false);
    final list = json['users'];
    if (list is! List) return [];
    return list.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return UserOption(
        id: m['id'] is int ? m['id'] as int : int.parse('${m['id']}'),
        name: '${m['name'] ?? ''}',
        empresaId: m['empresa_id'] is int
            ? m['empresa_id'] as int
            : int.tryParse('${m['empresa_id'] ?? ''}'),
        vendedorId: m['vendedor_id'] is int
            ? m['vendedor_id'] as int
            : int.tryParse('${m['vendedor_id'] ?? ''}'),
      );
    }).toList();
  }

  Future<void> login({
    required String usuario,
    required String senha,
    required int empresaId,
    int? userId,
  }) async {
    final json = await _client.postJson(
      '/auth/login',
      body: {
        'usuario': usuario.trim(),
        'user_id': ?userId,
        'senha': senha,
        'empresa_id': empresaId,
        'device_uuid': DeviceIdentity.uuid,
        'device_name': DeviceIdentity.deviceName,
        'platform': DeviceIdentity.platform,
        'app_version': '1.0.0',
      },
      auth: false,
    );

    final token = json['token']?.toString();
    if (token == null || token.isEmpty) {
      throw ApiException('Resposta de login inválida.');
    }

    final user = json['user'];
    final userMap = user is Map<String, dynamic> ? user : <String, dynamic>{};
    final emp = userMap['empresa_id'] is int
        ? userMap['empresa_id'] as int
        : int.tryParse('${userMap['empresa_id'] ?? ''}');

    if (emp == null || emp <= 0) {
      throw ApiException('Usuário sem empresa. Login bloqueado.');
    }

    AppSession.token = token;
    AppSession.empresaId = emp;
    AppSession.usuario = (userMap['tecnico'] ?? userMap['name'] ?? usuario)
        .toString()
        .toUpperCase();
    AppSession.userId = userMap['id'] is int
        ? userMap['id'] as int
        : int.tryParse('${userMap['id'] ?? ''}');
    AppSession.vendedorId = userMap['vendedor_id'] is int
        ? userMap['vendedor_id'] as int
        : int.tryParse('${userMap['vendedor_id'] ?? ''}');
    await AppSession.persist();
  }

  Future<void> logout() async {
    try {
      if (AppSession.token != null) {
        await _client.postJson('/auth/logout', auth: true);
      }
    } catch (_) {
      // Encerra local mesmo se a API falhar.
    } finally {
      await AppSession.clear();
    }
  }
}
