import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../utils/turkish_text.dart';
import 'fake_server.dart';
import 'multipart.dart';

/// `API_MODE=fake`: Dio isteklerini ağ yerine [FakeServer]'a yönlendirir (spec C.4).
/// Gerçek ara katmanlar (başlıklar, belirteç, yenileme, hata eşleme) aynen çalışır.
class FakeApiAdapter implements HttpClientAdapter {
  FakeApiAdapter(this.server);

  final FakeServer server;

  /// Yolu `api/v1/` köküne göre verir (`/api/v1/orders/12` → `orders/12`).
  static String relativePath(Uri uri) {
    var p = uri.path;
    final i = p.indexOf('/api/v1/');
    if (i >= 0) {
      p = p.substring(i + '/api/v1/'.length);
    } else if (p.startsWith('/')) {
      p = p.substring(1);
    }
    return p.endsWith('/') ? p.substring(0, p.length - 1) : p;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = BytesBuilder(copy: false);
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.add(chunk);
      }
    }
    final raw = bytes.takeBytes();
    final headers = <String, String>{
      for (final e in options.headers.entries)
        if (e.value != null) e.key.asciiLower: '${e.value}',
    };
    final contentType = headers['content-type'] ?? options.contentType;

    Object? body;
    FakeMultipart? multipart;
    if (raw.isNotEmpty) {
      multipart = FakeMultipart.tryParse(contentType, raw);
      if (multipart == null) {
        final text = utf8.decode(raw, allowMalformed: true);
        try {
          body = jsonDecode(text);
        } catch (_) {
          body = text;
        }
      }
    }

    // Gecikme (iptal edilebilir).
    final latency = server.nextLatency();
    if (latency > Duration.zero) {
      final delay = Future<void>.delayed(latency);
      if (cancelFuture != null) {
        var cancelled = false;
        await Future.any([delay, cancelFuture.then((_) => cancelled = true)]);
        if (cancelled) {
          throw DioException.requestCancelled(
            requestOptions: options,
            reason: 'İptal edildi',
          );
        }
      } else {
        await delay;
      }
    }

    // Hata enjeksiyonu (dev menüsü).
    final mode = server.failureMode == FakeFailureMode.flaky
        ? (server.random.nextInt(5) == 0
              ? (server.random.nextBool()
                    ? FakeFailureMode.offline
                    : FakeFailureMode.serverError)
              : FakeFailureMode.none)
        : server.failureMode;
    switch (mode) {
      case FakeFailureMode.offline:
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Sahte: bağlantı yok',
        );
      case FakeFailureMode.timeout:
        throw DioException.receiveTimeout(
          timeout: options.receiveTimeout ?? const Duration(seconds: 30),
          requestOptions: options,
        );
      case FakeFailureMode.serverError:
        return _encode(
          FakeResponse.server('Sahte sunucu hatası (dev menüsü).'),
        );
      case FakeFailureMode.none:
      case FakeFailureMode.flaky:
        break;
    }

    final response = await server.handle(
      method: options.method.asciiUpper,
      path: relativePath(options.uri),
      uri: options.uri,
      body: body,
      multipart: multipart,
      headers: headers,
    );
    return _encode(response);
  }

  static ResponseBody _encode(FakeResponse r) {
    final headers = <String, List<String>>{
      for (final e in r.headers.entries) e.key: [e.value],
    };
    final body = r.body;
    if (body is FakeBinary) {
      return ResponseBody.fromBytes(
        body.bytes,
        r.status,
        headers: {
          ...headers,
          Headers.contentTypeHeader: [body.contentType],
          if (body.fileName != null)
            'content-disposition': ['inline; filename="${body.fileName}"'],
        },
      );
    }
    if (body == null || r.status == 204) {
      return ResponseBody.fromString('', r.status, headers: headers);
    }
    final isProblem = r.status >= 400;
    return ResponseBody.fromString(
      jsonEncode(body),
      r.status,
      headers: {
        ...headers,
        Headers.contentTypeHeader: [
          isProblem
              ? 'application/problem+json; charset=utf-8'
              : 'application/json; charset=utf-8',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
