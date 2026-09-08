import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:unitec_os_app/theme/app_theme.dart';

/// Modal grande para coletar assinatura do cliente (dedo / stylus).
/// Retorna PNG em bytes ao confirmar; `null` se cancelar.
class AssinaturaPadDialog extends StatefulWidget {
  const AssinaturaPadDialog({super.key, this.titulo = 'Assinatura do cliente'});

  final String titulo;

  static Future<Uint8List?> show(BuildContext context) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AssinaturaPadDialog(),
    );
  }

  @override
  State<AssinaturaPadDialog> createState() => _AssinaturaPadDialogState();
}

class _AssinaturaPadDialogState extends State<AssinaturaPadDialog> {
  final _boundaryKey = GlobalKey();
  final List<List<Offset>> _tracos = [];
  List<Offset>? _tracoAtual;
  bool _exportando = false;

  bool get _temAssinatura =>
      _tracos.any((t) => t.isNotEmpty) || (_tracoAtual?.isNotEmpty ?? false);

  void _iniciar(DragStartDetails details) {
    setState(() {
      _tracoAtual = [details.localPosition];
    });
  }

  void _atualizar(DragUpdateDetails details) {
    final atual = _tracoAtual;
    if (atual == null) return;
    setState(() {
      atual.add(details.localPosition);
    });
  }

  void _finalizar(DragEndDetails details) {
    final atual = _tracoAtual;
    if (atual == null) return;
    setState(() {
      if (atual.isNotEmpty) _tracos.add(List<Offset>.from(atual));
      _tracoAtual = null;
    });
  }

  void _limpar() {
    setState(() {
      _tracos.clear();
      _tracoAtual = null;
    });
  }

  Future<void> _confirmar() async {
    if (!_temAssinatura || _exportando) return;
    setState(() => _exportando = true);
    try {
      await Future<void>.delayed(Duration.zero);
      final boundary =
          _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) setState(() => _exportando = false);
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = byteData?.buffer.asUint8List();
      if (!mounted) return;
      if (bytes == null) {
        setState(() => _exportando = false);
        return;
      }
      Navigator.of(context).pop(bytes);
    } catch (_) {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: size.width,
        height: size.height * 0.72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.titulo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border, width: 1.4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          key: _boundaryKey,
                          child: ColoredBox(
                            color: Colors.white,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: _iniciar,
                              onPanUpdate: _atualizar,
                              onPanEnd: _finalizar,
                              child: CustomPaint(
                                painter: _AssinaturaPainter(
                                  tracos: [
                                    ..._tracos,
                                    ?_tracoAtual,
                                  ],
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                        if (!_temAssinatura)
                          const IgnorePointer(
                            child: Center(
                              child: Text(
                                'ASSINE AQUI COM O DEDO',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: AppTheme.muted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _exportando ? null : _limpar,
                      child: const Text('Limpar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _exportando
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          (!_temAssinatura || _exportando) ? null : _confirmar,
                      child: _exportando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssinaturaPainter extends CustomPainter {
  _AssinaturaPainter({required this.tracos});

  final List<List<Offset>> tracos;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final pointPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final traco in tracos) {
      if (traco.isEmpty) continue;
      if (traco.length == 1) {
        canvas.drawCircle(traco.first, 1.6, pointPaint);
        continue;
      }
      final path = Path()..moveTo(traco.first.dx, traco.first.dy);
      for (var i = 1; i < traco.length; i++) {
        path.lineTo(traco[i].dx, traco[i].dy);
      }
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AssinaturaPainter oldDelegate) => true;
}
