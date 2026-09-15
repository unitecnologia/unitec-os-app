import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:unitec_os_app/models/cliente_resumo.dart';
import 'package:unitec_os_app/models/ordem_servico.dart';
import 'package:unitec_os_app/models/peca_os.dart';
import 'package:unitec_os_app/models/produto_resumo.dart';
import 'package:uuid/uuid.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  final _uuid = const Uuid();

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'unitec_os.db');
    _db = await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await _createOrdens(db);
        await _createSyncQueue(db);
        await _createCatalogo(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _ensureColumn(db, 'ordens', 'servicos_json', 'TEXT');
        }
        if (oldVersion < 3) {
          await _ensureColumn(db, 'ordens', 'numero_offline', 'TEXT');
        }
        if (oldVersion < 4) {
          await _ensureColumn(db, 'ordens', 'servico_realizado', 'TEXT');
        }
        if (oldVersion < 5) {
          await _createCatalogo(db);
        }
      },
    );
    return _db!;
  }

  Future<void> _createOrdens(Database db) async {
    await db.execute('''
      CREATE TABLE ordens (
        local_uuid TEXT PRIMARY KEY,
        server_id INTEGER,
        numero TEXT NOT NULL,
        numero_offline TEXT,
        cliente TEXT NOT NULL,
        telefone TEXT,
        endereco TEXT,
        equipamento TEXT,
        problema TEXT,
        status TEXT NOT NULL,
        data_hora TEXT,
        tecnico TEXT,
        servico_realizado TEXT,
        observacoes TEXT,
        pecas_json TEXT,
        servicos_json TEXT,
        hora_inicio TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_sync INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_ordens_server ON ordens(server_id)');
  }

  Future<void> _createSyncQueue(Database db) async {
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        local_uuid TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createCatalogo(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clientes (
        id INTEGER PRIMARY KEY,
        nome TEXT NOT NULL,
        fantasia TEXT,
        telefone TEXT,
        email TEXT,
        cpf_cnpj TEXT,
        cep TEXT,
        endereco TEXT,
        endereco_completo TEXT,
        numero TEXT,
        bairro TEXT,
        cidade TEXT,
        uf TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clientes_nome ON clientes(nome)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clientes_doc ON clientes(cpf_cnpj)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS produtos (
        id INTEGER PRIMARY KEY,
        codigo TEXT,
        codigo_barras TEXT,
        codigo_barras_caixa TEXT,
        descricao TEXT NOT NULL,
        unidade TEXT,
        grupo TEXT,
        preco REAL NOT NULL DEFAULT 0,
        estoque REAL NOT NULL DEFAULT 0,
        estoque_reservado REAL NOT NULL DEFAULT 0,
        estoque_disponivel REAL NOT NULL DEFAULT 0,
        foto_url TEXT,
        is_servico INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_produtos_desc ON produtos(descricao)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_produtos_cod ON produtos(codigo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_produtos_grupo ON produtos(grupo)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_produtos_servico ON produtos(is_servico)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS grupos (
        nome TEXT PRIMARY KEY
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  /// Evita falha se a coluna já existir (upgrade repetido / schema misto).
  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => '${row['name']}' == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  String newLocalUuid() => _uuid.v4();

  Future<bool> catalogoSincronizado() async {
    final rows = await (await db).query(
      'sync_meta',
      where: "key = 'catalog_synced_at'",
      limit: 1,
    );
    return rows.isNotEmpty && '${rows.first['value'] ?? ''}'.isNotEmpty;
  }

  Future<void> marcarCatalogoSincronizado() async {
    await (await db).insert(
      'sync_meta',
      {'key': 'catalog_synced_at', 'value': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceCatalogo({
    required List<Map<String, dynamic>> clientes,
    required List<Map<String, dynamic>> produtos,
    required List<String> grupos,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('clientes');
      await txn.delete('produtos');
      await txn.delete('grupos');

      final batch = txn.batch();
      for (final c in clientes) {
        final id = c['id'];
        if (id == null) continue;
        batch.insert('clientes', {
          'id': id is int ? id : int.tryParse('$id'),
          'nome': '${c['nome'] ?? ''}',
          'fantasia': '${c['fantasia'] ?? ''}',
          'telefone': '${c['telefone'] ?? ''}',
          'email': '${c['email'] ?? ''}',
          'cpf_cnpj': '${c['cpf_cnpj'] ?? ''}',
          'cep': '${c['cep'] ?? ''}',
          'endereco': '${c['endereco'] ?? ''}',
          'endereco_completo': '${c['endereco_completo'] ?? c['endereco'] ?? ''}',
          'numero': '${c['numero'] ?? ''}',
          'bairro': '${c['bairro'] ?? ''}',
          'cidade': '${c['cidade'] ?? ''}',
          'uf': '${c['uf'] ?? ''}',
        });
      }
      for (final p in produtos) {
        final id = p['id'];
        if (id == null) continue;
        final estoque = _toDouble(p['estoque']);
        final reservado = _toDouble(p['estoque_reservado']);
        final disponivel = p.containsKey('estoque_disponivel') && p['estoque_disponivel'] != null
            ? _toDouble(p['estoque_disponivel'])
            : estoque - reservado;
        batch.insert('produtos', {
          'id': id is int ? id : int.tryParse('$id'),
          'codigo': '${p['codigo'] ?? ''}',
          'codigo_barras': '${p['codigo_barras'] ?? ''}',
          'codigo_barras_caixa': '${p['codigo_barras_caixa'] ?? ''}',
          'descricao': '${p['descricao'] ?? ''}',
          'unidade': '${p['unidade'] ?? 'UN'}',
          'grupo': '${p['grupo'] ?? ''}'.trim(),
          'preco': _toDouble(p['preco']),
          'estoque': estoque,
          'estoque_reservado': reservado,
          'estoque_disponivel': disponivel,
          'foto_url': '${p['foto_url'] ?? ''}'.trim(),
          'is_servico': (p['is_servico'] == true || p['is_servico'] == 1) ? 1 : 0,
        });
      }
      for (final g in grupos) {
        final nome = g.trim();
        if (nome.isEmpty) continue;
        batch.insert('grupos', {'nome': nome});
      }
      await batch.commit(noResult: true);
    });
    await marcarCatalogoSincronizado();
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? 0}') ?? 0;
  }

  Future<List<ClienteResumo>> buscarClientesLocal(String termo, {int limit = 40}) async {
    final q = termo.trim();
    final database = await db;
    List<Map<String, Object?>> rows;
    if (q.isEmpty) {
      rows = await database.query('clientes', orderBy: 'nome COLLATE NOCASE', limit: limit);
    } else {
      final like = '%$q%';
      final digits = q.replaceAll(RegExp(r'\D'), '');
      rows = await database.query(
        'clientes',
        where: digits.length >= 2
            ? '(nome LIKE ? OR fantasia LIKE ? OR telefone LIKE ? OR cpf_cnpj LIKE ? OR REPLACE(REPLACE(REPLACE(REPLACE(cpf_cnpj, ".", ""), "-", ""), "/", ""), " ", "") LIKE ?)'
            : '(nome LIKE ? OR fantasia LIKE ? OR telefone LIKE ? OR cpf_cnpj LIKE ?)',
        whereArgs: digits.length >= 2
            ? [like, like, like, like, '%$digits%']
            : [like, like, like, like],
        orderBy: 'nome COLLATE NOCASE',
        limit: limit,
      );
    }
    return rows.map(_clienteFromRow).toList();
  }

  ClienteResumo _clienteFromRow(Map<String, Object?> row) {
    return ClienteResumo(
      id: row['id'] is int ? row['id'] as int : int.parse('${row['id']}'),
      nome: '${row['nome'] ?? ''}',
      telefone: '${row['telefone'] ?? ''}',
      email: '${row['email'] ?? ''}',
      cpfCnpj: '${row['cpf_cnpj'] ?? ''}',
      cep: '${row['cep'] ?? ''}',
      endereco: '${row['endereco'] ?? ''}',
      enderecoCompleto: '${row['endereco_completo'] ?? row['endereco'] ?? ''}',
      numero: '${row['numero'] ?? ''}',
      bairro: '${row['bairro'] ?? ''}',
      cidade: '${row['cidade'] ?? ''}',
      uf: '${row['uf'] ?? ''}',
    );
  }

  Future<List<String>> listarGruposLocal() async {
    final rows = await (await db).query('grupos', orderBy: 'nome COLLATE NOCASE');
    return rows
        .map((r) => '${r['nome'] ?? ''}'.trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  Future<List<ProdutoResumo>> buscarProdutosLocal(
    String termo, {
    String tipo = 'produto',
    String? grupo,
    int limit = 100,
  }) async {
    final q = termo.trim();
    final g = (grupo ?? '').trim();
    final where = StringBuffer();
    final args = <Object?>[];

    if (tipo == 'servico') {
      where.write('is_servico = 1');
    } else if (tipo != 'todos') {
      where.write('(is_servico = 0 OR is_servico IS NULL)');
    } else {
      where.write('1=1');
    }

    if (g.isNotEmpty) {
      where.write(' AND grupo = ?');
      args.add(g);
    }

    if (q.isNotEmpty) {
      final like = '%$q%';
      where.write(
        ' AND (descricao LIKE ? OR codigo LIKE ? OR codigo_barras LIKE ? OR codigo_barras_caixa LIKE ?)',
      );
      args.addAll([like, like, like, like]);
    }

    final rows = await (await db).query(
      'produtos',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'descricao COLLATE NOCASE',
      limit: limit,
    );
    return rows.map(_produtoFromRow).toList();
  }

  ProdutoResumo _produtoFromRow(Map<String, Object?> row) {
    return ProdutoResumo(
      id: row['id'] is int ? row['id'] as int : int.parse('${row['id']}'),
      descricao: '${row['descricao'] ?? ''}',
      codigo: '${row['codigo'] ?? ''}',
      codigoBarras: '${row['codigo_barras'] ?? ''}',
      codigoBarrasCaixa: '${row['codigo_barras_caixa'] ?? ''}',
      unidade: '${row['unidade'] ?? 'UN'}',
      grupo: '${row['grupo'] ?? ''}'.trim(),
      preco: _toDouble(row['preco']),
      estoque: _toDouble(row['estoque']),
      estoqueReservado: _toDouble(row['estoque_reservado']),
      estoqueDisponivel: _toDouble(row['estoque_disponivel']),
      fotoUrl: '${row['foto_url'] ?? ''}'.trim(),
      isServico: (row['is_servico'] as int? ?? 0) == 1,
    );
  }

  Future<List<OrdemServico>> listOrdens() async {
    final rows = await (await db).query('ordens', orderBy: 'updated_at DESC');
    return rows.map(_fromRow).toList();
  }

  Future<OrdemServico?> getByKey(String key) async {
    if (key.startsWith('s:')) {
      final id = int.tryParse(key.substring(2));
      if (id == null) return null;
      final rows = await (await db).query(
        'ordens',
        where: 'server_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRow(rows.first);
    }
    if (key.startsWith('l:')) {
      final uuid = key.substring(2);
      final rows = await (await db).query(
        'ordens',
        where: 'local_uuid = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRow(rows.first);
    }
    // fallback server id numérico
    final id = int.tryParse(key);
    if (id != null) {
      final rows = await (await db).query(
        'ordens',
        where: 'server_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRow(rows.first);
    }
    return null;
  }

  Future<void> upsertFromServer(OrdemServico os) async {
    if (os.id == null) return;
    final database = await db;
    final existing = await database.query(
      'ordens',
      where: 'server_id = ?',
      whereArgs: [os.id],
      limit: 1,
    );

    if (existing.isNotEmpty && (existing.first['dirty'] as int? ?? 0) == 1) {
      // Não sobrescreve alteração local pendente.
      return;
    }

    if (existing.isEmpty && (os.localUuid == null || os.localUuid!.isEmpty)) {
      final criacaoPendente = await database.query(
        'sync_queue',
        columns: ['id'],
        where: "tipo = 'create'",
        limit: 1,
      );
      if (criacaoPendente.isNotEmpty) {
        return;
      }
    }

    final localUuid = existing.isNotEmpty
        ? '${existing.first['local_uuid']}'
        : (os.localUuid ?? newLocalUuid());

    await _substituirLinha(
      os.copyWith(localUuid: localUuid, dirty: false, pendingSync: false),
    );
  }

  Future<OrdemServico> saveLocal(OrdemServico os, {required String tipoFila}) async {
    final database = await db;
    final localUuid = os.localUuid ?? newLocalUuid();
    final saved = os.copyWith(
      localUuid: localUuid,
      dirty: true,
      pendingSync: true,
    );
    await database.insert(
      'ordens',
      _toRow(saved),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await database.insert('sync_queue', {
      'tipo': tipoFila,
      'local_uuid': localUuid,
      'payload_json': jsonEncode(saved.toJson()),
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    return saved;
  }

  Future<List<Map<String, dynamic>>> pendingQueue() async {
    return (await db).query('sync_queue', orderBy: 'id ASC');
  }

  Future<void> removeQueueItem(int id) async {
    await (await db).delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  /// Grava só o id e o número oficiais. Não troca o `local_uuid` nem apaga atendimento local.
  Future<void> vincularServidor({
    required String localUuid,
    required int serverId,
    required String numeroOficial,
    OrdemServico? fallback,
  }) async {
    final database = await db;
    final rows = await database.query(
      'ordens',
      where: 'local_uuid = ?',
      whereArgs: [localUuid],
      limit: 1,
    );
    if (rows.isEmpty) {
      if (fallback == null) return;
      await database.insert(
        'ordens',
        _toRow(fallback.copyWith(
          localUuid: localUuid,
          id: serverId,
          numero: numeroOficial,
          dirty: false,
          pendingSync: false,
        )),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    final atual = '${rows.first['numero'] ?? ''}';
    final historico = '${rows.first['numero_offline'] ?? ''}';
    final numeroOffline = historico.isNotEmpty
        ? historico
        : (atual.startsWith('OFF-') ? atual : null);

    await database.update(
      'ordens',
      {
        'server_id': serverId,
        'numero': numeroOficial,
        'numero_offline': ?numeroOffline,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'local_uuid = ?',
      whereArgs: [localUuid],
    );
  }

  Future<void> markSynced(String localUuid, OrdemServico serverOs) async {
    await _substituirLinha(
      serverOs.copyWith(
        localUuid: localUuid,
        dirty: false,
        pendingSync: false,
      ),
    );
  }

  /// Substitui a linha sem trocar `local_uuid` e sem apagar o OFF histórico.
  Future<void> _substituirLinha(OrdemServico os) async {
    final database = await db;
    final row = _toRow(os);
    final localUuid = '${row['local_uuid'] ?? ''}';
    if (localUuid.isNotEmpty && (row['numero_offline'] == null || '${row['numero_offline']}'.isEmpty)) {
      final existing = await database.query(
        'ordens',
        columns: ['numero_offline'],
        where: 'local_uuid = ?',
        whereArgs: [localUuid],
        limit: 1,
      );
      final kept = existing.isEmpty ? null : existing.first['numero_offline'];
      if (kept != null && '$kept'.isNotEmpty) {
        row['numero_offline'] = kept;
      }
    }
    await database.insert(
      'ordens',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Atualiza só o relato do técnico. Não regrava peças, serviços nem o restante da OS.
  Future<OrdemServico> gravarServicoRealizado(OrdemServico os, String texto) async {
    final database = await db;
    var localUuid = os.localUuid;
    if (localUuid == null || localUuid.isEmpty) {
      if (os.id != null) {
        final porServidor = await database.query(
          'ordens',
          columns: ['local_uuid'],
          where: 'server_id = ?',
          whereArgs: [os.id],
          limit: 1,
        );
        if (porServidor.isNotEmpty) {
          localUuid = '${porServidor.first['local_uuid']}';
        }
      }
      localUuid ??= newLocalUuid();
    }

    final existente = await database.query(
      'ordens',
      where: 'local_uuid = ?',
      whereArgs: [localUuid],
      limit: 1,
    );
    final agora = DateTime.now().toIso8601String();
    if (existente.isEmpty) {
      await database.insert(
        'ordens',
        _toRow(os.copyWith(
          localUuid: localUuid,
          servicoRealizado: texto,
          dirty: true,
          pendingSync: true,
        )),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await database.update(
        'ordens',
        {
          'servico_realizado': texto,
          'dirty': 1,
          'pending_sync': 1,
          'updated_at': agora,
        },
        where: 'local_uuid = ?',
        whereArgs: [localUuid],
      );
    }

    await _mesclarServicoRealizadoNaFila(localUuid, texto);
    return (await getByKey('l:$localUuid')) ??
        os.copyWith(
          localUuid: localUuid,
          servicoRealizado: texto,
          dirty: true,
          pendingSync: true,
        );
  }

  Future<void> _mesclarServicoRealizadoNaFila(
    String localUuid,
    String texto,
  ) async {
    final database = await db;
    final itens = await database.query(
      'sync_queue',
      where: 'local_uuid = ? AND tipo IN (?, ?)',
      whereArgs: [localUuid, 'create', 'update'],
    );

    var temUpdate = false;
    for (final item in itens) {
      if ('${item['tipo']}' == 'update') temUpdate = true;
      final raw = jsonDecode('${item['payload_json']}');
      if (raw is! Map) continue;
      raw['servico_realizado'] = texto;
      await database.update(
        'sync_queue',
        {'payload_json': jsonEncode(raw)},
        where: 'id = ?',
        whereArgs: [item['id']],
      );
    }

    if (temUpdate) return;

    // Só o relato. Peças e serviços ficam no payload que o atendimento já enfileirou.
    await database.insert('sync_queue', {
      'tipo': 'update',
      'local_uuid': localUuid,
      'payload_json': jsonEncode({
        'local_uuid': localUuid,
        'servico_realizado': texto,
      }),
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
  }

  Future<int> pendingCount() async {
    final r = await (await db).rawQuery('SELECT COUNT(*) AS c FROM sync_queue');
    return (r.first['c'] as int?) ?? 0;
  }

  OrdemServico _fromRow(Map<String, dynamic> row) {
    List<PecaOs> parseItens(dynamic raw) {
      if (raw is! String || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(PecaOs.fromJson)
          .where((e) => e.descricao.trim().isNotEmpty)
          .toList();
    }

    return OrdemServico(
      id: row['server_id'] as int?,
      localUuid: row['local_uuid']?.toString(),
      numero: '${row['numero'] ?? ''}',
      numeroOffline: row['numero_offline']?.toString(),
      cliente: '${row['cliente'] ?? ''}',
      telefone: '${row['telefone'] ?? ''}',
      endereco: '${row['endereco'] ?? ''}',
      equipamento: '${row['equipamento'] ?? ''}',
      problema: '${row['problema'] ?? ''}',
      servico: '${row['equipamento'] ?? ''}',
      status: '${row['status'] ?? ''}',
      dataHora: '${row['data_hora'] ?? ''}',
      tecnico: '${row['tecnico'] ?? ''}',
      servicoRealizado: '${row['servico_realizado'] ?? ''}',
      observacao: '${row['observacoes'] ?? ''}',
      pecas: parseItens(row['pecas_json']),
      servicos: parseItens(row['servicos_json']),
      horaInicio: row['hora_inicio']?.toString(),
      dirty: (row['dirty'] as int? ?? 0) == 1,
      pendingSync: (row['pending_sync'] as int? ?? 0) == 1,
    );
  }

  Map<String, Object?> _toRow(OrdemServico os) {
    return {
      'local_uuid': os.localUuid ?? newLocalUuid(),
      'server_id': os.id,
      'numero': os.numero,
      'numero_offline': os.numeroOffline,
      'cliente': os.cliente,
      'telefone': os.telefone,
      'endereco': os.endereco,
      'equipamento': os.equipamento,
      'problema': os.problema,
      'status': os.status,
      'data_hora': os.dataHora,
      'tecnico': os.tecnico,
      'servico_realizado': os.servicoRealizado,
      'observacoes': os.observacao,
      'pecas_json': jsonEncode(os.pecas.map((e) => e.toJson()).toList()),
      'servicos_json': jsonEncode(os.servicos.map((e) => e.toJson()).toList()),
      'hora_inicio': os.horaInicio,
      'dirty': os.dirty ? 1 : 0,
      'pending_sync': os.pendingSync ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
