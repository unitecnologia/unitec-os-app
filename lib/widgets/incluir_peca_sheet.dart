import 'package:flutter/material.dart';
import 'package:unitec_os_app/services/os_service.dart';
import 'package:unitec_os_app/ui/fv_brand.dart';
import 'package:unitec_os_app/ui/fv_format.dart';

class IncluirPecaResult {
  const IncluirPecaResult({
    required this.quantidade,
    required this.precoUnitario,
    required this.desconto,
  });

  final double quantidade;
  final double precoUnitario;
  final double desconto;
}

/// Modal de inclusão de peça com quantidade e desconto (layout Força de Vendas).
class IncluirPecaSheet extends StatefulWidget {
  const IncluirPecaSheet({
    super.key,
    required this.produto,
    this.confirmLabel = 'Incluir item',
    this.quantidadeInicial = 1,
    this.descontoPctInicial = 0,
    this.descontoValorInicial = 0,
  });

  final ProdutoResumo produto;
  final String confirmLabel;
  final double quantidadeInicial;
  final double descontoPctInicial;
  final double descontoValorInicial;

  static Future<IncluirPecaResult?> abrir(
    BuildContext context, {
    required ProdutoResumo produto,
    String confirmLabel = 'Incluir item',
  }) {
    return showModalBottomSheet<IncluirPecaResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IncluirPecaSheet(
        produto: produto,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<IncluirPecaSheet> createState() => _IncluirPecaSheetState();
}

class _IncluirPecaSheetState extends State<IncluirPecaSheet> {
  late final TextEditingController _qtd;
  late final TextEditingController _descPct;
  late final TextEditingController _descValor;
  late final double _precoUnitario;
  bool _sincDesc = false;

  String _fmtNum(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  String _fmtQtd(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void initState() {
    super.initState();
    _precoUnitario = widget.produto.preco;
    _qtd = TextEditingController(text: _fmtQtd(widget.quantidadeInicial));
    _descPct = TextEditingController(text: _fmtNum(widget.descontoPctInicial));
    _descValor = TextEditingController(text: _fmtNum(widget.descontoValorInicial));
  }

  @override
  void dispose() {
    _qtd.dispose();
    _descPct.dispose();
    _descValor.dispose();
    super.dispose();
  }

  double _parseNum(String s) =>
      double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;

  double get _quantidade => _parseNum(_qtd.text).clamp(0.001, 999999.0).toDouble();

  double get _bruto => _quantidade * _precoUnitario;

  double get _desconto {
    final pct = _parseNum(_descPct.text);
    if (pct > 0) return (_bruto * pct / 100).clamp(0.0, _bruto).toDouble();
    return _parseNum(_descValor.text).clamp(0.0, _bruto).toDouble();
  }

  void _syncFromPct() {
    if (_sincDesc) return;
    _sincDesc = true;
    final pct = _parseNum(_descPct.text);
    _descValor.text = _fmtNum((pct > 0 ? _bruto * pct / 100 : 0.0).toDouble());
    _sincDesc = false;
    setState(() {});
  }

  void _syncFromValor() {
    if (_sincDesc) return;
    _sincDesc = true;
    final valor = _parseNum(_descValor.text);
    final pct = _bruto > 0 ? valor / _bruto * 100.0 : 0.0;
    _descPct.text = _fmtNum(pct);
    _sincDesc = false;
    setState(() {});
  }

  void _alterarQtd(double delta) {
    final nova = (_parseNum(_qtd.text) + delta).clamp(0.001, 999999.0).toDouble();
    _qtd.text = _fmtQtd(nova);
    _syncFromPct();
    setState(() {});
  }

  void _alterarDescPct(double delta) {
    final nova = (_parseNum(_descPct.text) + delta).clamp(0.0, 100.0).toDouble();
    _descPct.text = _fmtNum(nova);
    _syncFromPct();
    setState(() {});
  }

  void _alterarDescValor(double delta) {
    final nova = (_parseNum(_descValor.text) + delta).clamp(0.0, _bruto).toDouble();
    _descValor.text = _fmtNum(nova);
    _syncFromValor();
    setState(() {});
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: FvBrand.blue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 48,
          child: Icon(icon, size: 20, color: FvBrand.blue),
        ),
      ),
    );
  }

  void _confirmar() {
    final qtd = _quantidade;
    if (qtd <= 0) return;
    Navigator.pop(
      context,
      IncluirPecaResult(
        quantidade: qtd,
        precoUnitario: _precoUnitario,
        desconto: _desconto,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.produto.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Preço unitário (bloqueado)',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Text(
                        brMoney(_precoUnitario),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: FvBrand.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _stepBtn(Icons.remove_rounded, () => _alterarQtd(-1)),
                    Expanded(
                      child: TextField(
                        controller: _qtd,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Quantidade',
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                        ),
                        onChanged: (_) {
                          _syncFromPct();
                          setState(() {});
                        },
                      ),
                    ),
                    _stepBtn(Icons.add_rounded, () => _alterarQtd(1)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _stepBtn(Icons.remove_rounded, () => _alterarDescPct(-1)),
                          Expanded(
                            child: TextField(
                              controller: _descPct,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                labelText: 'Desconto %',
                                suffixText: '%',
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(12)),
                                ),
                              ),
                              onChanged: (_) => _syncFromPct(),
                            ),
                          ),
                          _stepBtn(Icons.add_rounded, () => _alterarDescPct(1)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          _stepBtn(Icons.remove_rounded, () => _alterarDescValor(-1)),
                          Expanded(
                            child: TextField(
                              controller: _descValor,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                labelText: 'Desconto R\$',
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(12)),
                                ),
                              ),
                              onChanged: (_) => _syncFromValor(),
                            ),
                          ),
                          _stepBtn(Icons.add_rounded, () => _alterarDescValor(1)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Total do item: ${brMoney(_bruto - _desconto)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: FvBrand.green,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _confirmar,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(widget.confirmLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: FvBrand.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
