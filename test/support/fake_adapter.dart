// Ağsız Dio adaptörü (F2GO `test/cuzdan/sahte_adaptor.dart` uyarlaması): istekleri kaydeder, sıradaki
// yanıtı döner. Tek tek yanıt sırası gereken birim testleri içindir; uçtan uca akışlar için
// `FakeServer.forTests()` + `FakeApiAdapter` kullanın.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Kaydedilen istek.
class RecordedRequest {
  RecordedRequest(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;

  /// JSON çözülmüş gövde ya da null.
  final Object? body;

  String? header(String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name.toLowerCase()) return e.value?.toString();
    }
    return null;
  }

  String get path => uri.path;
}

typedef QueuedResponse =
    FutureOr<ResponseBody> Function(RequestOptions request);

/// Sıralı yanıtlar veren adaptör.
class QueueAdapter implements HttpClientAdapter {
  final List<RecordedRequest> requests = [];
  final List<QueuedResponse> _queue = [];

  /// Yol eşleşmesine göre yanıt üreten yedek (sıra boşken).
  QueuedResponse? fallback;

  void enqueue(QueuedResponse response) => _queue.add(response);

  void json(
    int status,
    Object? body, {
    Map<String, List<String>> headers = const {},
  }) => enqueue(
    (_) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        ...headers,
      },
    ),
  );

  void problem(
    int status,
    String code,
    String detail, {
    Map<String, List<String>> headers = const {},
  }) => json(status, {
    'title': detail,
    'status': status,
    'detail': detail,
    'code': code,
    'traceId': 'test-trace',
  }, headers: headers);

  void empty(int status) => enqueue((_) => ResponseBody.fromString('', status));

  void connectionError() => enqueue(
    (o) =>
        throw DioException.connectionError(requestOptions: o, reason: 'test'),
  );

  void timeout() => enqueue(
    (o) => throw DioException.receiveTimeout(
      timeout: const Duration(seconds: 1),
      requestOptions: o,
    ),
  );

  /// Testin serbest bırakacağı bekletilmiş JSON yanıtı (yarış durumları).
  Completer<void> held(int status, Object? body) {
    final release = Completer<void>();
    enqueue((_) async {
      await release.future;
      return ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      );
    });
    return release;
  }

  int get remaining => _queue.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      try {
        body = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        body = text;
      }
    }
    requests.add(
      RecordedRequest(
        options.method,
        options.uri,
        Map.of(options.headers),
        body,
      ),
    );
    if (_queue.isEmpty) {
      final f = fallback;
      if (f != null) return f(options);
      throw StateError('Beklenmeyen istek: ${options.method} ${options.uri}');
    }
    return _queue.removeAt(0)(options);
  }

  @override
  void close({bool force = false}) {}
}
