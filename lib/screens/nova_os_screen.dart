import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unitec_os_app/screens/detalhe_os_screen.dart';
import 'package:unitec_os_app/services/api_client.dart';
import 'package:unitec_os_app/services/os_service.dart';
import 'package:unitec_os_app/theme/app_theme.dart';

class NovaOsScreen extends StatefulWidget {
  const NovaOsScreen({super.key});

  static const route = '/nova-os';

  @override
  State<NovaOsScreen> createState() => _NovaOsScreenState();
}

class _NovaOsScreenState extends State<NovaOsScreen> {
  final _osService = OsService();
  final _cliente = TextEditingController();
  final _fantasia = TextEditingController();
  final _cpfCnpj = TextEditingController();
  final _telefone = TextEditingController();
  final _email = TextEditingController();
  final _cep = TextEditingController();
  final _endereco = TextEditingController();
  final _numero = TextEditingController();
  final _bairro = TextEditingController();
  final _cidade = TextEditingController();
  final _uf = TextEditingController();
  final _equipamento = TextEditingController();
  final _problema = TextEditingController();

  final _clienteFocus = FocusNode();
  final _cpfCnpjFocus = FocusNode();
  final _cepFocus = FocusNode();
  final _numeroFocus = FocusNode();

  int? _clienteId;
  List<ClienteResumo> _sugestoes = [];
  bool _buscando = false;
  bool _buscandoCnpj = false;
  bool _buscandoCep = false;
  bool _salvando = false;
  bool _preenchendoAuto = false;
  bool _enderecoViaCnpj = false;
  String? _ultimoCnpjConsultado;
  String? _ultimoCepConsultado;
  final Set<String> _tocado = {};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _cliente.addListener(_onClienteChanged);
    _cpfCnpjFocus.addListener(_onCpfCnpjFocusChanged);
    _cepFocus.addListener(_onCepFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cliente.removeListener(_onClienteChanged);
    _cpfCnpjFocus.removeListener(_onCpfCnpjFocusChanged);
    _cepFocus.removeListener(_onCepFocusChanged);
    _cliente.dispose();
    _fantasia.dispose();
    _cpfCnpj.dispose();
    _telefone.dispose();
    _email.dispose();
    _cep.dispose();
    _endereco.dispose();
    _numero.dispose();
    _bairro.dispose();
    _cidade.dispose();
    _uf.dispose();
    _equipamento.dispose();
    _problema.dispose();
    _clienteFocus.dispose();
    _cpfCnpjFocus.dispose();
    _cepFocus.dispose();
    _numeroFocus.dispose();
    super.dispose();
  }

  String _somenteDigitos(String v) => v.replaceAll(RegExp(r'\D'), '');

  bool _semConexao(Object e) {
    if (e is ApiException && e.isOffline) return true;
    final msg = e is ApiException ? e.message.toLowerCase() : e.toString().toLowerCase();
    return msg.contains('sem conexão') ||
        msg.contains('socket') ||
        msg.contains('host inacess') ||
        msg.contains('tls/ssl') ||
        msg.contains('tempo esgotado') ||
        msg.contains('network');
  }

  void _marcarTocado(String campo) {
    if (_preenchendoAuto) return;
    _tocado.add(campo);
  }

  void _setAuto(TextEditingController controller, String campo, String valor) {
    final v = valor.trim();
    if (v.isEmpty) return;
    if (_tocado.contains(campo)) return;
    _preenchendoAuto = true;
    controller.text = v;
    _preenchendoAuto = false;
  }

