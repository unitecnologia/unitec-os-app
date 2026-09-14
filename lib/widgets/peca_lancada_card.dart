import 'package:flutter/material.dart';
import 'package:unitec_os_app/models/peca_os.dart';
import 'package:unitec_os_app/theme/app_theme.dart';

class PecaLancadaCard extends StatelessWidget {
  const PecaLancadaCard({
    required this.peca,
    required this.qtd,
    required this.unitario,
    required this.total,
    required this.podeExcluir,
    required this.onExcluir,
    super.key,
  });

  final PecaOs peca;
  final String qtd;
  final String unitario;
  final String total;
  final bool podeExcluir;
  final VoidCallback onExcluir;

  @override
  Widget build(BuildContext context) {
    final detalhes = [
      if (peca.codigo.isNotEmpty) 'Cód. ${peca.codigo}',
      if (peca.codigoBarras.isNotEmpty) 'EAN: ${peca.codigoBarras}',
      if (peca.imei.isNotEmpty) 'IMEI: ${peca.imei}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    peca.descricao,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.text,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
              if (podeExcluir)
                IconButton(
                  tooltip: 'Excluir peça',
                  onPressed: onExcluir,
                  icon: const Icon(Icons.delete_outline),
                  color: const Color(0xFFB91C1C),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (detalhes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                detalhes,
                style: const TextStyle(fontSize: 12, color: AppTheme.muted, height: 1.3),
              ),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 2),
            child: Text(
              'Qtd: $qtd · Unitário: $unitario · Total: $total',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
