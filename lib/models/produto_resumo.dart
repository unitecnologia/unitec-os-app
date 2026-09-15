class ProdutoResumo {
  const ProdutoResumo({
    required this.id,
    required this.descricao,
    this.codigo = '',
    this.codigoBarras = '',
    this.codigoBarrasCaixa = '',
    this.imei = '',
    this.numeroSerie = '',
    this.unidade = 'UN',
    this.grupo = '',
    this.preco = 0,
    this.estoque = 0,
    this.estoqueReservado = 0,
    this.estoqueDisponivel = 0,
    this.fotoUrl = '',
    this.isServico = false,
  });

  final int id;
  final String descricao;
  final String codigo;
  final String codigoBarras;
  final String codigoBarrasCaixa;
  final String imei;
  final String numeroSerie;
  final String unidade;
  final String grupo;
  final double preco;
  final double estoque;
  final double estoqueReservado;
  final double estoqueDisponivel;
  final String fotoUrl;
  final bool isServico;

  bool correspondeCodigo(String codigo) {
    final alvo = codigo.trim();
    if (alvo.isEmpty) return false;
    return this.codigo.trim() == alvo ||
        codigoBarras.trim() == alvo ||
        codigoBarrasCaixa.trim() == alvo ||
        imei.trim() == alvo ||
        numeroSerie.trim() == alvo;
  }

  factory ProdutoResumo.fromJson(Map<String, dynamic> json) {
    final estoque = _num(json['estoque']);
    final reservado = _num(json['estoque_reservado']);
    final disponivel = json.containsKey('estoque_disponivel') && json['estoque_disponivel'] != null
        ? _num(json['estoque_disponivel'])
        : estoque - reservado;

    return ProdutoResumo(
      id: json['id'] is int ? json['id'] as int : int.parse('${json['id']}'),
      descricao: '${json['descricao'] ?? ''}',
      codigo: '${json['codigo'] ?? ''}',
      codigoBarras: '${json['codigo_barras'] ?? ''}',
      codigoBarrasCaixa: '${json['codigo_barras_caixa'] ?? ''}',
      imei: '${json['imei'] ?? ''}',
      numeroSerie: '${json['numero_serie'] ?? ''}',
      unidade: '${json['unidade'] ?? 'UN'}',
      grupo: '${json['grupo'] ?? ''}'.trim(),
      preco: _num(json['preco']),
      estoque: estoque,
      estoqueReservado: reservado,
      estoqueDisponivel: disponivel,
      fotoUrl: '${json['foto_url'] ?? ''}'.trim(),
      isServico: json['is_servico'] == true || json['is_servico'] == 1,
    );
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? 0}') ?? 0;
  }
}
