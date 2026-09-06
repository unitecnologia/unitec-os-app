import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:unitec_os_app/data/local/app_database.dart';
import 'package:unitec_os_app/models/ordem_servico.dart';
import 'package:unitec_os_app/services/api_client.dart';
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

/// Pull das OS do ERP + push da fila local. Auto ao voltar online.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  final _client = ApiClient();
  final _db = AppDatabase.instance;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _syncing = false;
  bool _online = true;
  int _pending = 0;
  String? _lastError;

  bool get syncing => _syncing;
  bool get online => _online;
  int get pending => _pending;
  String? get lastError => _lastError;

  Future<void> start() async {
    await refreshPending();
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      final wasOffline = !_online;
      _online = online;
      notifyListeners();
      if (online && wasOffline && AppSession.isLoggedIn) {
        unawaited(sincronizar());
      }
    });
    try {
      final now = await Connectivity().checkConnectivity();
      _online = now.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      _online = true;
    }
    notifyListeners();
  }

  void disposeListener() {
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
      if (forcePull) {
        pulled = await _pullOrdens();
      }
      await refreshPending();
      _syncing = false;
      notifyListeners();
      return SyncResult(
        ok: true,
        pulled: pulled,
        pushed: pushed,
        pending: _pending,
        message: _pending > 0
            ? 'Parcial: $_pending pendente(s).'
            : 'Sincronizado.',
      );
    } on ApiException catch (e) {
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

  Future<int> _pushQueue() async {
    final queue = await _db.pendingQueue();
    var done = 0;

    for (final item in queue) {
      final id = item['id'] as int;
      final tipo = '${item['tipo']}';
      final localUuid = '${item['local_uuid']}';
      final payload = jsonDecode('${item['payload_json']}');
      if (payload is! Map) {
        await _db.removeQueueItem(id);
        continue;
      }
      final map = Map<String, dynamic>.from(payload);

      try {
        if (tipo == 'create') {
          final json = await _client.postJson(
            '/ordens',
            body: {
              if (map['cliente_id'] != null) 'cliente_id': map['cliente_id'],
              'cliente': '${map['cliente'] ?? ''}'.trim(),
              'telefone': '${map['telefone'] ?? ''}'.trim(),
              'email': '${map['email'] ?? ''}'.trim(),
              'cpf_cnpj': '${map['cpf_cnpj'] ?? ''}'.trim(),
              'cep': '${map['cep'] ?? ''}'.trim(),
              'endereco': '${map['endereco'] ?? ''}'.trim(),
              'numero': '${map['numero'] ?? ''}'.trim(),
              'bairro': '${map['bairro'] ?? ''}'.trim(),
              'cidade': '${map['cidade'] ?? ''}'.trim(),
              'uf': '${map['uf'] ?? ''}'.trim(),
              'equipamento': '${map['equipamento'] ?? ''}'.trim(),
              'problema': '${map['problema'] ?? ''}'.trim(),
            },
            auth: true,
          );
          final data = json['data'];
          if (data is Map) {
            final serverOs = OrdemServico.fromJson(Map<String, dynamic>.from(data));
            await _db.markSynced(localUuid, serverOs);
          }
        } else if (tipo == 'update') {
          final local = await _db.getByKey('l:$localUuid');
          final serverId = local?.id ??
              (map['id'] is int
                  ? map['id'] as int
                  : int.tryParse('${map['id'] ?? ''}'));
          if (serverId == null) {
            // Ainda sem id no servidor — aguarda o create anterior.
            continue;
          }
          final body = <String, dynamic>{
            if (map['status'] != null) 'status': map['status'],
            if (map['hora_inicio'] != null) 'hora_inicio': map['hora_inicio'],
            if (map['servico_realizado'] != null)
              'servico_realizado': map['servico_realizado'],
            if (map['observacoes'] != null) 'observacoes': map['observacoes'],
            if (map['pecas'] != null) 'pecas': map['pecas'],
            if (map['servicos'] != null) 'servicos': map['servicos'],
            if (map['iniciar_atendimento'] == true) 'iniciar_atendimento': true,
            if (map['finalizar'] == true) 'finalizar': true,
          };
          final json = await _client.putJson('/ordens/$serverId', body: body);
          final data = json['data'];
          if (data is Map) {
            final serverOs = OrdemServico.fromJson(Map<String, dynamic>.from(data));
            await _db.markSynced(localUuid, serverOs);
          }
        }
        await _db.removeQueueItem(id);
        done++;
      } on ApiException catch (e) {
        if (e.statusCode == 401) rethrow;
        // Mantém na fila para tentar depois.
        _lastError = e.message;
        break;
      }
    }
    return done;
  }
}
