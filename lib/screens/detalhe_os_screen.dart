import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:unitec_os_app/models/ordem_servico.dart';
import 'package:unitec_os_app/models/peca_os.dart';
import 'package:unitec_os_app/services/api_client.dart';
import 'package:unitec_os_app/services/os_service.dart';
import 'package:unitec_os_app/theme/app_theme.dart';
import 'package:unitec_os_app/widgets/assinatura_pad_dialog.dart';

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
  final List<File> _fotos = [];
  final _imagePicker = ImagePicker();
  final Set<String> _fotosSincronizadas = {};
  Uint8List? _assinaturaPng;
  bool _assinaturaSincronizada = false;
  bool _enviandoMidia = false;

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
      final assinatura = await _lerAssinaturaLocal(widget.osKey);
      final fotos = await _listarFotosLocal(widget.osKey);
      if (!mounted) return;
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
        _fotos
          ..clear()
          ..addAll(fotos);
        _assinaturaPng = assinatura;
        _carregando = false;
      });
      // ignore: discarded_futures
      _sincronizarMidiasPendentes();
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
      final OrdemServico updated;
      if (finalizar) {
        updated = await _osService.atualizarAtendimento(
          os: _os!,
          observacoes: _observacoes.text.trim(),
          pecas: List<PecaOs>.from(_pecas),
          servicos: List<PecaOs>.from(_servicos),
          finalizar: true,
        );
      } else {
        updated = await _osService.atualizarAtendimento(
          os: _os!,
          observacoes: _observacoes.text.trim(),
          servicos: List<PecaOs>.from(_servicos),
          pecas: List<PecaOs>.from(_pecas),
        );
      }
      if (!mounted) return;
      setState(() {
        _os = updated;
        _status = updated.status;
        _inicioAtendimento = updated.horaInicio;
        _servicoRealizado.text = updated.servicoRealizado;
        _observacoes.text = updated.observacao;
        _servicos
          ..clear()
          ..addAll(updated.servicos);
        _pecas
          ..clear()
          ..addAll(updated.pecas);
        _salvando = false;
      });
      if (finalizar) {
        _toast(updated.pendingSync
            ? 'OS finalizada (aguardando sync).'
            : 'OS finalizada.');
      } else {
        _toast(updated.pendingSync
            ? 'Salvo localmente (aguardando sync).'
            : 'OS salva.');
      }
      // Volta para a tela inicial (Minhas OS) após salvar ou finalizar.
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _salvando = false);
    } catch (_) {
      _toast(finalizar ? 'Falha ao finalizar a OS.' : 'Falha ao salvar.');
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _finalizarOs() async {
    if (_os == null || _salvando) return;

    final iniciada = _status == 'Em andamento' ||
        _status == 'Finalizada' ||
        (_inicioAtendimento != null && _inicioAtendimento!.trim().isNotEmpty);
    if (!iniciada || _status == 'Pendente') {
      _toast('Inicie o atendimento antes de finalizar a OS.');
      return;
    }

    if (_servicos.isEmpty) {
      _toast('Informe pelo menos um serviço realizado antes de finalizar.');
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar OS'),
        content: const Text('Deseja finalizar esta OS?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    await _salvar(finalizar: true);
  }

  Future<void> _adicionarPeca() async {
    final selecionado = await showDialog<ProdutoResumo>(
      context: context,
      builder: (ctx) => const _BuscarCatalogoDialog(
        titulo: 'Adicionar peça / produto',
        tipo: 'produto',
      ),
    );
    if (selecionado == null || !mounted) return;

    final qtd = await showDialog<double>(
      context: context,
      builder: (ctx) => const _QuantidadePecaDialog(),
    );
    if (qtd == null || !mounted) return;

    setState(() {
      _pecas.add(
        PecaOs(
          produtoId: selecionado.id,
          codigo: selecionado.codigo,
          descricao: selecionado.descricao,
          preco: selecionado.preco,
          qtd: qtd,
        ),
      );
    });
  }

  String _fmtMoney(double v) {
    return 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _fmtQtd(double v) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  Future<void> _adicionarServicoRealizado() async {
    final descricao = await showDialog<String>(
      context: context,
      builder: (ctx) => const _DescricaoServicoDialog(),
    );
    if (descricao == null || !mounted) return;
    final texto = descricao.trim();
    if (texto.isEmpty) return;
    setState(() {
      _servicos.add(PecaOs(descricao: texto.toUpperCase()));
    });
  }

  String _chaveArquivoAssinatura(String osKey) =>
      osKey.replaceAll(RegExp(r'[^\w\-]+'), '_');

  Future<File> _arquivoAssinatura(String osKey) async {
    final dir = await getApplicationDocumentsDirectory();
    final pasta = Directory(p.join(dir.path, 'assinaturas'));
    if (!await pasta.exists()) {
      await pasta.create(recursive: true);
    }
    return File(p.join(pasta.path, '${_chaveArquivoAssinatura(osKey)}.png'));
  }

  Future<Uint8List?> _lerAssinaturaLocal(String osKey) async {
    try {
      final file = await _arquivoAssinatura(osKey);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _salvarAssinaturaLocal(String osKey, Uint8List bytes) async {
    final file = await _arquivoAssinatura(osKey);
    await file.writeAsBytes(bytes, flush: true);
    await _marcarNaoSincronizado(file);
  }

  File _marcadorSync(File arquivo) => File('${arquivo.path}.ok');

  Future<bool> _estaSincronizado(File arquivo) async {
    try {
      return await _marcadorSync(arquivo).exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> _marcarSincronizado(File arquivo) async {
    try {
      await _marcadorSync(arquivo).writeAsString(
        DateTime.now().toIso8601String(),
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> _marcarNaoSincronizado(File arquivo) async {
    try {
      final m = _marcadorSync(arquivo);
      if (await m.exists()) await m.delete();
    } catch (_) {}
  }

  Future<void> _coletarAssinatura() async {
    final bytes = await AssinaturaPadDialog.show(context);
    if (bytes == null || !mounted) return;
    await _salvarAssinaturaLocal(widget.osKey, bytes);
    if (!mounted) return;
    setState(() {
      _assinaturaPng = bytes;
      _assinaturaSincronizada = false;
    });
    _toast('Assinatura salva.');
    await _enviarAssinaturaSePossivel(bytes);
  }

  String _chavePastaFotos(String osKey) =>
      osKey.replaceAll(RegExp(r'[^\w\-]+'), '_');

  Future<Directory> _pastaFotos(String osKey) async {
    final dir = await getApplicationDocumentsDirectory();
    final pasta =
        Directory(p.join(dir.path, 'fotos_os', _chavePastaFotos(osKey)));
    if (!await pasta.exists()) {
      await pasta.create(recursive: true);
    }
    return pasta;
  }

  Future<List<File>> _listarFotosLocal(String osKey) async {
    try {
      final pasta = await _pastaFotos(osKey);
      final arquivos = pasta
          .listSync()
          .whereType<File>()
          .where((f) {
            final ext = p.extension(f.path).toLowerCase();
            return ext == '.jpg' ||
                ext == '.jpeg' ||
                ext == '.png' ||
                ext == '.webp';
          })
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      _fotosSincronizadas.clear();
      for (final f in arquivos) {
        if (await _estaSincronizado(f)) {
          _fotosSincronizadas.add(f.path);
        }
      }

      final assinaturaFile = await _arquivoAssinatura(osKey);
      _assinaturaSincronizada = await _estaSincronizado(assinaturaFile);

      return arquivos;
    } catch (_) {
      return [];
    }
  }

  Future<void> _sincronizarMidiasPendentes() async {
    final osId = _os?.id;
    if (osId == null || _enviandoMidia) return;

    for (final foto in List<File>.from(_fotos)) {
      if (_fotosSincronizadas.contains(foto.path)) continue;
      await _enviarFotoSePossivel(foto, silencioso: true);
    }

    if (_assinaturaPng != null && !_assinaturaSincronizada) {
      await _enviarAssinaturaSePossivel(_assinaturaPng!, silencioso: true);
    }
  }

  Future<void> _enviarFotoSePossivel(
    File foto, {
    bool silencioso = false,
  }) async {
    final osId = _os?.id;
    if (osId == null) {
      if (!silencioso) {
        _toast('Salve a OS no ERP antes de enviar fotos.');
      }
      return;
    }
    try {
      setState(() => _enviandoMidia = true);
      await _osService.enviarFotoOs(osId: osId, arquivo: foto);
      await _marcarSincronizado(foto);
      if (!mounted) return;
      setState(() {
        _fotosSincronizadas.add(foto.path);
        _enviandoMidia = false;
      });
      if (!silencioso) _toast('Foto enviada ao ERP.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _enviandoMidia = false);
      if (!silencioso) _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _enviandoMidia = false);
      if (!silencioso) {
        _toast('Falha ao enviar foto. Mantida localmente.');
      }
    }
  }

  Future<void> _enviarAssinaturaSePossivel(
    Uint8List bytes, {
    bool silencioso = false,
  }) async {
    final osId = _os?.id;
    if (osId == null) {
      if (!silencioso) {
        _toast('Salve a OS no ERP antes de enviar a assinatura.');
      }
      return;
    }
    try {
      setState(() => _enviandoMidia = true);
      await _osService.enviarAssinaturaOs(osId: osId, pngBytes: bytes);
      final file = await _arquivoAssinatura(widget.osKey);
      await _marcarSincronizado(file);
      if (!mounted) return;
      setState(() {
        _assinaturaSincronizada = true;
        _enviandoMidia = false;
      });
      if (!silencioso) _toast('Assinatura enviada ao ERP.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _enviandoMidia = false);
      if (!silencioso) _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _enviandoMidia = false);
      if (!silencioso) {
        _toast('Falha ao enviar assinatura. Mantida localmente.');
      }
    }
  }

  Future<void> _adicionarFoto() async {
    final origem = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (origem == null || !mounted) return;

    try {
      final escolhida = await _imagePicker.pickImage(
        source: origem,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (escolhida == null || !mounted) return;

      final pasta = await _pastaFotos(widget.osKey);
      final nome =
          '${DateTime.now().millisecondsSinceEpoch}_${_fotos.length + 1}.jpg';
      final destino = File(p.join(pasta.path, nome));
      await File(escolhida.path).copy(destino.path);
      if (!mounted) return;
      setState(() => _fotos.add(destino));
      await _enviarFotoSePossivel(destino);
    } catch (_) {
      if (!mounted) return;
      _toast('Não foi possível adicionar a foto.');
    }
  }

  Future<void> _excluirFoto(File foto) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir foto'),
        content: const Text('Deseja remover esta foto da OS?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (await foto.exists()) await foto.delete();
      await _marcarNaoSincronizado(foto);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _fotos.removeWhere((f) => f.path == foto.path);
      _fotosSincronizadas.remove(foto.path);
    });
  }

  void _verFoto(File foto) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Image.file(foto, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
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
                      if (_status == 'Pendente')
                        ElevatedButton.icon(
                          onPressed: (_salvando || finalizada) ? null : _iniciarAtendimento,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Iniciar atendimento'),
                        )
                      else ...[
                        if (_inicioAtendimento != null &&
                            _inicioAtendimento!.isNotEmpty) ...[
                          Text(
                            'Início: $_inicioAtendimento',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
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
                  titulo: 'Serviços realizados',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (finalizada || _salvando)
                            ? null
                            : _adicionarServicoRealizado,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar serviço'),
                      ),
                      const SizedBox(height: 8),
                      if (_servicos.isEmpty)
                        const Text(
                          'Nenhum serviço realizado adicionado.',
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        )
                      else
                        ..._servicos.asMap().entries.map((e) {
                          final item = e.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                    color: AppTheme.muted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.descricao,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (!finalizada)
                                  IconButton(
                                    tooltip: 'Remover',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _salvando
                                        ? null
                                        : () {
                                            setState(
                                              () => _servicos.removeAt(e.key),
                                            );
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
                        onPressed:
                            (finalizada || _salvando) ? null : _adicionarPeca,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar peça'),
                      ),
                      const SizedBox(height: 8),
                      if (_pecas.isEmpty)
                        const Text(
                          'Nenhuma peça/produto adicionada.',
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        )
                      else ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  'Produto',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  'Qtd',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 64,
                                child: Text(
                                  'Valor',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 64,
                                child: Text(
                                  'Total',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ),
                              SizedBox(width: 36),
                            ],
                          ),
                        ),
                        ..._pecas.asMap().entries.map((e) {
                          final peca = e.value;
                          final total = peca.preco * peca.qtd;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 4,
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
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    _fmtQtd(peca.qtd),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    _fmtMoney(peca.preco),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    _fmtMoney(total),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 36,
                                  child: (!finalizada)
                                      ? IconButton(
                                          tooltip: 'Excluir',
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                          onPressed: _salvando
                                              ? null
                                              : () {
                                                  setState(
                                                    () => _pecas.removeAt(e.key),
                                                  );
                                                },
                                          icon: const Icon(Icons.close, size: 18),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
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
                        onPressed:
                            (finalizada || _salvando) ? null : _adicionarFoto,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('+ Adicionar foto'),
                      ),
                      if (_fotos.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _fotos.map((foto) {
                            final sync = _fotosSincronizadas.contains(foto.path);
                            return SizedBox(
                              width: 88,
                              height: 88,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: Material(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () => _verFoto(foto),
                                        child: Image.file(
                                          foto,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, error, stackTrace) =>
                                              const Center(
                                            child: Icon(
                                              Icons.broken_image_outlined,
                                              color: AppTheme.muted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 4,
                                    bottom: 4,
                                    child: Icon(
                                      sync
                                          ? Icons.cloud_done_outlined
                                          : Icons.cloud_upload_outlined,
                                      size: 16,
                                      color: sync
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFFB45309),
                                    ),
                                  ),
                                  if (!finalizada)
                                    Positioned(
                                      top: -6,
                                      right: -6,
                                      child: Material(
                                        color: Colors.white,
                                        shape: const CircleBorder(),
                                        elevation: 1,
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: _salvando
                                              ? null
                                              : () => _excluirFoto(foto),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Color(0xFFB45309),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
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
                            : _coletarAssinatura,
                        icon: const Icon(Icons.draw_outlined),
                        label: Text(
                          _assinaturaPng == null
                              ? 'Coletar assinatura'
                              : 'Refazer assinatura',
                        ),
                      ),
                      if (_assinaturaPng != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          height: 96,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Image.memory(
                            _assinaturaPng!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _assinaturaSincronizada
                              ? 'Assinatura sincronizada'
                              : 'Assinatura local (aguardando envio)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _assinaturaSincronizada
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB45309),
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
                          : _finalizarOs,
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
        _lista = lista.take(20).toList();
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
                hintText: isServico
                    ? 'Código ou descrição'
                    : 'Código, código de barras ou descrição',
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
                            : 'Digite código, barras ou descrição.',
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

class _QuantidadePecaDialog extends StatefulWidget {
  const _QuantidadePecaDialog();

  @override
  State<_QuantidadePecaDialog> createState() => _QuantidadePecaDialogState();
}

class _QuantidadePecaDialogState extends State<_QuantidadePecaDialog> {
  final _ctrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final raw = _ctrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final qtd = double.tryParse(raw);
    if (qtd == null || qtd <= 0) return;
    Navigator.of(context).pop(qtd);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quantidade'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Qtd',
          hintText: '1',
        ),
        onSubmitted: (_) => _confirmar(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _confirmar,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

class _DescricaoServicoDialog extends StatefulWidget {
  const _DescricaoServicoDialog();

  @override
  State<_DescricaoServicoDialog> createState() => _DescricaoServicoDialogState();
}

class _DescricaoServicoDialogState extends State<_DescricaoServicoDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty) return;
    Navigator.of(context).pop(texto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Serviço realizado'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Descreva o serviço realizado',
        ),
        onSubmitted: (_) => _confirmar(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _confirmar,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
