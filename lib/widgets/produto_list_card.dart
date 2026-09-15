import 'package:flutter/material.dart';
import 'package:unitec_os_app/config/api_config.dart';
import 'package:unitec_os_app/services/os_service.dart';
import 'package:unitec_os_app/ui/fv_brand.dart';
import 'package:unitec_os_app/ui/fv_format.dart';
import 'package:unitec_os_app/widgets/estoque_linha_grid.dart';
import 'package:unitec_os_app/widgets/produto_foto_image.dart';

class ProdutoListCard extends StatelessWidget {
  const ProdutoListCard({
    super.key,
    required this.produto,
    required this.onTap,
    this.onFotoTap,
  });

  final ProdutoResumo produto;
  final VoidCallback onTap;
  final VoidCallback? onFotoTap;

  @override
  Widget build(BuildContext context) {
    final fotoUrl = produtoFotoUrlCompleta(ApiConfig.erpBaseUrl, produto.fotoUrl);

    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0xFF0F2847).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 7, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onFotoTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: FvBrand.green.withValues(alpha: 0.2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ProdutoFotoImage(
                    networkUrl: fotoUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    borderRadius: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.descricao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.2,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 5),
                    EstoqueLinhaGrid(produto: produto),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 58),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: FvBrand.precoVarejo.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: FvBrand.precoVarejo.withValues(alpha: 0.55),
                    width: 1.3,
                  ),
                ),
                child: Text(
                  brMoney(produto.preco),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    height: 1.1,
                    color: FvBrand.precoVarejo,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
