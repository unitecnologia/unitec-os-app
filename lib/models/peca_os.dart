class PecaOs {
  const PecaOs({
    this.produtoId,
    this.codigo = '',
    this.codigoBarras = '',
    this.imei = '',
    required this.descricao,
    this.preco = 0,
    this.qtd = 1,
  });

  final int? produtoId;
  final String codigo;
  final String codigoBarras;
  final String imei;
  final String descricao;
  final double preco;
  final double qtd;

  String get label {
    if (codigo.isNotEmpty) return '$codigo — $descricao';
    return descricao;
  }

  PecaOs copyWith({
    int? produtoId,
    String? codigo,
    String? codigoBarras,
    String? imei,
    String? descricao,
    double? preco,
    double? qtd,
  }) {
    return PecaOs(
      produtoId: produtoId ?? this.produtoId,
      codigo: codigo ?? this.codigo,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      imei: imei ?? this.imei,
      descricao: descricao ?? this.descricao,
      preco: preco ?? this.preco,
      qtd: qtd ?? this.qtd,
    );
  }

  factory PecaOs.fromJson(dynamic raw) {
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      final id = m['produto_id'] ?? m['id'];
      return PecaOs(
        produtoId: id is int ? id : int.tryParse('${id ?? ''}'),
        codigo: '${m['codigo'] ?? ''}',
        codigoBarras: '${m['codigo_barras'] ?? ''}',
        imei: '${m['imei'] ?? ''}',
        descricao: '${m['descricao'] ?? m['nome'] ?? ''}'.trim(),
        preco: m['preco'] is num
            ? (m['preco'] as num).toDouble()
            : double.tryParse('${m['preco'] ?? 0}') ?? 0,
        qtd: m['qtd'] is num
            ? (m['qtd'] as num).toDouble()
            : double.tryParse('${m['qtd'] ?? 1}') ?? 1,
      );
    }
    return PecaOs(descricao: '$raw'.trim());
  }

  Map<String, dynamic> toJson() => {
        if (produtoId != null) 'produto_id': produtoId,
        if (codigo.isNotEmpty) 'codigo': codigo,
        if (codigoBarras.isNotEmpty) 'codigo_barras': codigoBarras,
        if (imei.isNotEmpty) 'imei': imei,
        'descricao': descricao,
        'preco': preco,
        'qtd': qtd,
      };
}
