import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unitec_os_app/config/api_config.dart';
import 'package:unitec_os_app/services/os_service.dart';
import 'package:unitec_os_app/services/sync_service.dart';
import 'package:unitec_os_app/ui/fv_brand.dart';
import 'package:unitec_os_app/ui/fv_format.dart';
import 'package:unitec_os_app/widgets/barcode_scan_page.dart';
import 'package:unitec_os_app/widgets/produto_foto_image.dart';
import 'package:unitec_os_app/widgets/produto_list_card.dart';

/// Bottom sheet de seleção de produto (layout Força de Vendas).
class SelecionarProdutoSheet extends StatefulWidget {
  const SelecionarProdutoSheet({
    super.key,
    this.titulo = 'Selecionar produto',
    this.tipo = 'produto',
  });

  final String titulo;
  final String tipo;

  static Future<ProdutoResumo?> abrir(
    BuildContext context, {
    String titulo = 'Selecionar produto',
    String tipo = 'produto',
  }) {
    return showModalBottomSheet<ProdutoResumo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelecionarProdutoSheet(titulo: titulo, tipo: tipo),
    );
  }

  @override
  State<SelecionarProdutoSheet> createState() => _SelecionarProdutoSheetState();
}

class _SelecionarProdutoSheetState extends State<SelecionarProdutoSheet> {
  final _osService = OsService();
  final _busca = TextEditingController();
  Timer? _debounce;
  List<ProdutoResumo> _lista = [];
  List<String> _grupos = [];
  String? _grupoSel;
  bool _buscando = false;
  String? _erro;

  bool get _isProduto => widget.tipo == 'produto';

  @override
  void initState() {
    super.initState();
    if (_isProduto) _carregarGrupos();
    _buscar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregarGrupos() async {
    final nomes = await _osService.buscarGrupos();
    if (!mounted) return;
    setState(() {
      _grupos = nomes;
      if (_grupoSel != null && !_grupos.contains(_grupoSel)) {
        _grupoSel = null;
      }
    });
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _buscar);
  }

  Future<void> _escanear() async {
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
      final lista = await _osService.buscarProdutos(
        _busca.text,
        tipo: widget.tipo,
        grupo: _grupoSel,
      );
      final temCatalogo = await _osService.catalogoDisponivel();
      if (!mounted) return;
      String? erro;
      if (lista.isEmpty) {
        if (!SyncService.instance.podeTentarErp && !temCatalogo) {
          erro = 'Catálogo ainda não sincronizado. Conecte uma vez ao ERP.';
        } else if (_busca.text.trim().isNotEmpty) {
          erro = _isProduto ? 'Nenhuma peça encontrada.' : 'Nenhum serviço encontrado.';
        }
      }
      setState(() {
        _lista = lista;
        _buscando = false;
        _erro = erro;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lista = [];
        _buscando = false;
        _erro = 'Falha ao buscar produtos.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;

    return SizedBox(
      height: h * 0.94,
      child: Container(
        decoration: const BoxDecoration(
          color: FvBrand.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 2),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.titulo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _busca,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
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
                        : (_isProduto
                            ? IconButton(
                                tooltip: 'Escanear código de barras',
                                onPressed: _escanear,
                                icon: const Icon(
                                  Icons.qr_code_scanner,
                                  color: FvBrand.blue,
                                ),
                              )
                            : null),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: _onChanged,
                ),
              ),
              if (_isProduto && _grupos.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _chip('Todos', _grupoSel == null, () {
                        setState(() => _grupoSel = null);
                        _buscar();
                      }),
                      for (final g in _grupos)
                        _chip(g, _grupoSel == g, () {
                          setState(() => _grupoSel = g);
                          _buscar();
                        }),
                    ],
                  ),
                ),
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    _erro!,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: _lista.isEmpty && !_buscando
                    ? Center(
                        child: Text(
                          _erro != null ? '' : 'Nada encontrado.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                        itemCount: _lista.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final p = _lista[i];
                          final fotoUrl = produtoFotoUrlCompleta(
                            ApiConfig.erpBaseUrl,
                            p.fotoUrl,
                          );
                          return ProdutoListCard(
                            produto: p,
                            onTap: () => Navigator.pop(context, p),
                            onFotoTap: () => abrirProdutoFoto(
                              context,
                              url: fotoUrl,
                              titulo: p.descricao,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onTap(),
        selectedColor: FvBrand.blue,
        labelStyle: TextStyle(
          color: sel ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );
  }
}
