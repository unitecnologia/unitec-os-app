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
import 'package:unitec_os_app/services/sync_service.dart';
import 'package:unitec_os_app/services/whatsapp_contato.dart';
import 'package:unitec_os_app/theme/app_theme.dart';
import 'package:unitec_os_app/widgets/assinatura_pad_dialog.dart';
import 'package:unitec_os_app/widgets/barcode_scan_page.dart';
import 'package:unitec_os_app/widgets/peca_lancada_card.dart';

class DetalheOsScreen extends StatefulWidget {
  const DetalheOsScreen({super.key, required this.osKey});

  static const route = '/detalhe-os';

  final String osKey;

  @override
  State<DetalheOsScreen> createState() => _DetalheOsScreenState();
}

class _DetalheOsScreenState extends State<DetalheOsScreen> with WidgetsBindingObserver {
  final _osService = OsService();
  final _servicoRealizado = TextEditingController();
  final _observacoes = TextEditingController();
  Timer? _persistirServicoTimer;
  bool _gravandoServico = false;
  bool _servicoPrestadoSujo = false;

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistirServicoTimer?.cancel();
    final os = _os;
    final texto = _servicoRealizado.text.trim();
    if (os != null && texto != os.servicoRealizado.trim()) {
      unawaited(_osService.gravarServicoPrestadoLocal(os, texto));
    }
    _servicoRealizado.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_persistirServicoPrestadoAgora());
    }
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

  void _agendarServicoPrestado(String _) {
    if (_gravandoServico) _servicoPrestadoSujo = true;
    _persistirServicoTimer?.cancel();
    _persistirServicoTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_persistirServicoPrestadoAgora());
    });
  }

  Future<void> _persistirServicoPrestadoAgora() async {
    _persistirServicoTimer?.cancel();
    final os = _os;
    if (os == null) return;
    if (_gravandoServico) {
      _servicoPrestadoSujo = true;
      return;
    }
    final texto = _servicoRealizado.text.trim();
    if (texto == os.servicoRealizado.trim()) return;

    _gravandoServico = true;
    try {
      final updated = await _osService.gravarServicoPrestadoLocal(os, texto);
      if (!mounted) {
        _os = updated;
        return;
      }
      setState(() => _os = updated);
    } catch (_) {
      _servicoPrestadoSujo = true;
    } finally {
      _gravandoServico = false;
      if (_servicoPrestadoSujo) {
        _servicoPrestadoSujo = false;
        final atual = _os;
        if (atual != null && _servicoRealizado.text.trim() != atual.servicoRealizado.trim()) {
          unawaited(_persistirServicoPrestadoAgora());
        }
      }
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'Pendente':
        return const Color(0xFFB45309);
      case 'Em andamento':
        return AppTheme.primaryBlue;
      case 'Em faturamento':
        return const Color(0xFF9A3412);
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
          ? 'Salvo no aparelho — aguardando sincronização.'
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
      _persistirServicoTimer?.cancel();
      final relato = _servicoRealizado.text.trim();
      if (finalizar) {
        updated = await _osService.atualizarAtendimento(
          os: _os!,
          observacoes: _observacoes.text.trim(),
          servicoRealizado: relato,
          pecas: List<PecaOs>.from(_pecas),
          servicos: List<PecaOs>.from(_servicos),
          finalizar: true,
        );
      } else {
        updated = await _osService.atualizarAtendimento(
          os: _os!,
          observacoes: _observacoes.text.trim(),
          servicoRealizado: relato,
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
      if (updated.pendingSync) {
        _toast('Salvo no aparelho — aguardando sincronização.');
      } else if (finalizar) {
        _toast('OS enviada para faturamento.');
      } else {
        _toast('OS salva.');
      }
      // Volta para a tela inicial (Minhas OS) após salvar ou finalizar.
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _salvando = false);
    } catch (_) {
      _toast(finalizar ? 'Falha ao enviar a OS para faturamento.' : 'Falha ao salvar.');
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _finalizarOs() async {
    if (_os == null || _salvando) return;

    final iniciada = _status == 'Em andamento' ||
        _status == 'Finalizada' ||
        (_inicioAtendimento != null && _inicioAtendimento!.trim().isNotEmpty);
    if (!iniciada || _status == 'Pendente') {
      _toast('Inicie o atendimento antes de enviar a OS para faturamento.');
      return;
    }

    if (_servicos.isEmpty) {
      _toast('Informe pelo menos um serviço realizado antes de enviar para faturamento.');
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar para faturamento'),
        content: const Text(
          'A OS vai aberta para o ERP. No app ela fica em faturamento até o faturamento ser concluído.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
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
        titulo: 'Selecionar peça',
        tipo: 'produto',
      ),
    );
    if (selecionado == null || !mounted) return;
    await _confirmarQuantidadePeca(selecionado);
  }

  Future<void> _confirmarQuantidadePeca(ProdutoResumo selecionado) async {
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
          codigoBarras: selecionado.codigoBarras.isNotEmpty
              ? selecionado.codigoBarras
              : selecionado.codigoBarrasCaixa,
          imei: selecionado.imei,
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
    final selecionado = await showDialog<ProdutoResumo>(
      context: context,
      builder: (ctx) => const _BuscarCatalogoDialog(
        titulo: 'Selecionar serviço',
        tipo: 'servico',
      ),
    );
    if (selecionado == null || !mounted) return;

    final lancamento = await showDialog<_LancamentoServico>(
      context: context,
      builder: (ctx) => _LancamentoServicoDialog(
        descricao: selecionado.descricao,
        precoInicial: selecionado.preco,
      ),
    );
    if (lancamento == null || !mounted) return;

    setState(() {
      _servicos.add(
        PecaOs(
          produtoId: selecionado.id,
          codigo: selecionado.codigo,
          descricao: selecionado.descricao,
          preco: lancamento.preco,
          qtd: lancamento.qtd,
        ),
      );
    });
  }

  Future<void> _alterarValorServico(int index) async {
    if (index < 0 || index >= _servicos.length) return;
    final item = _servicos[index];
    final lancamento = await showDialog<_LancamentoServico>(
      context: context,
      builder: (ctx) => _LancamentoServicoDialog(
        descricao: item.descricao,
        precoInicial: item.preco,
        qtdInicial: item.qtd,
        titulo: 'Alterar serviço',
        confirmarLabel: 'Salvar',
      ),
    );
    if (lancamento == null || !mounted) return;
    setState(() {
      _servicos[index] = item.copyWith(
        preco: lancamento.preco,
        qtd: lancamento.qtd,
      );
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
    final file = await _arquivoAssinatura(widget.osKey);
    await _enfileirarArquivo(file, 'assinatura');
    if (!mounted) return;
    setState(() {
      _assinaturaPng = bytes;
      _assinaturaSincronizada = false;
    });
    _toast('Salvo no aparelho — aguardando sincronização.');
    await _tentarEnviarFila();
    if (!mounted) return;
    if (await _estaSincronizado(file)) {
      setState(() => _assinaturaSincronizada = true);
    }
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

  Future<String?> _uuidDaOs() async {
    final atual = _os?.localUuid;
    if (atual != null && atual.isNotEmpty) return atual;
    final os = await _osService.obterPorKey(widget.osKey);
    final uuid = os?.localUuid;
    if (uuid == null || uuid.isEmpty) return null;
    return uuid;
  }

  Future<void> _enfileirarArquivo(File arquivo, String tipo) async {
    final uuid = await _uuidDaOs();
    if (uuid == null) return;
    await _osService.enfileirarMidia(
      localUuid: uuid,
      serverId: _os?.id,
      tipo: tipo,
      path: arquivo.path,
    );
  }

  Future<void> _tentarEnviarFila() async {
    if (!SyncService.instance.podeTentarErp) return;
    await SyncService.instance.sincronizar(forcePull: false);
    await _recarregarVinculoServidor();
  }

  /// Atualiza id e número oficial sem recriar a OS nem limpar o atendimento em edição.
  Future<void> _recarregarVinculoServidor() async {
    final uuid = _os?.localUuid;
    if (uuid == null || uuid.isEmpty) return;
    final atual = await _osService.obterPorKey('l:$uuid');
    if (!mounted || atual == null) return;
    setState(() => _os = atual);
  }

  Future<void> _sincronizarMidiasPendentes() async {
    for (final foto in List<File>.from(_fotos)) {
      if (await _estaSincronizado(foto)) continue;
      await _enfileirarArquivo(foto, 'foto');
    }
    final assinatura = await _arquivoAssinatura(widget.osKey);
    if (await assinatura.exists() && !await _estaSincronizado(assinatura)) {
      await _enfileirarArquivo(assinatura, 'assinatura');
    }
    await _tentarEnviarFila();
    if (!mounted) return;
    final fotosSync = <String>{};
    for (final foto in _fotos) {
      if (await _estaSincronizado(foto)) fotosSync.add(foto.path);
    }
    final assinaturaSync = await _estaSincronizado(assinatura);
    if (!mounted) return;
    setState(() {
      _fotosSincronizadas
        ..clear()
        ..addAll(fotosSync);
      _assinaturaSincronizada = assinaturaSync;
    });
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
      await _enfileirarArquivo(destino, 'foto');
      if (!mounted) return;
      setState(() => _fotos.add(destino));
      _toast('Salvo no aparelho — aguardando sincronização.');
      await _tentarEnviarFila();
      if (!mounted) return;
      if (await _estaSincronizado(destino)) {
        setState(() => _fotosSincronizadas.add(destino.path));
      }
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
      await _osService.removerMidiaFila(foto.path);
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

  Future<void> _abrirWhatsapp(String telefone) async {
    final ok = await WhatsappContato.abrir(telefone);
    if (!ok && mounted) {
      _toast('Não foi possível abrir o WhatsApp.');
    }
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
    final finalizada = _status == 'Finalizada' || _status == 'Em faturamento';

    return Theme(
      data: Theme.of(context).copyWith(
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            minimumSize: const Size.fromHeight(40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            side: const BorderSide(color: AppTheme.primaryBlue),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      child: Scaffold(
      appBar: AppBar(
        title: Text('OS ${os.numeroExibicao}'),
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'OS ${os.numeroExibicao}',
                              style: const TextStyle(
                                fontSize: 16,
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
                          const SizedBox(height: 6),
                          _Campo(label: 'Técnico', valor: os.tecnico),
                        ],
                        const SizedBox(height: 4),
                        _Campo(label: 'Cliente', valor: os.cliente),
                        const SizedBox(height: 4),
                        _CampoComAcao(
                          label: 'Telefone',
                          valor: os.telefone.isEmpty ? '—' : os.telefone,
                          icone: Icons.chat,
                          corAcao: const Color(0xFF128C7E),
                          acaoLabel: 'WhatsApp',
                          onPressed: () => _abrirWhatsapp(os.telefone),
                        ),
                        const SizedBox(height: 4),
                        _CampoComAcao(
                          label: 'Endereço',
                          valor: os.endereco.isEmpty ? '—' : os.endereco,
                          icone: Icons.map_outlined,
                          acaoLabel: 'Mapa',
                          onPressed: () => _toast('Mapa (mock).'),
                        ),
                        const SizedBox(height: 4),
                        _Campo(
                          label: 'Equipamento',
                          valor: os.equipamento.isEmpty ? '—' : os.equipamento,
                        ),
                        const SizedBox(height: 4),
                        _Campo(
                          label: 'Problema informado',
                          valor: os.problema.isEmpty ? '—' : os.problema,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
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
                              fontSize: 14,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          _status == 'Finalizada'
                              ? 'Atendimento finalizado.'
                              : (_status == 'Em faturamento'
                                  ? 'Aguardando faturamento no ERP.'
                                  : 'Atendimento em andamento.'),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
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
                      else ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  'Serviço',
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
                                width: 72,
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
                        ..._servicos.asMap().entries.map((e) {
                          final item = e.value;
                          final total = item.preco * item.qtd;
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
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    _fmtQtd(item.qtd),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 72,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: finalizada
                                        ? Text(
                                            _fmtMoney(item.preco),
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(fontSize: 12),
                                          )
                                        : InkWell(
                                            onTap: _salvando
                                                ? null
                                                : () => _alterarValorServico(e.key),
                                            child: Text(
                                              _fmtMoney(item.preco),
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.primaryBlue,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                          ),
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
                                          tooltip: 'Remover',
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
                                                    () => _servicos.removeAt(e.key),
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
                const SizedBox(height: 6),
                _Bloco(
                  titulo: 'Serviços prestados',
                  child: TextField(
                    controller: _servicoRealizado,
                    minLines: 2,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    enabled: !finalizada && !_salvando,
                    onChanged: _agendarServicoPrestado,
                    style: const TextStyle(fontSize: 14, height: 1.25),
                    decoration: const InputDecoration(
                      hintText: 'Descreva o que foi realizado no atendimento...',
                      alignLabelWithHint: true,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _Bloco(
                  titulo: 'Peças / Produtos',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (finalizada || _salvando)
                            ? null
                            : _adicionarPeca,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar peça'),
                      ),
                      const SizedBox(height: 8),
                      if (_pecas.isEmpty)
                        const Text(
                          'Nenhuma peça/produto adicionada.',
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        )
                      else
                        ..._pecas.asMap().entries.map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: PecaLancadaCard(
                              peca: e.value,
                              qtd: _fmtQtd(e.value.qtd),
                              unitario: _fmtMoney(e.value.preco),
                              total: _fmtMoney(e.value.preco * e.value.qtd),
                              podeExcluir: !finalizada && !_salvando,
                              onExcluir: () {
                                setState(() => _pecas.removeAt(e.key));
                              },
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
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
                const SizedBox(height: 6),
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
                const SizedBox(height: 6),
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                        backgroundColor: const Color(0xFF9A3412),
                      ),
                      onPressed: (_salvando || finalizada)
                          ? null
                          : _finalizarOs,
                      child: const Text('Enviar faturamento'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
  int? _selecionadoId;

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

  Future<void> _escanear() async {
    if (!SyncService.instance.podeTentarErp) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O ERP precisa estar online para achar a peça pelo código.'),
        ),
      );
      return;
    }
    final codigo = await BarcodeScanPage.abrir(context);
    if (codigo == null || !mounted) return;
    _busca.text = codigo.trim();
    await _buscar();
    if (!mounted || _lista.isEmpty) return;
    final exatos = _lista.where((p) => p.correspondeCodigo(_busca.text)).toList();
    if (exatos.length == 1) {
      Navigator.of(context).pop(exatos.first);
      return;
    }
    if (_lista.length == 1) {
      Navigator.of(context).pop(_lista.first);
    }
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
        _lista = lista.take(25).toList();
        _buscando = false;
        _selecionadoId = null;
        if (lista.isEmpty && !SyncService.instance.podeTentarErp) {
          _erro = 'ERP offline. A busca precisa do ERP respondendo.';
        } else if (lista.isEmpty && _busca.text.trim().isNotEmpty) {
          _erro = widget.tipo == 'servico'
              ? 'Nenhum serviço encontrado.'
              : 'Nenhuma peça encontrada.';
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

  void _escolher(ProdutoResumo item) {
    if (_selecionadoId == item.id) {
      Navigator.of(context).pop(item);
      return;
    }
    setState(() => _selecionadoId = item.id);
  }

  void _confirmarSelecao() {
    final id = _selecionadoId;
    if (id == null) return;
    for (final item in _lista) {
      if (item.id == id) {
        Navigator.of(context).pop(item);
        return;
      }
    }
  }

  String _moeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    final isServico = widget.tipo == 'servico';
    final tela = MediaQuery.sizeOf(context);
    final maxH = tela.height * 0.62;
    final largura = tela.width - 16;
    final selecionado = _selecionadoId != null;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
      constraints: BoxConstraints(minWidth: largura, maxWidth: largura),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.titulo),
          const SizedBox(height: 2),
          Text(
            isServico
                ? 'Pesquise por nome ou código'
                : 'Pesquise por nome, código, EAN, IMEI ou série',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.muted,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: largura,
        height: maxH.clamp(280.0, 480.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _busca,
              autofocus: true,
              decoration: InputDecoration(
                hintText: isServico
                    ? 'Digite nome ou código'
                    : 'Digite nome, código, EAN, IMEI ou série',
                prefixIcon: const Icon(Icons.search),
                suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                suffixIcon: _buscando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (!isServico
                        ? IconButton(
                            tooltip: 'Escanear código de barras',
                            onPressed: _escanear,
                            icon: const Icon(Icons.qr_code_scanner),
                          )
                        : null),
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
                        _erro != null
                            ? ''
                            : (isServico
                                ? 'Nenhum serviço para mostrar.'
                                : 'Digite para pesquisar a peça.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _lista.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final p = _lista[index];
                        return _ItemBusca(
                          item: p,
                          preco: _moeda(p.preco),
                          selecionado: p.id == _selecionadoId,
                          onTap: () => _escolher(p),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: selecionado ? _confirmarSelecao : null,
                    child: const Text('Selecionar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemBusca extends StatelessWidget {
  const _ItemBusca({
    required this.item,
    required this.preco,
    required this.selecionado,
    required this.onTap,
  });

  final ProdutoResumo item;
  final String preco;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final extras = <String>[
      if (item.codigoBarras.isNotEmpty) 'EAN: ${item.codigoBarras}',
      if (item.codigoBarrasCaixa.isNotEmpty) 'Cx: ${item.codigoBarrasCaixa}',
      if (item.imei.isNotEmpty) 'IMEI: ${item.imei}',
      if (item.numeroSerie.isNotEmpty) 'Série: ${item.numeroSerie}',
    ];
    final secundario = [
      if (item.codigo.isNotEmpty) 'Cód. ${item.codigo}',
      if (item.unidade.isNotEmpty) item.unidade,
    ].join(' · ');

    return Material(
      color: selecionado ? const Color(0xFFE8F1FB) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selecionado ? AppTheme.primaryBlue : AppTheme.border,
              width: selecionado ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.descricao,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.text,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    preco,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
              if (secundario.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  secundario,
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
              if (extras.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  extras.join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppTheme.text),
                ),
              ],
            ],
          ),
        ),
      ),
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
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 128,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted,
              height: 1.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
              height: 1.2,
            ),
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
    this.corAcao = AppTheme.primaryBlue,
  });

  final String label;
  final String valor;
  final IconData icone;
  final String acaoLabel;
  final VoidCallback onPressed;
  final Color corAcao;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Campo(label: label, valor: valor)),
        const SizedBox(width: 4),
        TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icone, size: 18),
          label: Text(acaoLabel),
          style: TextButton.styleFrom(
            foregroundColor: corAcao,
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
        OutlinedButton(
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

class _LancamentoServico {
  const _LancamentoServico({required this.qtd, required this.preco});

  final double qtd;
  final double preco;
}

class _LancamentoServicoDialog extends StatefulWidget {
  const _LancamentoServicoDialog({
    required this.descricao,
    required this.precoInicial,
    this.qtdInicial = 1,
    this.titulo = 'Serviço',
    this.confirmarLabel = 'Adicionar',
  });

  final String descricao;
  final double precoInicial;
  final double qtdInicial;
  final String titulo;
  final String confirmarLabel;

  @override
  State<_LancamentoServicoDialog> createState() => _LancamentoServicoDialogState();
}

class _LancamentoServicoDialogState extends State<_LancamentoServicoDialog> {
  late final TextEditingController _qtd;
  late final TextEditingController _valor;

  @override
  void initState() {
    super.initState();
    _qtd = TextEditingController(text: _formatarNumero(widget.qtdInicial, 3));
    _valor = TextEditingController(text: _formatarNumero(widget.precoInicial, 2));
  }

  @override
  void dispose() {
    _qtd.dispose();
    _valor.dispose();
    super.dispose();
  }

  String _formatarNumero(double valor, int casas) {
    if (casas == 3 && valor == valor.roundToDouble()) {
      return '${valor.toInt()}';
    }
    return valor.toStringAsFixed(casas).replaceAll('.', ',');
  }

  double? _lerNumero(String texto) {
    final raw = texto.trim().replaceAll('.', '').replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  void _confirmar() {
    final qtd = _lerNumero(_qtd.text);
    final preco = _lerNumero(_valor.text);
    if (qtd == null || qtd <= 0 || preco == null || preco < 0) return;
    Navigator.of(context).pop(_LancamentoServico(qtd: qtd, preco: preco));
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
          const SizedBox(height: 12),
          TextField(
            controller: _qtd,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantidade'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _valor,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor',
              prefixText: 'R\$ ',
            ),
            onSubmitted: (_) => _confirmar(),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _confirmar,
          child: Text(widget.confirmarLabel),
        ),
      ],
    );
  }
}
