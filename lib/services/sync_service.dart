import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:unitec_os_app/config/erp_url.dart';
import 'package:unitec_os_app/services/auth_service.dart';
import 'package:unitec_os_app/config/device_identity.dart';
import 'package:unitec_os_app/data/local/app_database.dart';
import 'package:unitec_os_app/models/ordem_servico.dart';
import 'package:unitec_os_app/services/api_client.dart';
import 'package:unitec_os_app/services/os_create_vinculo.dart';
import 'package:unitec_os_app/session/app_session.dart';

/// Resultado de uma sincronização.
class SyncResult {
  const SyncResult({
    required this.ok,
    this.pulled = 0,
    this.pushed = 0,
    this.pending = 0,
    this.message,
  });

  final bool ok;
  final int pulled;
  final int pushed;
  final int pending;
  final String? message;
}


/// Pull das OS do ERP + push da fila local.
/// Online só quando a API responde — Wi-Fi/4G sozinhos não bastam.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _intervaloVerificacao = Duration(seconds: 25);

  final _client = ApiClient();
  final _db = AppDatabase.instance;
  final _auth = AuthService();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _syncing = false;
  bool _semRede = false;
  bool _verificando = false;
  ErpAlcance _estado = ErpAlcance.verificando;
  DateTime? _ultimaVerificacao;
  int _pending = 0;
  String? _lastError;

  bool get syncing => _syncing;
  bool get online => _estado == ErpAlcance.online;
  bool get semRede => _semRede;
  ErpAlcance get estado => _estado;
  bool get verificando => _estado == ErpAlcance.verificando;
  bool get podeTentarErp => _estado == ErpAlcance.online && !_semRede;
  int get pending => _pending;
  String? get lastError => _lastError;

  String get estadoLabel => switch (_estado) {
        ErpAlcance.online => 'ERP online',
        ErpAlcance.offline => _semRede ? 'Sem internet' : 'ERP offline',
        ErpAlcance.verificando => 'Verificando ERP',
      };

  void marcarErpInalcancavel() {
    _definirAlcance(temInternet: !_semRede, apiRespondeu: false);
  }

  void marcarErpAlcancavel() {
    _semRede = false;
    _definirAlcance(temInternet: true, apiRespondeu: true);
  }

  void _definirAlcance({required bool temInternet, required bool? apiRespondeu}) {
    _estado = ErpUrl.avaliar(temInternet: temInternet, apiRespondeu: apiRespondeu);
    notifyListeners();
  }

  Future<void> start() async {
    await refreshPending();
    WidgetsBinding.instance.addObserver(this);
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen(_aplicarRede);
    try {
      final now = await Connectivity().checkConnectivity();
      _aplicarRede(now, tentarSync: false);
    } catch (_) {
      _semRede = false;
    }
    unawaited(verificarErp(forcar: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(verificarErp());
    }
  }

  void _aplicarRede(List<ConnectivityResult> results, {bool tentarSync = true}) {
    final semRede = !results.any((r) => r != ConnectivityResult.none);
    final voltouRede = _semRede && !semRede;
    _semRede = semRede;
    if (semRede) {
      _definirAlcance(temInternet: false, apiRespondeu: null);
      return;
    }
    notifyListeners();
    if (tentarSync && voltouRede) {
      unawaited(verificarErp(forcar: true));
    }
  }

  /// Ping leve. Não faz logout, não apaga token nem fila.
  Future<void> verificarErp({
    bool forcar = false,
    bool sincronizarSeOnline = true,
  }) async {
    if (_verificando || _syncing) return;
    if (_semRede) {
      _definirAlcance(temInternet: false, apiRespondeu: null);
      return;
    }
    final agora = DateTime.now();
    if (!forcar &&
        _ultimaVerificacao != null &&
        agora.difference(_ultimaVerificacao!) < _intervaloVerificacao) {
      return;
    }

    _ultimaVerificacao = agora;
    _verificando = true;
    _definirAlcance(temInternet: true, apiRespondeu: null);

    final ok = await _auth.ping();
    _verificando = false;
    if (!ok) {
      _definirAlcance(temInternet: !_semRede, apiRespondeu: false);
      return;
    }

    marcarErpAlcancavel();
    if (sincronizarSeOnline && AppSession.isLoggedIn) {
      await sincronizar();
    }
  }

  /// Pedido do usuário: uma tentativa, mesmo se o ERP estava marcado offline.
  Future<SyncResult> tentarSincronizar() async {
    if (_semRede) {
      marcarErpInalcancavel();
      await refreshPending();
      return SyncResult(
        ok: false,
        pending: _pending,
        message: 'Sem internet no aparelho. As OS continuam salvas neste celular.',
      );
    }
    if (_estado != ErpAlcance.online) {
      await verificarErp(forcar: true, sincronizarSeOnline: false);
    }
    return sincronizar();
  }

  void disposeListener() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _sub = null;
  }

  Future<void> refreshPending() async {
    _pending = await _db.pendingCount();
    notifyListeners();
  }

  Future<SyncResult> sincronizar({bool forcePull = true}) async {
    if (!AppSession.isLoggedIn) {
      return const SyncResult(ok: false, message: 'Faça login para sincronizar.');
    }
    if (!podeTentarErp) {
      await refreshPending();
      return SyncResult(
        ok: false,
        pending: _pending,
        message: 'Sem conexão com o ERP.',
      );
    }
    if (_syncing) {
      return SyncResult(ok: false, pending: _pending, message: 'Sincronização já em andamento.');
    }

    _syncing = true;
    _lastError = null;
    notifyListeners();

    var pulled = 0;
    var pushed = 0;

    try {
      pushed = await _pushQueue();
      if (forcePull && !await _temCriacaoPendente()) {
        pulled = await _pullOrdens();
      }
      final catalogoOk = await _pullCatalogo();
      await refreshPending();
      _syncing = false;
      marcarErpAlcancavel();
      final base = _pending > 0
          ? 'Parcial: $_pending pendente(s).'
          : 'Sincronizado.';
      return SyncResult(
        ok: true,
        pulled: pulled,
        pushed: pushed,
        pending: _pending,
        message: catalogoOk
            ? '$base Catálogo atualizado.'
            : '$base Catálogo não baixou — tente sync de novo.',
      );
    } on ApiException catch (e) {
      if (e.isOffline) marcarErpInalcancavel();
      _lastError = e.message;
      await refreshPending();
      _syncing = false;
      notifyListeners();
      return SyncResult(
        ok: false,
        pulled: pulled,
        pushed: pushed,
        pending: _pending,
        message: e.message,
      );
    } catch (e) {
      _lastError = '$e';
      await refreshPending();
      _syncing = false;
      notifyListeners();
      return SyncResult(
        ok: false,
        pulled: pulled,
        pushed: pushed,
        pending: _pending,
        message: 'Falha na sincronização.',
      );
    }
  }

  Future<int> _pullOrdens() async {
    final json = await _client.getJson('/ordens');
    final data = json['data'];
    if (data is! List) return 0;
    var n = 0;
    for (final item in data) {
      if (item is! Map) continue;
      final os = OrdemServico.fromJson(Map<String, dynamic>.from(item));
      await _db.upsertFromServer(os);
      n++;
    }
    return n;
  }

  bool _catalogoPulling = false;

  /// Retorna true se o catálogo foi gravado localmente.
  Future<bool> _pullCatalogo() async {
    if (!podeTentarErp || _catalogoPulling) {
      return await _db.catalogoSincronizado();
    }
    _catalogoPulling = true;
    try {
      final json = await _client.getJson(
        '/sync/pull',
        timeout: const Duration(seconds: 90),
      );
      final data = json['data'];
      if (data is! Map) return false;
      final map = Map<String, dynamic>.from(data);
      final clientes = (map['clientes'] is List)
          ? (map['clientes'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final produtos = (map['produtos'] is List)
          ? (map['produtos'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final grupos = (map['grupos'] is List)
          ? (map['grupos'] as List).map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      await _db.replaceCatalogo(
        clientes: clientes,
        produtos: produtos,
        grupos: grupos,
      );
      return true;
    } on ApiException catch (e) {
      if (e.isOffline) marcarErpInalcancavel();
      _lastError = e.message;
      return false;
    } catch (e) {
      _lastError = '$e';
      return false;
    } finally {
      _catalogoPulling = false;
    }
  }

  Future<int> _pushQueue() async {
    var done = 0;
    done += await _enviarCriacoes();
    if (!podeTentarErp) return done;
    done += await _enviarAtendimentos();
    if (!podeTentarErp) return done;
    done += await _enviarMidias();
    if (!podeTentarErp) return done;
    done += await _enviarFaturamentos();
    return done;
  }

  Future<bool> _temCriacaoPendente() async {
    final rows = await (await _db.db).query(
      'sync_queue',
      columns: ['id'],
      where: "tipo = 'create'",
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Cria no ERP e só tira da fila depois de gravar `server_id` na mesma linha local.
  Future<int> _enviarCriacoes() async {
    final queue = await _db.pendingQueue();
    var done = 0;

    for (final item in queue) {
      if ('${item['tipo']}' != 'create') continue;
      final id = item['id'] as int;
      final localUuid = '${item['local_uuid']}';
      final payload = jsonDecode('${item['payload_json']}');
      if (payload is! Map) {
        await _db.removeQueueItem(id);
        continue;
      }

      try {
        final gravou = await _enviarCreate(localUuid, Map<String, dynamic>.from(payload));
        if (!gravou) continue;
        final local = await _db.getByKey('l:$localUuid');
        if (local?.id == null) continue;
        await _db.removeQueueItem(id);
        done++;
      } on ApiException catch (e) {
        if (e.isAuth) rethrow;
        if (e.isOffline) marcarErpInalcancavel();
        _lastError = e.message;
        break;
      }
    }
    return done;
  }

  Future<bool> _criarAindaNaFila(String localUuid) async {
    final rows = await (await _db.db).query(
      'sync_queue',
      columns: ['id'],
      where: "tipo = 'create' AND local_uuid = ?",
      whereArgs: [localUuid],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> _enviarAtendimentos() async {
    final queue = await _db.pendingQueue();
    var done = 0;

    for (final item in queue) {
      final id = item['id'] as int;
      final tipo = '${item['tipo']}';
      if (tipo != 'update') continue;
      final localUuid = '${item['local_uuid']}';
      final payload = jsonDecode('${item['payload_json']}');
      if (payload is! Map) {
        await _db.removeQueueItem(id);
        continue;
      }
      final map = Map<String, dynamic>.from(payload);

      try {
        if (await _criarAindaNaFila(localUuid)) continue;

        final finalizar = map['finalizar'] == true;
        final temMidia = await _temMidiaPendente(localUuid);
        if (finalizar && temMidia) {
          final enviou = await _enviarUpdate(localUuid, map, incluirFinalizar: false);
          if (!enviou) continue;
          await (await _db.db).update(
            'sync_queue',
            {
              'payload_json': jsonEncode({
                'id': map['id'],
                'status': map['status'],
                'finalizar': true,
              }),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          done++;
          continue;
        }
        if (finalizar) continue;

        final enviou = await _enviarUpdate(localUuid, map, incluirFinalizar: false);
        if (!enviou) continue;
        await _db.removeQueueItem(id);
        done++;
      } on ApiException catch (e) {
        if (e.isAuth) rethrow;
        if (e.isOffline) marcarErpInalcancavel();
        _lastError = e.message;
        break;
      }
    }
    return done;
  }

  Future<int> _enviarMidias() async {
    final queue = await _db.pendingQueue();
    var done = 0;

    for (final item in queue) {
      final tipo = '${item['tipo']}';
      if (tipo != 'foto' && tipo != 'assinatura') continue;
      final id = item['id'] as int;
      final localUuid = '${item['local_uuid']}';
      final payload = jsonDecode('${item['payload_json']}');
      if (payload is! Map) {
        await _db.removeQueueItem(id);
        continue;
      }
      final map = Map<String, dynamic>.from(payload);

      try {
        if (await _criarAindaNaFila(localUuid)) continue;
        final enviou = await _enviarMidia(localUuid, tipo, map);
        if (!enviou) continue;
        await _db.removeQueueItem(id);
        done++;
      } on ApiException catch (e) {
        if (e.isAuth) rethrow;
        if (e.isOffline) marcarErpInalcancavel();
        _lastError = e.message;
        break;
      }
    }
    return done;
  }

  Future<int> _enviarFaturamentos() async {
    final queue = await _db.pendingQueue();
    var done = 0;

    for (final item in queue) {
      if ('${item['tipo']}' != 'update') continue;
      final id = item['id'] as int;
      final localUuid = '${item['local_uuid']}';
      final payload = jsonDecode('${item['payload_json']}');
      if (payload is! Map) {
        await _db.removeQueueItem(id);
        continue;
      }
      final map = Map<String, dynamic>.from(payload);
      if (map['finalizar'] != true) continue;
      if (await _criarAindaNaFila(localUuid)) continue;
      if (await _temMidiaPendente(localUuid)) continue;

      try {
        final enviou = await _enviarUpdate(localUuid, map, incluirFinalizar: true);
        if (!enviou) continue;
        await _db.removeQueueItem(id);
        done++;
      } on ApiException catch (e) {
        if (e.isAuth) rethrow;
        if (e.isOffline) marcarErpInalcancavel();
        _lastError = e.message;
        break;
      }
    }
    return done;
  }

  Future<bool> _temMidiaPendente(String localUuid) async {
    final rows = await (await _db.db).query(
      'sync_queue',
      where: "local_uuid = ? AND tipo IN ('foto', 'assinatura')",
      whereArgs: [localUuid],
    );
    return rows.isNotEmpty;
  }

  String _numeroEndereco(Map<String, dynamic> map) {
    final rua = '${map['numero'] ?? ''}'.trim();
    if (rua.startsWith('OFF-')) return '';
    return rua;
  }

  /// Devolve true só depois que `server_id` e `numero_os` estão na linha do [localUuid].
  /// Não gera outro UUID. `200` e `201` são sucesso.
  Future<bool> _enviarCreate(String localUuid, Map<String, dynamic> map) async {
    if (localUuid.isEmpty) return false;

    final jaVinculada = await _db.getByKey('l:$localUuid');
    if (jaVinculada?.id != null) return true;

    await DeviceIdentity.ensureReady();
    final deviceUuid = '${map['device_uuid'] ?? ''}'.trim();
    final json = await _client.postJson(
      '/ordens',
      body: OsCreateVinculo.corpo(
        localUuid: localUuid,
        deviceUuid: deviceUuid.isNotEmpty ? deviceUuid : DeviceIdentity.uuid,
        campos: {
          if (map['cliente_id'] != null) 'cliente_id': map['cliente_id'],
          'cliente': '${map['cliente'] ?? ''}'.trim(),
          'nome_fantasia': '${map['nome_fantasia'] ?? ''}'.trim(),
          'telefone': '${map['telefone'] ?? ''}'.trim(),
          'email': '${map['email'] ?? ''}'.trim(),
          'cpf_cnpj': '${map['cpf_cnpj'] ?? ''}'.trim(),
          'cep': '${map['cep'] ?? ''}'.trim(),
          'endereco': '${map['endereco'] ?? ''}'.trim(),
          'numero': _numeroEndereco(map),
          'bairro': '${map['bairro'] ?? ''}'.trim(),
          'cidade': '${map['cidade'] ?? ''}'.trim(),
          'uf': '${map['uf'] ?? ''}'.trim(),
          'equipamento': '${map['equipamento'] ?? ''}'.trim(),
          'problema': '${map['problema'] ?? ''}'.trim(),
        },
      ),
      auth: true,
    );
    final vinculo = OsCreateVinculo.lerResposta(json);
    if (vinculo == null) return false;

    final data = json['data'];
    final fallback = data is Map
        ? OrdemServico.fromJson(Map<String, dynamic>.from(data)).copyWith(
            localUuid: localUuid,
            id: vinculo.serverId,
            numero: vinculo.numeroOficial,
          )
        : null;
    await _db.vincularServidor(
      localUuid: localUuid,
      serverId: vinculo.serverId,
      numeroOficial: vinculo.numeroOficial,
      fallback: fallback,
    );
    final gravada = await _db.getByKey('l:$localUuid');
    return gravada?.id == vinculo.serverId && gravada?.localUuid == localUuid;
  }

  Future<bool> _enviarUpdate(
    String localUuid,
    Map<String, dynamic> map, {
    required bool incluirFinalizar,
  }) async {
    if (await _criarAindaNaFila(localUuid)) return false;
    final local = await _db.getByKey('l:$localUuid');
    final serverId = local?.id;
    if (serverId == null) return false;

    final body = <String, dynamic>{
      if (map['status'] != null) 'status': map['status'],
      if (map['hora_inicio'] != null) 'hora_inicio': map['hora_inicio'],
      if (map['servico_realizado'] != null) 'servico_realizado': map['servico_realizado'],
      if (map['observacoes'] != null) 'observacoes': map['observacoes'],
      if (map['pecas'] != null) 'pecas': map['pecas'],
      if (map['servicos'] != null) 'servicos': map['servicos'],
      if (map['iniciar_atendimento'] == true) 'iniciar_atendimento': true,
      if (incluirFinalizar && map['finalizar'] == true) 'finalizar': true,
    };
    final json = await _client.putJson('/ordens/$serverId', body: body);
    final data = json['data'];
    if (data is Map && (incluirFinalizar || map['finalizar'] != true)) {
      final serverOs = OrdemServico.fromJson(Map<String, dynamic>.from(data));
      await _db.markSynced(localUuid, serverOs);
    }
    return true;
  }

  /// Envia a mídia. `false` = ainda sem server_id, item permanece na fila.
  Future<bool> _enviarMidia(
    String localUuid,
    String tipo,
    Map<String, dynamic> map,
  ) async {
    if (await _criarAindaNaFila(localUuid)) return false;
    final local = await _db.getByKey('l:$localUuid');
    final serverId = local?.id;
    if (serverId == null) return false;

    final path = '${map['path'] ?? ''}';
    if (path.isEmpty) return true;
    final arquivo = File(path);
    final marcador = File('$path.ok');
    if (await marcador.exists()) return true;
    if (!await arquivo.exists()) return true;

    final bytes = await arquivo.readAsBytes();
    final nome = arquivo.uri.pathSegments.isNotEmpty
        ? arquivo.uri.pathSegments.last
        : (tipo == 'assinatura' ? 'assinatura.png' : 'foto.jpg');
    await _client.postMultipart(
      tipo == 'assinatura' ? '/ordens/$serverId/assinatura' : '/ordens/$serverId/fotos',
      fieldName: tipo == 'assinatura' ? 'assinatura' : 'foto',
      bytes: bytes,
      filename: nome,
      contentType: tipo == 'assinatura' ? 'image/png' : 'image/jpeg',
    );
    await marcador.writeAsString(DateTime.now().toIso8601String(), flush: true);
    return true;
  }
}
