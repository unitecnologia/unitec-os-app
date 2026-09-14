import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:unitec_os_app/config/api_config.dart';
import 'package:unitec_os_app/session/app_session.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isAuth => statusCode == 401 || statusCode == 403;

  /// Rede, timeout, DNS ou túnel — o ERP não respondeu.
  bool get isOffline => statusCode == null;

  @override
  String toString() => message;
}

/// Cliente HTTP mínimo (dart:io) — sem bibliotecas extras.
class ApiClient {
  ApiClient({HttpClient? httpClient}) : _http = httpClient ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 15);

  final HttpClient _http;

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    bool device = true,
  }) {
    return _request('POST', path, body: body, auth: auth, device: device);
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    bool auth = true,
    bool device = true,
    Duration? timeout,
  }) {
    return _request('GET', path, auth: auth, device: device, timeout: timeout);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool device = true,
  }) {
    return _request('PUT', path, body: body, auth: auth, device: device);
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    String contentType = 'application/octet-stream',
    Map<String, String> fields = const {},
    bool auth = true,
    bool device = true,
  }) async {
    final base = ApiConfig.apiBase;
    final uri = Uri.parse('$base$path');
    final boundary = '----UnitecOS${DateTime.now().millisecondsSinceEpoch}';

    late HttpClientRequest req;
    try {
      req = await _http.postUrl(uri);
    } on SocketException catch (e) {
      throw ApiException(
        'Sem conexão com o ERP em ${ApiConfig.erpBaseUrl}.\n'
        '${e.message.isNotEmpty ? e.message : 'Host inacessível'}',
      );
    } on HttpException catch (e) {
      throw ApiException('Falha HTTP: ${e.message}');
    } on HandshakeException {
      throw ApiException('Falha TLS/SSL ao conectar em ${ApiConfig.erpBaseUrl}.');
    }

    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set('X-Requested-With', 'XMLHttpRequest');
    req.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );

    if (device) {
      req.headers.set('X-OS-Device', DeviceIdentity.uuid);
    }
    if (auth) {
      final token = AppSession.token;
      if (token == null || token.isEmpty) {
        throw ApiException('Sessão expirada. Faça login novamente.', statusCode: 401);
      }
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }

    final body = BytesBuilder();
    void writeString(String s) => body.add(utf8.encode(s));

    for (final entry in fields.entries) {
      writeString('--$boundary\r\n');
      writeString('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n');
      writeString('${entry.value}\r\n');
    }

    writeString('--$boundary\r\n');
    writeString(
      'Content-Disposition: form-data; name="$fieldName"; filename="$filename"\r\n',
    );
    writeString('Content-Type: $contentType\r\n\r\n');
    body.add(bytes);
    writeString('\r\n--$boundary--\r\n');

    req.add(body.takeBytes());

    try {
      final res = await req.close().timeout(const Duration(seconds: 60));
      final raw = await res.transform(utf8.decoder).join();
      Map<String, dynamic> json = {};
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        }
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return json;
      }

      final msg = _extractError(json) ?? 'Erro HTTP ${res.statusCode}';
      throw ApiException(
        msg,
        statusCode: res.statusCode,
        code: json['code']?.toString(),
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Tempo esgotado ao falar com ${ApiConfig.erpBaseUrl}.');
    } on SocketException catch (e) {
      throw ApiException(
        'Conexão interrompida com ${ApiConfig.erpBaseUrl}.\n${e.message}',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    bool device = true,
    Duration? timeout,
  }) async {
    final base = ApiConfig.apiBase;
    final uri = Uri.parse('$base$path');
    late HttpClientRequest req;

    try {
      req = switch (method) {
        'GET' => await _http.getUrl(uri),
        'PUT' => await _http.putUrl(uri),
        _ => await _http.postUrl(uri),
      };
    } on SocketException catch (e) {
      throw ApiException(
        'Sem conexão com o ERP em ${ApiConfig.erpBaseUrl}.\n'
        '${e.message.isNotEmpty ? e.message : 'Host inacessível'}',
      );
    } on HttpException catch (e) {
      throw ApiException('Falha HTTP: ${e.message}');
    } on HandshakeException {
      throw ApiException('Falha TLS/SSL ao conectar em ${ApiConfig.erpBaseUrl}.');
    }

    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.contentType = ContentType.json;
    req.headers.set('X-Requested-With', 'XMLHttpRequest');

    if (device) {
      req.headers.set('X-OS-Device', DeviceIdentity.uuid);
    }

    if (auth) {
      final token = AppSession.token;
      if (token == null || token.isEmpty) {
        throw ApiException('Sessão expirada. Faça login novamente.', statusCode: 401);
      }
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }

    if (body != null) {
      req.add(utf8.encode(jsonEncode(body)));
    }

    try {
      final res = await req.close().timeout(timeout ?? const Duration(seconds: 20));
      final raw = await res.transform(utf8.decoder).join();
      Map<String, dynamic> json = {};
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        }
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return json;
      }

      final msg = _extractError(json) ?? 'Erro HTTP ${res.statusCode}';
      throw ApiException(
        msg,
        statusCode: res.statusCode,
        code: json['code']?.toString(),
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Tempo esgotado ao falar com ${ApiConfig.erpBaseUrl}.');
    } on SocketException catch (e) {
      throw ApiException(
        'Conexão interrompida com ${ApiConfig.erpBaseUrl}.\n${e.message}',
      );
    }
  }

  String? _extractError(Map<String, dynamic> json) {
    final message = json['message'];
    if (message is String && message.trim().isNotEmpty) return message;

    final errors = json['errors'];
    if (errors is Map) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) {
          return value.first.toString();
        }
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return null;
  }
}
