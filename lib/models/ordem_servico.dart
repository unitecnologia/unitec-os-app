import 'package:unitec_os_app/models/peca_os.dart';

class OrdemServico {
  const OrdemServico({
    this.id,
    this.localUuid,
    required this.numero,
    required this.cliente,
    required this.telefone,
    required this.endereco,
    required this.equipamento,
    required this.problema,
    required this.servico,
    required this.status,
    required this.dataHora,
    this.tecnico = '',
    this.servicoRealizado = '',
    this.pecas = const [],
    this.servicos = const [],
    this.observacao = '',
    this.horaInicio,
    this.numeroOffline,
    this.dirty = false,
    this.pendingSync = false,
  });

  final int? id;
  final String? localUuid;
  final String numero;
  /// Número provisório OFF-xxxx. Não é o número oficial depois da sincronização.
  final String? numeroOffline;
  final String cliente;
  final String telefone;
  final String endereco;
  final String equipamento;
  final String problema;
  final String servico;
  final String status;
  final String dataHora;
  final String tecnico;
  final String servicoRealizado;
  final List<PecaOs> pecas;
  final List<PecaOs> servicos;
  final String observacao;
  final String? horaInicio;
  final bool dirty;
  final bool pendingSync;

  String get key => id != null ? 's:$id' : 'l:${localUuid ?? numero}';

  /// Depois do vínculo com o ERP, [numero] já é o `numero_os` oficial.
  String get numeroExibicao => numero;

  OrdemServico copyWith({
    int? id,
    String? localUuid,
    String? numero,
    String? cliente,
    String? telefone,
    String? endereco,
    String? equipamento,
    String? problema,
    String? servico,
    String? status,
    String? dataHora,
    String? tecnico,
    String? servicoRealizado,
    List<PecaOs>? pecas,
    List<PecaOs>? servicos,
    String? observacao,
    String? horaInicio,
    String? numeroOffline,
    bool? dirty,
    bool? pendingSync,
  }) {
    return OrdemServico(
      id: id ?? this.id,
      localUuid: localUuid ?? this.localUuid,
      numero: numero ?? this.numero,
      numeroOffline: numeroOffline ?? this.numeroOffline,
      cliente: cliente ?? this.cliente,
      telefone: telefone ?? this.telefone,
      endereco: endereco ?? this.endereco,
      equipamento: equipamento ?? this.equipamento,
      problema: problema ?? this.problema,
      servico: servico ?? this.servico,
      status: status ?? this.status,
      dataHora: dataHora ?? this.dataHora,
      tecnico: tecnico ?? this.tecnico,
      servicoRealizado: servicoRealizado ?? this.servicoRealizado,
      pecas: pecas ?? this.pecas,
      servicos: servicos ?? this.servicos,
      observacao: observacao ?? this.observacao,
      horaInicio: horaInicio ?? this.horaInicio,
      dirty: dirty ?? this.dirty,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  static List<PecaOs> _parseItens(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map(PecaOs.fromJson)
        .where((e) => e.descricao.trim().isNotEmpty)
        .toList();
  }

  factory OrdemServico.fromJson(Map<String, dynamic> json) {
    return OrdemServico(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id'] ?? ''}'),
      localUuid: json['local_uuid']?.toString(),
      numero: '${json['numero_os'] ?? json['numero'] ?? ''}',
      cliente: '${json['cliente'] ?? ''}',
      telefone: '${json['telefone'] ?? ''}',
      endereco: '${json['endereco'] ?? ''}',
      equipamento: '${json['equipamento'] ?? ''}',
      problema: '${json['problema'] ?? ''}',
      servico: '${json['equipamento'] ?? json['servico'] ?? ''}',
      status: '${json['status'] ?? ''}',
      dataHora: '${json['data_hora'] ?? ''}',
      tecnico: '${json['tecnico'] ?? ''}',
      servicoRealizado: '${json['servico_realizado'] ?? ''}',
      pecas: _parseItens(json['pecas']),
      servicos: _parseItens(json['servicos']),
      observacao: '${json['observacoes'] ?? json['observacao'] ?? ''}',
      horaInicio: json['hora_inicio']?.toString(),
      dirty: json['dirty'] == true || json['dirty'] == 1,
      pendingSync: json['pending_sync'] == true || json['pending_sync'] == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'local_uuid': localUuid,
        'numero_os': numero,
        'cliente': cliente,
        'telefone': telefone,
        'endereco': endereco,
        'equipamento': equipamento,
        'problema': problema,
        'status': status,
        'data_hora': dataHora,
        'tecnico': tecnico,
        'servico_realizado': servicoRealizado,
        'observacoes': observacao,
        'pecas': pecas.map((e) => e.toJson()).toList(),
        'servicos': servicos.map((e) => e.toJson()).toList(),
        'hora_inicio': horaInicio,
      };
}
