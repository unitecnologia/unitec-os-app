import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:unitec_os_app/models/ordem_servico.dart';
import 'package:unitec_os_app/models/peca_os.dart';
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
      version: 4,
      onCreate: (db, version) async {
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
      },
    );
    return _db!;
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