  void _focarNumero() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _numeroFocus.requestFocus();
    });
  }

  void _onClienteChanged() {
    if (_clienteId != null) {
      final selecionado = _sugestoes.where((c) => c.id == _clienteId).toList();
      if (selecionado.isEmpty ||
          selecionado.first.nome.toUpperCase() !=
              _cliente.text.trim().toUpperCase()) {
        _clienteId = null;
      }
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _buscarClientes);
  }

  void _onCpfCnpjFocusChanged() {
    if (!_cpfCnpjFocus.hasFocus) {
      unawaited(_aoDocumentoPronto());
    }
  }

  void _onCepFocusChanged() {
    if (!_cepFocus.hasFocus) {
      unawaited(_aoCepPronto());
    }
  }

  Future<void> _buscarClientes() async {
    final termo = _cliente.text.trim();
    if (termo.length < 2) {
      setState(() => _sugestoes = []);
      return;
    }

    setState(() => _buscando = true);
    try {
      final lista = await _osService.buscarClientes(termo);
      if (!mounted) return;
      setState(() {
        _sugestoes = lista;
        _buscando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sugestoes = [];
        _buscando = false;
      });
    }
  }

  Future<void> _aoDocumentoPronto() async {
    final digits = _somenteDigitos(_cpfCnpj.text);
    if (digits.length == 11 || digits.length == 14) {
      try {
        final lista = await _osService.buscarClientes(digits);
        if (!mounted) return;
        final match = lista.where((c) {
          return _somenteDigitos(c.cpfCnpj) == digits;
        }).toList();
        if (match.isNotEmpty) {
          _selecionarCliente(match.first);
          return;
        }
      } catch (_) {}
    }

    if (digits.length == 14) {
      await _consultarCnpj(digits);
    }
  }

  Future<void> _consultarCnpj(String digits) async {
    if (_buscandoCnpj || digits == _ultimoCnpjConsultado) return;
    setState(() => _buscandoCnpj = true);
    try {
      final data = await _osService.consultarCnpj(digits);
      if (!mounted) return;
      _ultimoCnpjConsultado = digits;

      final razao = (data['nome_razao'] ?? '').trim();
      final fantasia = (data['apelido_fantasia'] ?? '').trim();
      final fone = (data['fone1'] ?? data['fone2'] ?? '').trim();
      final email = (data['email'] ?? '').trim();
      final cep = (data['cep'] ?? '').trim();
      final end = (data['endereco'] ?? '').trim();
      final num = (data['numero'] ?? '').trim();
      final bairro = (data['bairro'] ?? '').trim();
      final cidade = (data['cidade_nome'] ?? '').trim();
      final uf = (data['uf'] ?? '').trim();

      setState(() {
        _setAuto(_cliente, 'cliente', razao.toUpperCase());
        if (razao.isNotEmpty) _clienteId = null;
        _setAuto(_fantasia, 'fantasia', fantasia.toUpperCase());
        _setAuto(_telefone, 'telefone', fone);
        _setAuto(_email, 'email', email);
        if (cep.isNotEmpty) {
          _setAuto(_cep, 'cep', cep);
          _ultimoCepConsultado = _somenteDigitos(cep);
        }
        _setAuto(_endereco, 'endereco', end.toUpperCase());
        _setAuto(_numero, 'numero', num);
        _setAuto(_bairro, 'bairro', bairro.toUpperCase());
        _setAuto(_cidade, 'cidade', cidade.toUpperCase());
        _setAuto(_uf, 'uf', uf.toUpperCase());
        _enderecoViaCnpj = end.isNotEmpty ||
            bairro.isNotEmpty ||
            cidade.isNotEmpty ||
            uf.isNotEmpty;
        _sugestoes = [];
        _buscandoCnpj = false;
      });

      _toast('Cadastro do CNPJ preenchido automaticamente.');
      if (_enderecoViaCnpj || cep.isNotEmpty) {
        _focarNumero();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _buscandoCnpj = false);
      if (_semConexao(e)) {
        _toast('Sem conexão. Preencha o cadastro manualmente.');
      } else {
        _toast(e.message.trim().isEmpty ? 'CNPJ não encontrado.' : e.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _buscandoCnpj = false);
      _toast(_semConexao(e)
          ? 'Sem conexão. Preencha o cadastro manualmente.'
          : 'Não foi possível consultar o CNPJ.');
    }
  }

  Future<void> _aoCepPronto() async {
    final digits = _somenteDigitos(_cep.text);
    if (digits.length != 8 || digits == _ultimoCepConsultado || _buscandoCep) {
      return;
    }

    setState(() => _buscandoCep = true);
    try {
      final data = await _osService.consultarCep(digits);
      if (!mounted) return;
      _ultimoCepConsultado = digits;
      setState(() {
        _setAuto(_endereco, 'endereco', (data['endereco'] ?? '').trim());
        _setAuto(_bairro, 'bairro', (data['bairro'] ?? '').trim());
        _setAuto(_cidade, 'cidade', (data['cidade_nome'] ?? '').trim());
        _setAuto(_uf, 'uf', (data['uf'] ?? '').trim());
        final cepFmt = (data['cep'] ?? '').trim();
        if (cepFmt.isNotEmpty && !_tocado.contains('cep')) {
          _preenchendoAuto = true;
          _cep.text = cepFmt;
          _preenchendoAuto = false;
        }
        _buscandoCep = false;
      });
      _focarNumero();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _buscandoCep = false);
      if (_semConexao(e)) {
        _toast('Sem conexão. Preencha o endereço manualmente.');
      } else {
        _toast(e.message.trim().isEmpty ? 'CEP não encontrado.' : e.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _buscandoCep = false);
      if (_semConexao(e)) {
        _toast('Sem conexão. Preencha o endereço manualmente.');
      }
    }
  }

  void _selecionarCliente(ClienteResumo c) {
    setState(() {
      _preenchendoAuto = true;
      _clienteId = c.id;
      _cliente.text = c.nome;
      if (c.cpfCnpj.isNotEmpty) {
        _cpfCnpj.text = c.cpfCnpj;
        _ultimoCnpjConsultado = _somenteDigitos(c.cpfCnpj);
      }
      if (c.telefone.isNotEmpty) _telefone.text = c.telefone;
      if (c.email.isNotEmpty) _email.text = c.email;
      if (c.cep.isNotEmpty) {
        _cep.text = c.cep;
        _ultimoCepConsultado = _somenteDigitos(c.cep);
      }
      if (c.endereco.isNotEmpty) _endereco.text = c.endereco;
      if (c.numero.isNotEmpty) _numero.text = c.numero;
      if (c.bairro.isNotEmpty) _bairro.text = c.bairro;
      if (c.cidade.isNotEmpty) _cidade.text = c.cidade;
      if (c.uf.isNotEmpty) _uf.text = c.uf;
      _sugestoes = [];
      _enderecoViaCnpj = false;
      _preenchendoAuto = false;
    });
    _clienteFocus.unfocus();
  }

  Future<void> _salvar() async {
    final nome = _cliente.text.trim();
    if (nome.isEmpty) {
      _toast('Informe o cliente.');
      return;
    }

    final docDigits = _somenteDigitos(_cpfCnpj.text);
    if (docDigits.isNotEmpty && docDigits.length != 11 && docDigits.length != 14) {
      _toast('CPF/CNPJ incompleto.');
      return;
    }

    setState(() => _salvando = true);
    try {
      final result = await _osService.criarOs(
        clienteId: _clienteId,
        cliente: nome,
        nomeFantasia: _fantasia.text,
        telefone: _telefone.text,
        email: _email.text,
        cpfCnpj: _cpfCnpj.text,
        cep: _cep.text,
        endereco: _endereco.text,
        numero: _numero.text,
        bairro: _bairro.text,
        cidade: _cidade.text,
        uf: _uf.text,
        equipamento: _equipamento.text,
        problema: _problema.text,
      );
      if (!mounted) return;

      final msg = result.offline
          ? 'OS ${result.os.numero} salva offline (sincroniza depois).'
          : (result.clienteCriado
              ? 'OS ${result.os.numero} criada. Cliente novo cadastrado.'
              : 'OS ${result.os.numero} criada.');
      _toast(msg);

      Navigator.of(context).pushReplacementNamed(
        DetalheOsScreen.route,
        arguments: result.os.key,
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Falha ao salvar a OS.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required String campoKey,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    int? maxLength,
    Widget? suffix,
    TextCapitalization textCapitalization = TextCapitalization.none,
    VoidCallback? onEditingComplete,
    ValueChanged<String>? onChanged,
    TextInputAction? textInputAction,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: !_salvando,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction ?? TextInputAction.next,
      onChanged: (v) {
        _marcarTocado(campoKey);
        onChanged?.call(v);
      },
      onEditingComplete: onEditingComplete,
      onSubmitted: (_) => onEditingComplete?.call(),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        suffixIcon: suffix,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova OS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Busque o cliente ou informe o CNPJ para preencher o cadastro automaticamente. '
            'Se não existir, ao salvar a OS o cliente é cadastrado.',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _campo(
            controller: _cpfCnpj,
            label: 'CPF ou CNPJ',
            campoKey: 'cpfCnpj',
            focusNode: _cpfCnpjFocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(14),
            ],
            onEditingComplete: () {
              _cpfCnpjFocus.unfocus();
              unawaited(_aoDocumentoPronto());
            },
            suffix: _buscandoCnpj
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.badge_outlined),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cliente,
            focusNode: _clienteFocus,
            enabled: !_salvando,
            onChanged: (_) => _marcarTocado('cliente'),
            decoration: InputDecoration(
              labelText: 'Razão Social / Cliente',
              suffixIcon: _buscando
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.search),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          if (_sugestoes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Card(
              child: Column(
                children: _sugestoes.map((c) {
                  return ListTile(
                    dense: true,
                    title: Text(
                      c.nome,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        if (c.cpfCnpj.isNotEmpty) c.cpfCnpj,
                        if (c.telefone.isNotEmpty) c.telefone,
                        if (c.enderecoCompleto.isNotEmpty) c.enderecoCompleto,
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selecionarCliente(c),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _campo(
            controller: _fantasia,
            label: 'Nome Fantasia',
            campoKey: 'fantasia',
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          _campo(
            controller: _telefone,
            label: 'Telefone',
            campoKey: 'telefone',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          _campo(
            controller: _email,
            label: 'E-mail',
            campoKey: 'email',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _campo(
            controller: _cep,
            label: 'CEP',
            campoKey: 'cep',
            focusNode: _cepFocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            onEditingComplete: () {
              _cepFocus.unfocus();
              unawaited(_aoCepPronto());
            },
            onChanged: (_) {
              // CEP alterado manualmente: libera nova consulta e não bloqueia por CNPJ.
              if (!_preenchendoAuto) {
                _enderecoViaCnpj = false;
              }
            },
            suffix: _buscandoCep
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.location_on_outlined),
          ),
          const SizedBox(height: 12),
          _campo(
            controller: _endereco,
            label: 'Endereço',
            campoKey: 'endereco',
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _campo(
                  controller: _numero,
                  label: 'Número',
                  campoKey: 'numero',
                  focusNode: _numeroFocus,
                  keyboardType: TextInputType.text,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: _campo(
                  controller: _bairro,
                  label: 'Bairro',
                  campoKey: 'bairro',
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _campo(
                  controller: _cidade,
                  label: 'Cidade',
                  campoKey: 'cidade',
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _campo(
                  controller: _uf,
                  label: 'UF',
                  campoKey: 'uf',
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                    LengthLimitingTextInputFormatter(2),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _campo(
            controller: _equipamento,
            label: 'Equipamento',
            campoKey: 'equipamento',
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          _campo(
            controller: _problema,
            label: 'Problema informado',
            campoKey: 'problema',
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _salvando ? null : _salvar,
            child: _salvando
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Salvar OS'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _salvando ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}
