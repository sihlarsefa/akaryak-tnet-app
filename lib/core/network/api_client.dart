import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../utils/log.dart';
import 'app_failure.dart';
import 'interceptors/app_headers_interceptor.dart';
import 'interceptors/auth_interceptor.dart';
import 'response_cache.dart';

export 'response_cache.dart' show CachedResponse;

/// Yanıt gövdesini modele çeviren fonksiyon (`MeAccess.fromJson` gibi).
typedef JsonParser<T> = T Function(Object? json);

/// Mobil API v1 istemcisi (spec C.4). Tek Dio üzerinde çalışır; yollar `api/v1/` köküne göredir
/// (`client.get('me/access', parse: MeAccess.fromJson)`).
///
/// Her hata [AppFailure] olarak fırlatılır; başka tip istisna dışarı çıkmaz.
/// `Idempotency-Key` gereken POST'lar (spec B.2) [idempotencyKey] verir; anahtar kullanıcı niyeti başına
/// `IdempotencyLedger` ile tutulur.
///
/// Hız (2026-11-02, "veriler çok yavaş"):
/// - **Önce önbellek**: `get(cache: true)` başarılı yanıtı kullanıcıya ve kipe özel [ResponseCache]'e
///   yazar; ekran açılışta [peek] ile son yanıtı hemen gösterir, sunucudan arka planda tazeler.
/// - **Uçuştaki okuma tek**: aynı kullanıcı, yol ve sorguyla aynı anda istenen GET'ler tek isteği paylaşır
///   ([dedupeReads]; ör. ana sayfa açılırken iki sağlayıcının istediği `bayi/orders/counts`).
/// - **Yazma eskitir**: başarılı (ya da sonucu belirsiz) POST / PUT / DELETE, etkilediği okumaların
///   önbellek kayıtlarını hemen siler ([WriteInvalidation]); o ailelerde yazmadan önce başlamış uçuştaki
///   okumalar da artık paylaşılmaz (yazmadan sonra istenen liste yeni siparişi içerir).
class ApiClient {
  ApiClient(this.dio, {this.responses, this.dedupeReads = false});

  final Dio dio;

  /// Yanıt önbelleği (uygulamada her zaman var; birim testlerinde çoğunlukla yok).
  final ResponseCache? responses;

  /// Aynı anda istenen aynı GET'ler tek isteği paylaşır.
  final bool dedupeReads;

  final Map<String, _Flight> _inFlight = {};

  /// Yükleme zaman aşımı (spec C.4: 120 s).
  static const uploadTimeout = Duration(seconds: 120);

  /// [cache]: başarılı yanıt önbelleğe yazılır (ilk sayfalar, varsayılan süzgeçler, ayrıntılar; arama
  /// sorguları değil). Önbellekten okumak için [peek].
  Future<T> get<T>(
    String path, {
    required JsonParser<T> parse,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    bool anonymous = false,
    bool quiet403 = false,
    bool cache = false,
  }) async {
    final clean = _clean(query);
    final cacheUser = cache && !anonymous ? responses?.currentUser : null;
    final flight = _read(
      path,
      clean,
      cancelToken: cancelToken,
      anonymous: anonymous,
      quiet403: quiet403,
    );
    final raw = await flight.data;
    final T value;
    try {
      value = parse(raw);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw const UnknownFailure('Sunucudan beklenmeyen bir yanıt alındı.');
    }
    final store = responses;
    if (store != null && cacheUser != null && cacheUser.isNotEmpty) {
      try {
        await store.write(
          path,
          clean,
          raw,
          uid: cacheUser,
          // Paylaşılan okumada isteğin gerçek başlangıcı: bir yazmadan önce başlamış yanıt yazılmaz.
          requestedAt: flight.startedAt,
        );
      } catch (e) {
        AppLog.debug('Yanıt önbelleğe yazılamadı ($path): ${e.runtimeType}');
      }
    }
    return value;
  }

