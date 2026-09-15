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
