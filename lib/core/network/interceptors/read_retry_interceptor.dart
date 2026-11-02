import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../utils/turkish_text.dart';
import '../app_failure.dart';

/// Okuma (GET) yeniden deneme kuralı.
///
/// - 429 ve 503: sunucunun `Retry-After`'ı kadar beklenip en çok [maxRateLimitedRetries] kez yeniden
///   denenir; bekleme [maxWait]'ten uzunsa denenmez (ekran önbellekteki veriyi ya da "Tekrar dene"yi
///   gösterir). Başlık yoksa 1 s, 2 s.
/// - 502 / 504 ve bağlantı / zaman aşımı hataları: bir kez, kısa ve rastgele bir beklemeden sonra.
/// - Yalnızca GET: yazmalar asla burada tekrarlanmaz (onların kendi idempotent kuralları var).
class ReadRetryPolicy {
  const ReadRetryPolicy({
    this.maxRateLimitedRetries = 2,
    this.maxTransientRetries = 1,
    this.maxWait = const Duration(seconds: 8),
    this.transientDelay = const Duration(milliseconds: 600),
    this.jitter = const Duration(milliseconds: 600),
  });

  /// Kapalı (testler).
  static const none = ReadRetryPolicy(
    maxRateLimitedRetries: 0,
    maxTransientRetries: 0,
  );

  final int maxRateLimitedRetries;
  final int maxTransientRetries;
  final Duration maxWait;
  final Duration transientDelay;
  final Duration jitter;

  /// [attempt] (0 tabanlı) denemesinden sonra bekleme; yeniden denenmeyecekse null.
  Duration? delayFor(DioException e, int attempt, {Random? random}) {
    final status = e.response?.statusCode;
    if (status == 429 || status == 503) {
      if (attempt >= maxRateLimitedRetries) return null;
      final f = AppFailure.from(e);
      // Kalıcı 503 (ör. asistan kapalı, bakım kodu) beklemekle düzelmez.
      if (status == 503 && f.code != null && f.code != 'rate_limited') {
        return null;
      }
      final wait = f.retryAfter ?? Duration(seconds: attempt + 1);
      if (wait > maxWait) return null;
      return wait;
    }
    final transient =
        status == 502 ||
        status == 504 ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
    if (!transient || attempt >= maxTransientRetries) return null;
    final r = random ?? Random();
    return transientDelay +
        Duration(milliseconds: r.nextInt(jitter.inMilliseconds + 1));
  }
}

/// İstek ayarı: bu GET kaçıncı kez deneniyor.
const _attemptKey = 'akn.readRetry';

/// GET'leri [policy]'ye göre yeniden dener (Dio zincirinin tamamıyla: yetki başlığı yeniden eklenir).
/// API yığını kapanınca ([close]: uygulama kapandı, demo oturumu açıldı / bitti) bekleyen denemeler
/// iptal edilir; kapanmış Dio'ya yeniden istek gitmez.
class ReadRetryInterceptor extends Interceptor {
  ReadRetryInterceptor({required this.dio, required this.policy});

  final Dio dio;
  final ReadRetryPolicy policy;

  bool _closed = false;
  final Set<({Timer timer, Completer<bool> done})> _waits = {};

  /// Bekleyen denemeleri iptal eder; sonrasında yeniden deneme yapılmaz.
  void close() {
    _closed = true;
    for (final w in [..._waits]) {
      w.timer.cancel();
      if (!w.done.isCompleted) w.done.complete(false);
    }
    _waits.clear();
  }

  /// [d] kadar bekler; [close] ile kesilirse false.
  Future<bool> _wait(Duration d) {
    final done = Completer<bool>();
    late final ({Timer timer, Completer<bool> done}) entry;
    entry = (
      timer: Timer(d, () {
        _waits.remove(entry);
        if (!done.isCompleted) done.complete(true);
      }),
      done: done,
    );
    _waits.add(entry);
    return done.future;
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final o = err.requestOptions;
    if (_closed ||
        o.method.asciiUpper != 'GET' ||
        err.type == DioExceptionType.cancel ||
        (o.cancelToken?.isCancelled ?? false)) {
      handler.next(err);
      return;
    }
    final attempt = (o.extra[_attemptKey] as int?) ?? 0;
    final delay = policy.delayFor(err, attempt);
    if (delay == null) {
      handler.next(err);
      return;
    }
    final waited = await _wait(delay);
    if (!waited || _closed || (o.cancelToken?.isCancelled ?? false)) {
      handler.next(err);
      return;
    }
    try {
      final res = await dio.fetch<dynamic>(
        o.copyWith(extra: {...o.extra, _attemptKey: attempt + 1}),
      );
      handler.resolve(res);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
