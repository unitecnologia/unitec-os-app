import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:unitec_os_app/config/device_identity.dart';
import 'package:unitec_os_app/data/local/app_database.dart';
import 'package:unitec_os_app/models/cliente_resumo.dart';
import 'package:unitec_os_app/models/ordem_servico.dart';
import 'package:unitec_os_app/models/peca_os.dart';
import 'package:unitec_os_app/models/produto_resumo.dart';
import 'package:unitec_os_app/services/api_client.dart';
import 'package:unitec_os_app/services/os_create_vinculo.dart';
import 'package:unitec_os_app/services/sync_service.dart';
import 'package:unitec_os_app/session/app_session.dart';

export 'package:unitec_os_app/models/cliente_resumo.dart';
export 'package:unitec_os_app/models/produto_resumo.dart';

/// Local-first: lê/grava SQLite; enfileira mutações; tenta sync se online.
class OsService {
  OsService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;
  final _db = AppDatabase.instance;

  Future<List<OrdemServico>> listarMinhas({bool tentarSync = true}) async {
    if (tentarSync && AppSession.isLoggedIn) {
      try {
        await SyncService.instance.tentarSincronizar();
      } catch (_) {
        // Offline / falha → usa cache local.
      }
    }
    return _db.listOrdens();
  }

  Future<OrdemServico?> obterPorKey(String key) async {
    final local = await _db.getByKey(key);
    if (local != null) return local;
    if (!SyncService.instance.podeTentarErp) return null;

    if (key.startsWith('s:')) {
      final id = int.tryParse(key.substring(2));
      if (id != null) {
        try {
          final os = await _obterRemoto(id);
          await _db.upsertFromServer(os);
          return await _db.getByKey(key) ?? os;
        } catch (_) {}
      }
    }
    final id = int.tryParse(key);
    if (id != null) {
      try {
        final os = await _obterRemoto(id);
        await _db.upsertFromServer(os);
        return await _db.getByKey('s:$id') ?? os;
      } catch (_) {}
    }
    return null;
  }