  /// Oturumdaki kullanıcının bu okumaya son yanıtı (önbellekten; ağa çıkmaz). Yoksa, süresi geçtiyse ya
  /// da artık çözülemiyorsa (eski sürümün biçimi) null.
  Future<CachedResponse<T>?> peek<T>(
    String path, {
    required JsonParser<T> parse,
    Map<String, dynamic>? query,
  }) async {
    final store = responses;
    if (store == null) return null;
    final clean = _clean(query);
    try {
      final hit = await store.read(path, clean);
      if (hit == null) return null;
      return CachedResponse(parse(hit.value), storedAt: hit.storedAt);
    } catch (e) {
      AppLog.debug('Önbellekteki yanıt okunamadı ($path): ${e.runtimeType}');
      try {
        await store.remove(path, clean);
      } catch (_) {}
      return null;
    }
  }

  /// [prefixes] ile başlayan yolların önbellek kayıtlarını siler (oturumdaki kullanıcı); bu yollarda
  /// uçuştaki okumalar da artık paylaşılmaz (sonraki okuma yeni istek atar).
  Future<void> invalidate(Iterable<String> prefixes) async {
    final list = prefixes.toList();
    _forgetInFlight(list);
    try {
      await responses?.invalidate(list);
    } catch (e) {
      AppLog.debug('Önbellek geçersiz kılınamadı: ${e.runtimeType}');
    }
  }

  Future<T> post<T>(
    String path, {
    Object? body,
    JsonParser<T>? parse,
    Map<String, dynamic>? query,
    String? idempotencyKey,
    CancelToken? cancelToken,
    bool anonymous = false,
    bool quiet403 = false,
  }) => _write(
    'POST',
    path,
    () => dio.post<Object?>(
      path,
      data: body,
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: _options(
        anonymous: anonymous,
        quiet403: quiet403,
        idempotencyKey: idempotencyKey,
      ),
    ),
    parse,
  );

  Future<T> put<T>(
    String path, {
    Object? body,
    JsonParser<T>? parse,
    Map<String, dynamic>? query,
    String? idempotencyKey,
    CancelToken? cancelToken,
  }) => _write(
    'PUT',
    path,
    () => dio.put<Object?>(
      path,
      data: body,
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: _options(idempotencyKey: idempotencyKey),
    ),
    parse,
  );

