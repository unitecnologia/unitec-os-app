import 'package:flutter/material.dart';
import 'package:unitec_os_app/ui/fv_brand.dart';

class ProdutoFotoImage extends StatelessWidget {
  const ProdutoFotoImage({
    super.key,
    this.networkUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius = 12,
    this.placeholderIconSize = 26,
    this.darkPlaceholder = false,
  });

  final String? networkUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final double placeholderIconSize;
  final bool darkPlaceholder;

  Widget _placeholder() {
    if (darkPlaceholder) {
      return SizedBox(
        width: width,
        height: height,
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: placeholderIconSize,
        ),
      );
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FvBrand.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: FvBrand.green.withValues(alpha: 0.2)),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        color: FvBrand.green,
        size: placeholderIconSize,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = networkUrl?.trim() ?? '';
    if (url.isEmpty) return _placeholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _placeholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: width,
            height: height,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: darkPlaceholder ? Colors.white : FvBrand.blue,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

void abrirProdutoFoto(
  BuildContext context, {
  String? url,
  String? titulo,
}) {
  if (url == null || url.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            titulo ?? 'Foto do produto',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: ProdutoFotoImage(
              networkUrl: url,
              fit: BoxFit.contain,
              borderRadius: 0,
              placeholderIconSize: 64,
              darkPlaceholder: true,
            ),
          ),
        ),
      ),
    ),
  );
}
