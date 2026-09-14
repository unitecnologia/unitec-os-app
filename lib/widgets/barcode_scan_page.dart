import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:unitec_os_app/theme/app_theme.dart';

/// Lê um código de barras ou QR e devolve o texto. Não grava nada.
class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});

  static Future<String?> abrir(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BarcodeScanPage()),
    );
  }

  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  var _fechou = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _concluir(String valor) {
    if (_fechou || !mounted) return;
    final codigo = valor.trim();
    if (codigo.isEmpty) return;
    _fechou = true;
    Navigator.of(context).pop(codigo);
  }

  String _mensagemErro(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Permita o uso da câmera para ler o código de barras.',
      MobileScannerErrorCode.unsupported =>
        'Este aparelho não tem câmera para escanear o código.',
      _ => 'Não foi possível abrir a câmera.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear código de barras'),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: (captura) {
                for (final codigo in captura.barcodes) {
                  final valor = codigo.rawValue;
                  if (valor != null && valor.trim().isNotEmpty) {
                    _concluir(valor);
                    return;
                  }
                }
              },
              errorBuilder: (context, error) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _mensagemErro(error),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                );
              },
              overlayBuilder: (context, constraints) {
                return Center(
                  child: Container(
                    width: constraints.maxWidth * 0.82,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
            ),
          ),
          const SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Text(
                'Aponte a câmera para o código da peça.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.background,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