  Future<T> delete<T>(
    String path, {
    Object? body,
    JsonParser<T>? parse,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) => _write(
    'DELETE',
    path,
    () => dio.delete<Object?>(
      path,
      data: body,
      queryParameters: _clean(query),
      cancelToken: cancelToken,
      options: _options(),
    ),
    parse,
  );

  /// Çok parçalı yükleme (ilerleme ile). Yenileme gerekirse form klonlanıp bir kez tekrar gönderilir.
  Future<T> upload<T>(
    String path, {
    required FormData form,
    required JsonParser<T> parse,
    String? idempotencyKey,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) => _write(
    'POST',
    path,
    () => dio.post<Object?>(
      path,
      data: form,
      cancelToken: cancelToken,
      onSendProgress: onProgress,
      options: _options(
        idempotencyKey: idempotencyKey,
      ).copyWith(sendTimeout: uploadTimeout, receiveTimeout: uploadTimeout),
    ),
    parse,
  );

  /// İkili içerik (PDF, görsel).
  Future<Uint8List> bytes(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        cancelToken: cancelToken,
        options: _options().copyWith(
          responseType: ResponseType.bytes,
          receiveTimeout: uploadTimeout,
        ),
      );
      final data = res.data;
      return data is Uint8List ? data : Uint8List.fromList(data ?? const []);
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Ham GET (hata [AppFailure]). [dedupeReads] açıkken aynı anahtarla uçuştaki istek paylaşılır;
  /// iptal belirteci verilen istek paylaşılmaz (birinin iptali ötekini kesmesin). Dönen uçuşun
  /// [_Flight.startedAt]'i paylaşılan isteğin gerçek başlangıcıdır.
  _Flight _read(
    String path,
    Map<String, dynamic>? query, {
    CancelToken? cancelToken,
    required bool anonymous,
    required bool quiet403,
  }) {
    final canonical = ResponseCache.canonical(path, query);
    final startedAt = DateTime.now().toUtc();
    Future<Object?> fetch() async {
      try {
        final res = await dio.get<Object?>(
          path,
          queryParameters: query,
          cancelToken: cancelToken,
          options: _options(anonymous: anonymous, quiet403: quiet403),
        );
        return res.data;
      } catch (e) {
        throw AppFailure.from(e);
      }
    }

    if (!dedupeReads || cancelToken != null) {
      return _Flight(canonical, startedAt, fetch());
    }
    final scope = anonymous ? '-' : (responses?.currentUser ?? '?');
    final key = '$scope|${quiet403 ? 'q' : ''}|$canonical';
    final running = _inFlight[key];
    if (running != null) return running;
    final flight = _Flight(canonical, startedAt, fetch());
    _inFlight[key] = flight;
    unawaited(
      flight.data.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_inFlight[key], flight)) _inFlight.remove(key);
      }),
    );
    return flight;
  }

  /// Yazma: sonuç başarılı, belirsiz (zaman aşımı, 5xx), çakışma (veri değişmiş) ya da iş kuralıysa
  /// (400; ör. sunucu siparişi finans onayına alıp teklifi kaydetmedi: durum yine değişti) etkilenen
  /// okumalar önbellekten silinir. Doğrulama, yetki ve 429 hataları bir şey değiştirmez.
  Future<T> _write<T>(
    String method,
    String path,
    Future<Response<Object?>> Function() call,
    JsonParser<T>? parse,
  ) async {
    try {
      final result = await _send(call, parse);
      await _afterWrite(method, path);
      return result;
    } on AppFailure catch (f) {
      if (f.isUncertain || f is ConflictFailure || f is BusinessFailure) {
        await _afterWrite(method, path);
      }
      rethrow;
    }
  }

  /// Yazmanın eskittiği aileler: yazmadan önce başlamış uçuştaki okumalar artık paylaşılmaz (yanıtları
  /// yazmayı içermeyebilir; ör. "Sipariş ver"den hemen sonra istenen Siparişlerim yeni isteğe gider) ve
  /// önbellek kayıtları silinir.
  Future<void> _afterWrite(String method, String path) async {
    final prefixes = WriteInvalidation.prefixesFor(method, path);
    if (prefixes.isEmpty) return;
    _forgetInFlight(prefixes);
    await responses?.noteWrite(method, path);
  }

  /// [prefixes] ile başlayan yolların uçuştaki okumalarını paylaşımdan çıkarır (istekler sürer; yalnızca
  /// sonraki okumalar onlara katılmaz).
  void _forgetInFlight(Iterable<String> prefixes) {
    if (_inFlight.isEmpty) return;
    final list = [
      for (final p in prefixes)
        if (p.isNotEmpty) p.startsWith('/') ? p.substring(1) : p,
    ];
    if (list.isEmpty) return;
    _inFlight.removeWhere((_, f) => list.any(f.canonical.startsWith));
  }

  Future<T> _send<T>(
    Future<Response<Object?>> Function() call,
    JsonParser<T>? parse,
  ) async {
    final Response<Object?> res;
    try {
      res = await call();
    } catch (e) {
      throw AppFailure.from(e);
    }
    try {
      if (parse == null) return null as T;
      return parse(res.data);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw const UnknownFailure('Sunucudan beklenmeyen bir yanıt alındı.');
    }
  }

  static Options _options({
    bool anonymous = false,
    bool quiet403 = false,
    String? idempotencyKey,
  }) => Options(
    headers: {AppHeadersInterceptor.idempotencyHeader: ?idempotencyKey},
    extra: {
      if (anonymous) ApiExtra.skipAuth: true,
      if (quiet403) ApiExtra.quiet403: true,
    },
  );

  /// Null ve boş değerleri sorgudan atar; listeler `a=1&a=2` olarak gider.
  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    query.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      if (v is Iterable && v.isEmpty) return;
      out[k] = v is Iterable
          ? v.map((e) => '$e').toList()
          : (v is bool ? '$v' : v);
    });
    return out;
  }
}

/// Uçuştaki bir GET: kanonik yolu (geçersiz kılma eşlemesi), başlangıç anı ve yanıtı.
class _Flight {
  _Flight(this.canonical, this.startedAt, this.data);

  /// `yol?sorgu` (baştaki `/` olmadan; [ResponseCache.canonical]).
  final String canonical;

  /// İsteğin ağa çıktığı an (UTC); paylaşan çağıranlar için de bu an geçerlidir.
  final DateTime startedAt;

  final Future<Object?> data;
}
