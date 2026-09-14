import 'package:url_launcher/url_launcher.dart';

/// Abre a conversa do WhatsApp. Não altera o telefone salvo na OS.
class WhatsappContato {
  static String? numero(String telefone) {
    var digits = telefone.replaceAll(RegExp(r'\D'), '');
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.isEmpty) return null;
    if (!(digits.startsWith('55') && digits.length >= 12)) {
      digits = '55$digits';
    }
    if (digits.length < 12) return null;
    return digits;
  }

  static Future<bool> abrir(String telefone) async {
    final destino = numero(telefone);
    if (destino == null) return false;
    final uri = Uri.parse('whatsapp://send?phone=$destino');
    try {
      if (!await canLaunchUrl(uri)) return false;
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
