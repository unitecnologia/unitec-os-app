enum ErpAlcance { online, offline, verificando }

/// Normalização da URL do ERP e da descoberta local.
/// Túnel Cloudflare / unierp.uk nunca vira http nem é substituído por localhost.
class ErpUrl {
  /// Wi-Fi não significa online. Só [apiRespondeu] true marca o ERP como online.
  static ErpAlcance avaliar({
    required bool temInternet,
    required bool? apiRespondeu,
  }) {
    if (!temInternet) return ErpAlcance.offline;
    if (apiRespondeu == null) return ErpAlcance.verificando;
    return apiRespondeu ? ErpAlcance.online : ErpAlcance.offline;
  }

  static const hostsNuvem = [
    'trycloudflare.com',
    'cfargotunnel.com',
    'unierp.uk',
  ];

  static String normalize(String raw) {
    var texto = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (texto.isEmpty) return '';

    if (!texto.contains('://')) {
      final host = _hostDe(texto);
      texto = '${_esquemaPara(host)}://$texto';
    }

    var uri = Uri.tryParse(texto);
    if (uri == null || uri.host.isEmpty) return texto;

    final host = uri.host;
    final publico = ehNuvem(host) || !_ehLocal(host);
    var scheme = uri.scheme;
    var port = uri.hasPort ? uri.port : null;

    if (publico) {
      scheme = 'https';
      // Cloudflare / unierp.uk só atendem 443. Porta 8000/8765 na URL pública quebra o app.
      if (port != null && port != 443) {
        port = null;
      }
    }

    return Uri(
      scheme: scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: host,
      port: port,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    ).toString().replaceAll(RegExp(r'/+$'), '');
  }

  static bool ehNuvem(String host) {
    final h = host.toLowerCase();
    for (final dominio in hostsNuvem) {
      if (h == dominio || h.endsWith('.$dominio')) return true;
    }
    return false;
  }

  static bool ehNuvemUrl(String url) {
    final uri = Uri.tryParse(normalize(url));
    if (uri == null || uri.host.isEmpty) return false;
    return ehNuvem(uri.host);
  }

  /// Host público (túnel/domínio) — nunca mistura com candidatos locais.
  static bool ehPublicaUrl(String url) {
    final uri = Uri.tryParse(normalize(url));
    if (uri == null || uri.host.isEmpty) return false;
    return ehNuvem(uri.host) || !_ehLocal(uri.host);
  }

  /// Só a URL do túnel/pública. Localhost/emulador não entram na lista.
  static List<String> candidatosProva({
    required String atual,
    String? preferida,
    List<String> locais = const [
      'http://10.0.2.2:8000',
      'http://127.0.0.1:8000',
      'http://localhost:8000',
    ],
  }) {
    final pedida = (preferida ?? '').trim();
    final base = pedida.isNotEmpty ? normalize(pedida) : normalize(atual);
    if (base.isEmpty) return locais.map(normalize).toList();
    if (ehPublicaUrl(base)) return [base];

    final lista = <String>[base];
    for (final local in locais) {
      final n = normalize(local);
      if (n.isNotEmpty && !lista.contains(n)) lista.add(n);
    }
    return lista;
  }

  /// Se o teste falhar, a URL ativa volta a ser a anterior.
  static String aposTeste({
    required String anterior,
    required String tentada,
    required bool respondeu,
  }) {
    if (!respondeu) return normalize(anterior);
    final nova = normalize(tentada);
    return nova.isEmpty ? normalize(anterior) : nova;
  }

  static String _esquemaPara(String host) {
    if (ehNuvem(host) || !_ehLocal(host)) return 'https';
    return 'http';
  }

  static bool _ehLocal(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '127.0.0.1' || h == '10.0.2.2' || h == '0.0.0.0') {
      return true;
    }
    final partes = h.split('.');
    if (partes.length != 4) return false;
    final a = int.tryParse(partes[0]);
    final b = int.tryParse(partes[1]);
    if (a == null || b == null) return false;
    if (a == 10 || a == 127) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static String _hostDe(String semEsquema) {
    final semPath = semEsquema.split('/').first;
    return semPath.split(':').first;
  }
}
