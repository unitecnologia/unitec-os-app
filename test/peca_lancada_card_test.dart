import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_os_app/models/peca_os.dart';
import 'package:unitec_os_app/theme/app_theme.dart';
import 'package:unitec_os_app/widgets/peca_lancada_card.dart';

void main() {
  testWidgets('card da peça lançada', (tester) async {
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(420, 280));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppTheme.background,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 390,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: PecaLancadaCard(
                    peca: const PecaOs(
                      descricao: 'VALVULA PADRAO SISTEMAS',
                      codigo: '1',
                      codigoBarras: '7770000000012',
                      imei: '2514236525',
                    ),
                    qtd: '1',
                    unitario: 'R\$ 3,99',
                    total: 'R\$ 3,99',
                    podeExcluir: true,
                    onExcluir: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    final file = File(r'C:\Users\Alencar\AppData\Local\Temp\peca-lancada.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());

    expect(find.text('VALVULA PADRAO SISTEMAS'), findsOneWidget);
    expect(find.text('Cód. 1 · EAN: 7770000000012 · IMEI: 2514236525'), findsOneWidget);
    expect(find.text('Qtd: 1 · Unitário: R\$ 3,99 · Total: R\$ 3,99'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });
}