  Future<OrdemServico> _obterRemoto(int id) async {
    final json = await _client.getJson('/ordens/$id');
    final data = json['data'];
    if (data is! Map) {
      throw ApiException('OS não encontrada.', statusCode: 404);
    }
    return OrdemServico.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<ClienteResumo>> buscarClientes(String termo) async {
    final locais = await _db.buscarClientesLocal(termo);
    if (await _db.catalogoSincronizado() || !SyncService.instance.podeTentarErp) {
      return locais;
    }
    // Fallback online se o catálogo ainda não foi baixado.
    final q = termo.trim();
    final path = q.isEmpty
        ? '/clientes'
        : '/clientes?q=${Uri.encodeQueryComponent(q)}';
    try {
      final json = await _client.getJson(path);
      final data = json['data'];
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((e) => ClienteResumo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on ApiException {
      return [];
    }
  }

  Future<List<ProdutoResumo>> buscarProdutos(
    String termo, {
    String tipo = 'produto',
    String? grupo,
  }) async {
    final locais = await _db.buscarProdutosLocal(
      termo,
      tipo: tipo,
      grupo: grupo,
    );
    if (locais.isNotEmpty || await _db.catalogoSincronizado() || !SyncService.instance.podeTentarErp) {
      return locais;
    }
    final q = termo.trim();
    final params = <String>['tipo=${Uri.encodeQueryComponent(tipo)}'];
    if (q.isNotEmpty) {
      params.add('q=${Uri.encodeQueryComponent(q)}');
    }
    final g = (grupo ?? '').trim();
    if (g.isNotEmpty) {
      params.add('grupo=${Uri.encodeQueryComponent(g)}');
    }
    final path = '/produtos?${params.join('&')}';
    try {
      final json = await _client.getJson(path);
      final data = json['data'];
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((e) => ProdutoResumo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on ApiException {
      return [];
    }
  }

  Future<List<String>> buscarGrupos() async {
    final locais = await _db.listarGruposLocal();
    if (locais.isNotEmpty || await _db.catalogoSincronizado() || !SyncService.instance.podeTentarErp) {
      return locais;
    }
    try {
      final json = await _client.getJson('/grupos');
      final data = json['data'];
      if (data is! List) return [];
      return data
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } on ApiException {
      return [];
    }
  }

  Future<bool> catalogoDisponivel() => _db.catalogoSincronizado();

  Future<List<ProdutoResumo>> buscarServicos(String termo) {
    return buscarProdutos(termo, tipo: 'servico');
  }

  Future<({OrdemServico os, bool clienteCriado, bool offline})> criarOs({
    int? clienteId,
    required String cliente,
    String nomeFantasia = '',
    String telefone = '',
    String email = '',
    String cpfCnpj = '',
    String cep = '',
    String endereco = '',
    String numero = '',
    String bairro = '',
    String cidade = '',
    String uf = '',
    String equipamento = '',
    String problema = '',
  }) async {
    final agora = DateTime.now();
    final hora =
        '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';
    final dataHora =
        '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')} $hora';

    final enderecoExibicao = _montarEndereco(
      logradouro: endereco,
      numero: numero,
      bairro: bairro,
      cidade: cidade,
      uf: uf,
      cep: cep,
    );

    final localUuid = _db.newLocalUuid();
    await DeviceIdentity.ensureReady();

    final body = OsCreateVinculo.corpo(
      localUuid: localUuid,
      deviceUuid: DeviceIdentity.uuid,
      campos: {
      'cliente_id': ?clienteId,
      'cliente': cliente.trim(),
      'nome_fantasia': nomeFantasia.trim(),
      'telefone': telefone.trim(),
      'email': email.trim(),
      'cpf_cnpj': cpfCnpj.trim(),
      'cep': cep.trim(),
      'endereco': endereco.trim(),
      'numero': numero.trim(),
      'bairro': bairro.trim(),
      'cidade': cidade.trim(),
      'uf': uf.trim().toUpperCase(),
      'equipamento': equipamento.trim(),
      'problema': problema.trim(),
      },
    );

    try {
      if (!SyncService.instance.podeTentarErp) {
        throw ApiException('Sem conexão com o ERP.');
      }
      final json = await _client.postJson(
        '/ordens',
        body: body,
        auth: true,
      );
      final dataMap = json['data'];
      if (dataMap is! Map) {
        throw ApiException('Resposta inválida ao criar OS.');
      }
      final vinculo = OsCreateVinculo.lerResposta(json);
      if (vinculo == null) {
        throw ApiException('Resposta inválida ao criar OS.');
      }
      final os = OrdemServico.fromJson(Map<String, dynamic>.from(dataMap)).copyWith(
        localUuid: localUuid,
        id: vinculo.serverId,
        numero: vinculo.numeroOficial,
      );
      await _db.vincularServidor(
        localUuid: localUuid,
        serverId: vinculo.serverId,
        numeroOficial: vinculo.numeroOficial,
        fallback: os,
      );
      final saved = await _db.getByKey('l:$localUuid') ?? os;
      return (
        os: saved,
        clienteCriado: json['cliente_criado'] == true,
        offline: false,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401) rethrow;
    } catch (_) {}

    final short = localUuid.substring(0, 8).toUpperCase();
    final draft = OrdemServico(
      localUuid: localUuid,
      numero: 'OFF-$short',
      numeroOffline: 'OFF-$short',
      cliente: cliente.trim().toUpperCase(),
      telefone: telefone.trim(),
      endereco: enderecoExibicao,
      equipamento: equipamento.trim().toUpperCase(),
      problema: problema.trim(),
      servico: equipamento.trim().toUpperCase(),
      status: 'Pendente',
      dataHora: dataHora,
      tecnico: AppSession.usuario,
      dirty: true,
      pendingSync: true,
    );

    await _db.saveLocal(draft, tipoFila: 'create');
    await _replaceCreatePayload(draft, body);

    await SyncService.instance.refreshPending();
    // ignore: discarded_futures
    SyncService.instance.sincronizar(forcePull: false);

    return (os: draft, clienteCriado: false, offline: true);
  }

  String _montarEndereco({
    required String logradouro,
    required String numero,
    required String bairro,
    required String cidade,
    required String uf,
    required String cep,
  }) {
    final partes = <String>[
      [
        logradouro.trim().toUpperCase(),
        if (numero.trim().isNotEmpty) numero.trim(),
      ].where((e) => e.isNotEmpty).join(', '),
      if (bairro.trim().isNotEmpty) bairro.trim().toUpperCase(),
      [
        if (cidade.trim().isNotEmpty) cidade.trim().toUpperCase(),
        if (uf.trim().isNotEmpty) uf.trim().toUpperCase(),
      ].where((e) => e.isNotEmpty).join('/'),
      if (cep.trim().isNotEmpty) cep.trim(),
    ].where((e) => e.isNotEmpty).toList();
    return partes.join(' — ');
  }

  Future<Map<String, String>> consultarCnpj(String cnpj) async {
    final digits = cnpj.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 14) {
      throw ApiException('Informe um CNPJ completo com 14 dígitos.');
    }
    if (!SyncService.instance.podeTentarErp) {
      throw ApiException('Sem conexão com o ERP.');
    }
    final json = await _client.getJson('/cnpj/$digits', auth: true);
    final data = json['data'];
    if (data is! Map) {
      throw ApiException('${json['message'] ?? 'CNPJ não encontrado.'}');
    }
    return data.map((k, v) => MapEntry('$k', v?.toString() ?? ''));
  }

  Future<Map<String, String>> consultarCep(String cep) async {
    final digits = cep.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) {
      throw ApiException('Informe um CEP completo com 8 dígitos.');
    }
    if (!SyncService.instance.podeTentarErp) {
      throw ApiException('Sem conexão com o ERP.');
    }
    final json = await _client.getJson('/cep/$digits', auth: true);
    final data = json['data'];
    if (data is! Map) {
      throw ApiException('${json['message'] ?? 'CEP não encontrado.'}');
    }
    return data.map((k, v) => MapEntry('$k', v?.toString() ?? ''));
  }

  Future<void> enfileirarMidia({
    required String localUuid,
    int? serverId,
    required String tipo,
    required String path,
  }) async {
    final database = await _db.db;
    final rows = await database.query(
      'sync_queue',
      where: 'local_uuid = ? AND tipo = ?',
      whereArgs: [localUuid, tipo],
    );
    for (final row in rows) {
      final raw = jsonDecode('${row['payload_json']}');
      if (raw is Map && raw['path'] == path) return;
    }

    await database.insert('sync_queue', {
      'tipo': tipo,
      'local_uuid': localUuid,
      'payload_json': jsonEncode({
        'path': path,
        'server_id': serverId,
      }),
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await SyncService.instance.refreshPending();
  }

  Future<void> removerMidiaFila(String path) async {
    final database = await _db.db;
    final rows = await database.query(
      'sync_queue',
      where: "tipo IN ('foto', 'assinatura')",
    );
    for (final row in rows) {
      final raw = jsonDecode('${row['payload_json']}');
      if (raw is Map && raw['path'] == path) {
        await database.delete('sync_queue', where: 'id = ?', whereArgs: [row['id']]);
      }
    }
    await SyncService.instance.refreshPending();
  }

  Future<void> enviarFotoOs({
    required int osId,
    required File arquivo,
  }) async {
    if (!SyncService.instance.podeTentarErp) {
      throw ApiException('Sem conexão com o ERP.');
    }
    final bytes = await arquivo.readAsBytes();
    final nome = arquivo.uri.pathSegments.isNotEmpty
        ? arquivo.uri.pathSegments.last
        : 'foto.jpg';
    await _client.postMultipart(
      '/ordens/$osId/fotos',
      fieldName: 'foto',
      bytes: bytes,
      filename: nome,
      contentType: 'image/jpeg',
    );
  }

  Future<void> enviarAssinaturaOs({
    required int osId,
    required List<int> pngBytes,
  }) async {
    if (!SyncService.instance.podeTentarErp) {
      throw ApiException('Sem conexão com o ERP.');
    }
    await _client.postMultipart(
      '/ordens/$osId/assinatura',
      fieldName: 'assinatura',
      bytes: pngBytes,
      filename: 'assinatura.png',
      contentType: 'image/png',
    );
  }

  Future<void> _replaceCreatePayload(
    OrdemServico os,
    Map<String, dynamic> body,
  ) async {
    final database = await _db.db;
    await database.delete(
      'sync_queue',
      where: 'local_uuid = ? AND tipo = ?',
      whereArgs: [os.localUuid, 'create'],
    );
    final payload = {
      ...os.toJson(),
      ...body,
      'app_local_uuid': os.localUuid,
      'device_uuid': body['device_uuid'],
    };
    await database.insert('sync_queue', {
      'tipo': 'create',
      'local_uuid': os.localUuid,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
  }

  /// Grava o relato no SQLite e na mesma fila pendente do atendimento.
  /// Não chama a API aqui — o sync já envia `servico_realizado`.
  Future<OrdemServico> gravarServicoPrestadoLocal(OrdemServico os, String texto) async {
    final gravada = await _db.gravarServicoRealizado(os, texto.trim());
    await SyncService.instance.refreshPending();
    return gravada;
  }

  Future<OrdemServico> atualizarAtendimento({
    required OrdemServico os,
    String? status,
    String? horaInicio,
    String? servicoRealizado,
    String? observacoes,
    List<PecaOs>? pecas,
    List<PecaOs>? servicos,
    bool iniciar = false,
    bool finalizar = false,
  }) async {
    var nextStatus = os.status;
    if (finalizar) {
      nextStatus = 'Em faturamento';
    } else if (status != null) {
      nextStatus = status;
    } else if (iniciar && os.status == 'Pendente') {
      nextStatus = 'Em andamento';
    }

    var next = os.copyWith(
      status: nextStatus,
      horaInicio: horaInicio ?? os.horaInicio,
      servicoRealizado: servicoRealizado ?? os.servicoRealizado,
      observacao: observacoes ?? os.observacao,
      pecas: pecas ?? os.pecas,
      servicos: servicos ?? os.servicos,
      dirty: true,
      pendingSync: true,
    );

    if (iniciar && (next.horaInicio == null || next.horaInicio!.isEmpty)) {
      final agora = DateTime.now();
      next = next.copyWith(
        horaInicio:
            '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}',
      );
    }

    if (iniciar && next.tecnico.trim().isEmpty) {
      next = next.copyWith(tecnico: AppSession.usuario);
    }

    final gravado = await _persistirAtendimentoLocal(
      next,
      iniciar: iniciar,
      finalizar: finalizar,
    );
    next = gravado.os;

    if (next.id == null || !SyncService.instance.podeTentarErp) {
      return next;
    }

    try {
      final json = await _client.putJson(
        '/ordens/${next.id}',
        body: _corpoAtendimento(
          next,
          iniciar: gravado.iniciar,
          finalizar: gravado.finalizar,
        ),
      );
      final data = json['data'];
      if (data is Map) {
        final serverOs = OrdemServico.fromJson(Map<String, dynamic>.from(data));
        await _db.markSynced(next.localUuid!, serverOs);
        await _removerFilaUpdate(next.localUuid!);
        SyncService.instance.marcarErpAlcancavel();
        await SyncService.instance.refreshPending();
        return (await _db.getByKey('s:${serverOs.id}')) ??
            serverOs.copyWith(localUuid: next.localUuid, pendingSync: false, dirty: false);
      }
    } on ApiException catch (e) {
      if (e.isAuth) rethrow;
      if (e.isOffline) SyncService.instance.marcarErpInalcancavel();
      if (!e.isOffline) rethrow;
    } catch (_) {
      SyncService.instance.marcarErpInalcancavel();
    }

    return next;
  }

  Map<String, dynamic> _corpoAtendimento(
    OrdemServico os, {
    required bool iniciar,
    required bool finalizar,
  }) {
    return {
      'status': os.status,
      if (!iniciar && os.horaInicio != null) 'hora_inicio': os.horaInicio,
      'servico_realizado': os.servicoRealizado,
      'observacoes': os.observacao,
      'pecas': os.pecas.map((e) => e.toJson()).toList(),
      'servicos': os.servicos.map((e) => e.toJson()).toList(),
      if (iniciar) 'iniciar_atendimento': true,
      if (finalizar) 'finalizar': true,
    };
  }

  Future<({OrdemServico os, bool iniciar, bool finalizar})> _persistirAtendimentoLocal(
    OrdemServico os, {
    required bool iniciar,
    required bool finalizar,
  }) async {
    var localUuid = os.localUuid;
    if ((localUuid == null || localUuid.isEmpty) && os.id != null) {
      localUuid = (await _db.getByKey('s:${os.id}'))?.localUuid;
    }
    localUuid ??= _db.newLocalUuid();
    final next = os.copyWith(localUuid: localUuid, dirty: true, pendingSync: true);
    final database = await _db.db;

    await database.insert(
      'ordens',
      {
        'local_uuid': localUuid,
        'server_id': next.id,
        'numero': next.numero,
        'cliente': next.cliente,
        'telefone': next.telefone,
        'endereco': next.endereco,
        'equipamento': next.equipamento,
        'problema': next.problema,
        'status': next.status,
        'data_hora': next.dataHora,
        'tecnico': next.tecnico,
        'servico_realizado': next.servicoRealizado,
        'observacoes': next.observacao,
        'pecas_json': jsonEncode(next.pecas.map((e) => e.toJson()).toList()),
        'servicos_json': jsonEncode(next.servicos.map((e) => e.toJson()).toList()),
        'hora_inicio': next.horaInicio,
        'dirty': 1,
        'pending_sync': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    var iniciarFila = iniciar;
    var finalizarFila = finalizar;
    final anteriores = await database.query(
      'sync_queue',
      where: 'local_uuid = ? AND tipo = ?',
      whereArgs: [localUuid, 'update'],
    );
    for (final row in anteriores) {
      final raw = jsonDecode('${row['payload_json']}');
      if (raw is! Map) continue;
      if (raw['iniciar_atendimento'] == true) iniciarFila = true;
      if (raw['finalizar'] == true) finalizarFila = true;
    }
    await database.delete(
      'sync_queue',
      where: 'local_uuid = ? AND tipo = ?',
      whereArgs: [localUuid, 'update'],
    );

    final payload = next.toJson()
      ..['iniciar_atendimento'] = iniciarFila
      ..['finalizar'] = finalizarFila;
    await database.insert('sync_queue', {
      'tipo': 'update',
      'local_uuid': localUuid,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });

    await SyncService.instance.refreshPending();
    return (os: next, iniciar: iniciarFila, finalizar: finalizarFila);
  }

  Future<void> _removerFilaUpdate(String localUuid) async {
    await (await _db.db).delete(
      'sync_queue',
      where: 'local_uuid = ? AND tipo = ?',
      whereArgs: [localUuid, 'update'],
    );
  }
}
