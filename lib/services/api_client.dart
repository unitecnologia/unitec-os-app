import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:unitec_os_app/config/api_config.dart';
import 'package:unitec_os_app/session/app_session.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

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
  }) {
    return _request('GET', path, auth: auth, device: device);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool device = true,
  }) {
    return _request('PUT', path, body: body, auth: auth, device: device);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    bool device = true,
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
      final res = await req.close().timeout(const Duration(seconds: 20));
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
