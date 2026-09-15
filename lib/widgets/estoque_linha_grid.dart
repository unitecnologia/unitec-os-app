import 'package:flutter/material.dart';
import 'package:unitec_os_app/services/os_service.dart';
import 'package:unitec_os_app/ui/fv_brand.dart';
import 'package:unitec_os_app/ui/fv_format.dart';

class EstoqueLinhaGrid extends StatelessWidget {
  const EstoqueLinhaGrid({super.key, required this.produto});

  final ProdutoResumo produto;

  static const double _gap = 3;
  static const double _colChip = 54;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _celula('Cód.', produto.codigo, FvBrand.produtoCodigo, Colors.white),
        const SizedBox(width: _gap),
        _celula(
          'Atual',
          fmtEstoque(produto.estoque),
          FvBrand.estoqueAtual,
          Colors.white,
        ),
        const SizedBox(width: _gap),
        _celula(
          'Reserv.',
          fmtEstoque(produto.estoqueReservado),
          FvBrand.estoqueReservado,
          FvBrand.estoqueReservadoText,
        ),
        const SizedBox(width: _gap),
        _celula(
          'Disp.',
          fmtEstoque(produto.estoqueDisponivel),
          FvBrand.estoqueDisponivel,
          Colors.white,
        ),
      ],
    );
  }

  Widget _celula(String label, String valor, Color bg, Color fg) {
    return SizedBox(
      width: _colChip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: bg.withValues(alpha: 0.22),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: fg.withValues(alpha: 0.92),
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              valor,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: fg,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
