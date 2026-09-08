import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:unitec_os_app/data/local/app_database.dart';
import 'package:unitec_os_app/models/ordem_servico.dart';
import 'package:unitec_os_app/models/peca_os.dart';
import 'package:unitec_os_app/services/api_client.dart';
import 'package:unitec_os_app/services/sync_service.dart';
import 'package:unitec_os_app/session/app_session.dart';

class ClienteResumo {
  const ClienteResumo({
    required this.id,
    required this.nome,
    this.telefone = '',
    this.email = '',
    this.cpfCnpj = '',
    this.cep = '',
    this.endereco = '',
    this.enderecoCompleto = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
  });

  final int id;
  final String nome;
  final String telefone;
  final String email;
  final String cpfCnpj;
  final String cep;
  final String endereco;
  final String enderecoCompleto;
  final String numero;
  final String bairro;
  final String cidade;
  final String uf;

  factory ClienteResumo.fromJson(Map<String, dynamic> json) {
    return ClienteResumo(
      id: json['id'] is int ? json['id'] as int : int.parse('${json['id']}'),
      nome: '${json['nome'] ?? ''}',
      telefone: '${json['telefone'] ?? ''}',
      email: '${json['email'] ?? ''}',
      cpfCnpj: '${json['cpf_cnpj'] ?? ''}',
      cep: '${json['cep'] ?? ''}',
      endereco: '${json['endereco'] ?? ''}',
      enderecoCompleto: '${json['endereco_completo'] ?? json['endereco'] ?? ''}',
      numero: '${json['numero'] ?? ''}',
      bairro: '${json['bairro'] ?? ''}',
      cidade: '${json['cidade'] ?? ''}',
      uf: '${json['uf'] ?? ''}',
    );
  }
}

class ProdutoResumo {
  const ProdutoResumo({
    required this.id,
    required this.descricao,
    this.codigo = '',
    this.unidade = 'UN',
    this.preco = 0,
  });

  final int id;
  final String descricao;
  final String codigo;
  final String unidade;
  final double preco;

  factory ProdutoResumo.fromJson(Map<String, dynamic> json) {
    return ProdutoResumo(
      id: json['id'] is int ? json['id'] as int : int.parse('${json['id']}'),
      descricao: '${json['descricao'] ?? ''}',
      codigo: '${json['codigo'] ?? ''}',
      unidade: '${json['unidade'] ?? 'UN'}',
      preco: json['preco'] is num
          ? (json['preco'] as num).toDouble()
          : double.tryParse('${json['preco'] ?? 0}') ?? 0,
    );
  }
}

/// Local-first: lê/grava SQLite; enfileira mutações; tenta sync se online.
class OsService {
  OsService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;
  final _db = AppDatabase.instance;

  Future<List<OrdemServico>> listarMinhas({bool tentarSync = true}) async {
    if (tentarSync && AppSession.isLoggedIn) {
      try {
        await SyncService.instance.sincronizar();
      } catch (_) {
        // Offline / falha → usa cache local.
      }
    }
    return _db.listOrdens();
  }

  Future<OrdemServico?> obterPorKey(String key) async {
    final local = await _db.getByKey(key);
    if (local != null) return local;

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
  }) async {
    final q = termo.trim();
    final params = <String>['tipo=${Uri.encodeQueryComponent(tipo)}'];
    if (q.isNotEmpty) {
      params.add('q=${Uri.encodeQueryComponent(q)}');
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

    final body = <String, dynamic>{
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
    };

    try {
      final json = await _client.postJson(
        '/ordens',
        body: body,
        auth: true,
      );
      final dataMap = json['data'];
      if (dataMap is! Map) {
        throw ApiException('Resposta inválida ao criar OS.');
      }
      final os = OrdemServico.fromJson(Map<String, dynamic>.from(dataMap));
      await _db.upsertFromServer(os);
      final saved = await _db.getByKey('s:${os.id}') ?? os;
      return (
        os: saved,
        clienteCriado: json['cliente_criado'] == true,
        offline: false,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401) rethrow;
    } catch (_) {}

    final localUuid = _db.newLocalUuid();
    final short = localUuid.substring(0, 8).toUpperCase();
    final draft = OrdemServico(
      localUuid: localUuid,
      numero: 'OFF-$short',
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
    final json = await _client.getJson('/cep/$digits', auth: true);
    final data = json['data'];
    if (data is! Map) {
      throw ApiException('${json['message'] ?? 'CEP não encontrado.'}');
    }
    return data.map((k, v) => MapEntry('$k', v?.toString() ?? ''));
  }

  Future<void> enviarFotoOs({
    required int osId,
    required File arquivo,
  }) async {
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
    };
    await database.insert('sync_queue', {
      'tipo': 'create',
      'local_uuid': os.localUuid,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
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
      nextStatus = 'Finalizada';
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

    if (next.id != null) {
      try {
        final json = await _client.putJson(
          '/ordens/${next.id}',
          body: {
            'status': next.status,
            // No iniciar, o servidor grava/preserva hora_inicio (não sobrescreve).
            if (!iniciar && next.horaInicio != null) 'hora_inicio': next.horaInicio,
            if (servicoRealizado != null) 'servico_realizado': next.servicoRealizado,
            if (observacoes != null) 'observacoes': next.observacao,
            if (pecas != null) 'pecas': next.pecas.map((e) => e.toJson()).toList(),
            if (servicos != null)
              'servicos': next.servicos.map((e) => e.toJson()).toList(),
            if (iniciar) 'iniciar_atendimento': true,
            if (finalizar) 'finalizar': true,
          },
        );
        final data = json['data'];
        if (data is Map) {
          final serverOs = OrdemServico.fromJson(Map<String, dynamic>.from(data));
          await _db.upsertFromServer(serverOs);
          return (await _db.getByKey('s:${serverOs.id}')) ?? serverOs;
        }
      } on ApiException {
        rethrow;
      } catch (_) {}
    }

    final localUuid = next.localUuid ?? _db.newLocalUuid();
    next = next.copyWith(localUuid: localUuid);

    final payload = next.toJson()
      ..['iniciar_atendimento'] = iniciar
      ..['finalizar'] = finalizar;

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
    await database.insert('sync_queue', {
      'tipo': 'update',
      'local_uuid': localUuid,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });

    await SyncService.instance.refreshPending();
    // ignore: discarded_futures
    SyncService.instance.sincronizar(forcePull: false);

    return next;
  }
}
