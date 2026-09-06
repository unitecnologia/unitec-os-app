import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unitec_os_app/models/ordem_servico.dart';
import 'package:unitec_os_app/models/peca_os.dart';
import 'package:unitec_os_app/services/api_client.dart';
import 'package:unitec_os_app/services/os_service.dart';
import 'package:unitec_os_app/theme/app_theme.dart';

class DetalheOsScreen extends StatefulWidget {
  const DetalheOsScreen({super.key, required this.osKey});

  static const route = '/detalhe-os';

  final String osKey;

  @override
  State<DetalheOsScreen> createState() => _DetalheOsScreenState();
}

class _DetalheOsScreenState extends State<DetalheOsScreen> {
  final _osService = OsService();
  final _servicoRealizado = TextEditingController();
  final _observacoes = TextEditingController();

  OrdemServico? _os;
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  late String _status;
  String? _inicioAtendimento;
  final List<PecaOs> _pecas = [];
  final List<PecaOs> _servicos = [];
  int _fotosMock = 0;
  bool _assinaturaColetada = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _servicoRealizado.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final os = await _osService.obterPorKey(widget.osKey);
      if (!mounted) return;
      if (os == null) {
        setState(() {
          _erro = 'OS não encontrada.';
          _carregando = false;
        });
        return;
      }
      setState(() {
        _os = os;
        _status = os.status;
        _inicioAtendimento = os.horaInicio;
        if (_inicioAtendimento == null || _inicioAtendimento!.isEmpty) {
          if (_status == 'Em andamento' || _status == 'Finalizada') {
            final partes = os.dataHora.split(' ');
            _inicioAtendimento = partes.length > 1 ? partes.last : null;
          }
        }
        _servicoRealizado.text = os.servicoRealizado;
        _observacoes.text = os.observacao;
        _pecas
          ..clear()
          ..addAll(os.pecas);
        _servicos
          ..clear()
          ..addAll(os.servicos);
        _carregando = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.message;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Falha ao carregar a OS.';
        _carregando = false;
      });
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'Pendente':
        return const Color(0xFFB45309);
      case 'Em andamento':
        return AppTheme.primaryBlue;
      case 'Finalizada':
        return const Color(0xFF15803D);
      default:
        return AppTheme.muted;
    }
  }

  Future<void> _iniciarAtendimento() async {
    if (_os == null || _salvando) return;
    setState(() => _salvando = true);
    try {
      final updated = await _osService.atualizarAtendimento(
        os: _os!,
        iniciar: true,
      );
      if (!mounted) return;
      setState(() {
        _os = updated;
        _status = updated.status;
        _inicioAtendimento = updated.horaInicio;
        _salvando = false;
      });
      _toast(updated.pendingSync
          ? 'Atendimento iniciado (será sincronizado).'
          : 'Atendimento iniciado.');
    } on ApiException catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _salvando = false);
    } catch (_) {
      _toast('Falha ao iniciar atendimento.');
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _salvar({bool finalizar = false}) async {
    if (_os == null || _salvando) return;
    setState(() => _salvando = true);
    try {
      final updated = await _osService.atualizarAtendimento(
        os: _os!,
        servicoRealizado: _servicoRealizado.text.trim(),
        observacoes: _observacoes.text.trim(),
        pecas: List<PecaOs>.from(_pecas),
        servicos: List<PecaOs>.from(_servicos),
        finalizar: finalizar,
      );
      if (!mounted) return;
      final msg = finalizar
          ? (updated.pendingSync
              ? 'OS finalizada (aguardando sync).'
              : 'OS finalizada.')
          : (updated.pendingSync
              ? 'Salvo localmente (aguardando sync).'
              : 'OS salva.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _salvando = false);
    } catch (_) {
      _toast('Falha ao salvar.');
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _adicionarPeca() async {
    final selecionado = await showDialog<ProdutoResumo>(
      context: context,
      builder: (ctx) => const _BuscarCatalogoDialog(
        titulo: 'Adicionar peça / produto',
        tipo: 'produto',
      ),
    );
    if (selecionado == null) return;
    setState(() {
      _pecas.add(
        PecaOs(
          produtoId: selecionado.id,
          codigo: selecionado.codigo,
          descricao: selecionado.descricao,
          preco: selecionado.preco,
        ),
      );
    });
  }

  Future<void> _adicionarServico() async {
    final selecionado = await showDialog<ProdutoResumo>(
      context: context,
      builder: (ctx) => const _BuscarCatalogoDialog(
        titulo: 'Adicionar serviço',
        tipo: 'servico',
      ),
    );
    if (selecionado == null || !mounted) return;

    final preco = await showDialog<double>(
      context: context,
      builder: (ctx) => _ValorServicoDialog(
        titulo: 'Valor do serviço',
        descricao: selecionado.descricao,
        codigo: selecionado.codigo,
        valorInicial: selecionado.preco,
        confirmarLabel: 'Adicionar',
      ),
    );
    if (preco == null || !mounted) return;

    setState(() {
      _servicos.add(
        PecaOs(
          produtoId: selecionado.id,
          codigo: selecionado.codigo,
          descricao: selecionado.descricao,
          preco: preco,
        ),
      );
    });
  }

  Future<void> _editarValorServico(int index) async {
    final atual = _servicos[index];
    final preco = await showDialog<double>(
      context: context,
      builder: (ctx) => _ValorServicoDialog(
        titulo: 'Alterar valor',
        descricao: atual.descricao,
        codigo: atual.codigo,
        valorInicial: atual.preco,
        confirmarLabel: 'Salvar',
      ),
    );
    if (preco == null || !mounted) return;
    setState(() => _servicos[index] = atual.copyWith(preco: preco));
  }

  String _fmtMoney(double v) {
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        appBar: AppBar(title: const Text('OS')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_erro != null || _os == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('OS')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_erro ?? 'OS não encontrada.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _carregar,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final os = _os!;
    final corStatus = _corStatus(_status);
    final finalizada = _status == 'Finalizada';

    return Scaffold(
      appBar: AppBar(
        title: Text('OS ${os.numero}'),
        actions: [
          if (os.pendingSync)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.cloud_upload_outlined, color: Color(0xFFFFF7ED)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'OS ${os.numero}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.text,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: corStatus.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _status,
                                style: TextStyle(
                                  color: corStatus,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (os.tecnico.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _Campo(label: 'Técnico', valor: os.tecnico),
                        ],
                        const SizedBox(height: 12),
                        _Campo(label: 'Cliente', valor: os.cliente),
                        const SizedBox(height: 10),
                        _CampoComAcao(
                          label: 'Telefone',
                          valor: os.telefone.isEmpty ? '—' : os.telefone,
                          icone: Icons.phone,
                          acaoLabel: 'Ligar',
                          onPressed: () => _toast('Ligar (mock).'),
                        ),
                        const SizedBox(height: 10),
                        _CampoComAcao(
                          label: 'Endereço',
                          valor: os.endereco.isEmpty ? '—' : os.endereco,
                          icone: Icons.map_outlined,
                          acaoLabel: 'Mapa',
                          onPressed: () => _toast('Mapa (mock).'),
                        ),
                        const SizedBox(height: 10),
                        _Campo(
                          label: 'Equipamento',
                          valor: os.equipamento.isEmpty ? '—' : os.equipamento,
                        ),
                        const SizedBox(height: 10),
                        _Campo(
                          label: 'Problema informado',
                          valor: os.problema.isEmpty ? '—' : os.problema,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _Bloco(
                  titulo: 'Atendimento',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_inicioAtendimento == null || _inicioAtendimento!.isEmpty)
                        ElevatedButton.icon(
                          onPressed: (_salvando || finalizada) ? null : _iniciarAtendimento,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Iniciar atendimento'),
                        )
                      else ...[
                        Text(
                          'Início: $_inicioAtendimento',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          finalizada
                              ? 'Atendimento finalizado.'
                              : 'Atendimento em andamento.',
                          style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _Bloco(
                  titulo: 'Serviço realizado',
                  child: TextField(
                    controller: _servicoRealizado,
                    maxLines: 3,
                    enabled: !finalizada && !_salvando,
                    decoration: const InputDecoration(
                      hintText: 'Descreva o serviço realizado',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _Bloco(
                  titulo: 'Serviços',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (finalizada || _salvando) ? null : _adicionarServico,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar do cadastro'),
                      ),
                      const SizedBox(height: 8),
                      if (_servicos.isEmpty)
                        const Text(
                          'Nenhum serviço do ERP adicionado.',
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        )
                      else
                        ..._servicos.asMap().entries.map((e) {
                          final item = e.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.build_outlined,
                                  size: 18,
                                  color: AppTheme.muted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (item.codigo.isNotEmpty)
                                        Text(
                                          item.codigo,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.muted,
                                          ),
                                        ),
                                      Text(
                                        item.descricao,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: (finalizada || _salvando)
                                            ? null
                                            : () => _editarValorServico(e.key),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          foregroundColor: AppTheme.primaryBlue,
                                        ),
                                        child: Text(
                                          _fmtMoney(item.preco),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!finalizada)
                                  IconButton(
                                    tooltip: 'Remover',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _salvando
                                        ? null
                                        : () {
                                            setState(() => _servicos.removeAt(e.key));
                                          },
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _Bloco(
                  titulo: 'Peças / Produtos',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (finalizada || _salvando) ? null : _adicionarPeca,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar do cadastro'),
                      ),
                      const SizedBox(height: 8),
                      if (_pecas.isEmpty)
                        const Text(
                          'Nenhum produto do ERP adicionado.',
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        )
                      else
                        ..._pecas.asMap().entries.map((e) {
                          final peca = e.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 18,
                                  color: AppTheme.muted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (peca.codigo.isNotEmpty)
                                        Text(
                                          peca.codigo,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.muted,
                                          ),
                                        ),
                                      Text(
                                        peca.descricao,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!finalizada)
                                  IconButton(
                                    tooltip: 'Remover',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _salvando
                                        ? null
                                        : () {
                                            setState(() => _pecas.removeAt(e.key));
                                          },
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _Bloco(
                  titulo: 'Observações',
                  child: TextField(
                    controller: _observacoes,
                    maxLines: 3,
                    enabled: !finalizada && !_salvando,
                    decoration: const InputDecoration(
                      hintText: 'Observações do atendimento',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _Bloco(
                  titulo: 'Fotos',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (finalizada || _salvando)
                            ? null
                            : () {
                                setState(() => _fotosMock++);
                                _toast('Foto adicionada (mock).');
                              },
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('+ Adicionar foto'),
                      ),
                      if (_fotosMock > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '$_fotosMock foto(s) (visual mock)',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _Bloco(
                  titulo: 'Assinatura',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (finalizada || _salvando)
                            ? null
                            : () {
                                setState(() => _assinaturaColetada = true);
                                _toast('Assinatura coletada (mock).');
                              },
                        icon: const Icon(Icons.draw_outlined),
                        label: const Text('Coletar assinatura'),
                      ),
                      if (_assinaturaColetada) ...[
                        const SizedBox(height: 8),
                        Container(
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Text(
                            'Assinatura coletada (mock)',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (_salvando || finalizada) ? null : () => _salvar(),
                      child: _salvando
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Salvar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF15803D),
                      ),
                      onPressed: (_salvando || finalizada)
                          ? null
                          : () => _salvar(finalizar: true),
                      child: const Text('Finalizar OS'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuscarCatalogoDialog extends StatefulWidget {
  const _BuscarCatalogoDialog({
    required this.titulo,
    required this.tipo,
  });

  final String titulo;
  final String tipo;

  @override
  State<_BuscarCatalogoDialog> createState() => _BuscarCatalogoDialogState();
}

class _BuscarCatalogoDialogState extends State<_BuscarCatalogoDialog> {
  final _osService = OsService();
  final _busca = TextEditingController();
  Timer? _debounce;
  List<ProdutoResumo> _lista = [];
  bool _buscando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _buscar);
  }

  Future<void> _buscar() async {
    setState(() {
      _buscando = true;
      _erro = null;
    });
    try {
      final lista = await _osService.buscarProdutos(_busca.text, tipo: widget.tipo);
      if (!mounted) return;
      setState(() {
        _lista = lista;
        _buscando = false;
        if (lista.isEmpty && _busca.text.trim().isNotEmpty) {
          _erro = widget.tipo == 'servico'
              ? 'Nenhum serviço encontrado no ERP.'
              : 'Nenhum produto encontrado no ERP.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lista = [];
        _buscando = false;
        _erro = 'Falha ao buscar no ERP. Verifique a conexão.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isServico = widget.tipo == 'servico';
    final maxH = MediaQuery.sizeOf(context).height * 0.55;

    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: double.maxFinite,
        height: maxH.clamp(240.0, 420.0),
        child: Column(
          children: [
            TextField(
              controller: _busca,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Buscar no ERP',
                hintText: 'Código ou descrição',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 10),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _erro!,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
              ),
            Expanded(
              child: _lista.isEmpty && !_buscando
                  ? Center(
                      child: Text(
                        isServico
                            ? 'Digite para buscar serviços cadastrados.'
                            : 'Digite para buscar produtos cadastrados.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _lista.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = _lista[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            p.descricao,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [
                              if (p.codigo.isNotEmpty) 'Cód. ${p.codigo}',
                              if (p.unidade.isNotEmpty) p.unidade,
                              if (isServico)
                                'R\$ ${p.preco.toStringAsFixed(2).replaceAll('.', ',')}',
                            ].join(' • '),
                          ),
                          onTap: () => Navigator.of(context).pop(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _Bloco extends StatelessWidget {
  const _Bloco({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo({required this.label, required this.valor});

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.text,
          ),
        ),
      ],
    );
  }
}

class _CampoComAcao extends StatelessWidget {
  const _CampoComAcao({
    required this.label,
    required this.valor,
    required this.icone,
    required this.acaoLabel,
    required this.onPressed,
  });

  final String label;
  final String valor;
  final IconData icone;
  final String acaoLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Campo(label: label, valor: valor)),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icone, size: 18),
          label: Text(acaoLabel),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _ValorServicoDialog extends StatefulWidget {
  const _ValorServicoDialog({
    required this.titulo,
    required this.descricao,
    required this.codigo,
    required this.valorInicial,
    required this.confirmarLabel,
  });

  final String titulo;
  final String descricao;
  final String codigo;
  final double valorInicial;
  final String confirmarLabel;

  @override
  State<_ValorServicoDialog> createState() => _ValorServicoDialogState();
}

class _ValorServicoDialogState extends State<_ValorServicoDialog> {
  late final TextEditingController _precoCtrl;

  @override
  void initState() {
    super.initState();
    _precoCtrl = TextEditingController(
      text: widget.valorInicial.toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _precoCtrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final raw = _precoCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final preco = double.tryParse(raw) ?? widget.valorInicial;
    Navigator.of(context).pop(preco);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.descricao,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (widget.codigo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Cód. ${widget.codigo}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _precoCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor (R\$)',
              hintText: '0,00',
            ),
            onSubmitted: (_) => _confirmar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _confirmar,
          child: Text(widget.confirmarLabel),
        ),
      ],
    );
  }
}
