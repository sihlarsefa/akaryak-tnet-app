import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/problem.dart';
import '../utils/turkish_text.dart';

/// Uygulamanın tek hata tipi (spec C.4). Arayüz yalnızca [message] gösterir; ham yanıt asla gösterilmez.
///
/// Sunucu ProblemDetails `code` alanından eşlenir ([AppFailure.from]). Özellik kodları
/// `try { … } on AppFailure catch (f) { … }` ile yakalar; `switch (f) { OfflineFailure() => … }` ile
/// türüne göre davranır.
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.problem, this.statusCode});

  /// Türkçe kullanıcı mesajı.
  final String message;

  /// Sunucunun ProblemDetails gövdesi (varsa).
  final Problem? problem;
  final int? statusCode;

  /// ProblemDetails `code` (ör. `concurrency_conflict`).
  String? get code => problem?.code;

  /// Destek için iz kimliği.
  String? get traceId => problem?.traceId;

  /// Sonuç belirsiz: istek sunucuda işlenmiş olabilir (zaman aşımı, kopan bağlantı, 5xx, işlem sürüyor).
  /// Aynı Idempotency-Key ile tekrar denenmelidir.
  bool get isUncertain => false;

  /// Bir süre sonra tekrar denemek anlamlı (çevrimdışı, zaman aşımı, 5xx, 429, işlem sürüyor).
  bool get isTransient => false;

  /// Sunucunun istediği bekleme (`Retry-After`; 429 ve 503). Yoksa null.
  Duration? get retryAfter => null;

  /// Herhangi bir hatayı [AppFailure]'a çevirir.
  static AppFailure from(Object error) {
    if (error is AppFailure) return error;
    if (error is DioException) return _fromDio(error);
    if (error is SocketException ||
        error is HandshakeException ||
        error is HttpException) {
      return const OfflineFailure();
    }
    if (error is TimeoutException) return const TimeoutFailure();
    if (error is FormatException) {
      return const UnknownFailure('Sunucudan beklenmeyen bir yanıt alındı.');
    }
    return const UnknownFailure();
  }

  static AppFailure _fromDio(DioException e) {
    final inner = e.error;
    if (inner is AppFailure) return inner;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const TimeoutFailure();
      case DioExceptionType.connectionError:
        return const OfflineFailure();
      case DioExceptionType.cancel:
        return const UnknownFailure.cancelled();
      case DioExceptionType.badCertificate:
        return const OfflineFailure('Sunucuyla güvenli bağlantı kurulamadı.');
      case DioExceptionType.badResponse:
        final res = e.response;
        return fromResponse(
          res?.statusCode ?? 0,
          res?.data,
          retryAfterHeader: res?.headers.value('retry-after'),
        );
      case DioExceptionType.unknown:
        if (inner is SocketException ||
            inner is HandshakeException ||
            inner is HttpException) {
          return const OfflineFailure();
        }
        if (inner is TimeoutException) return const TimeoutFailure();
        if (inner is FormatException) {
          return const UnknownFailure(
            'Sunucudan beklenmeyen bir yanıt alındı.',
          );
        }
        return const UnknownFailure();
    }
  }

  /// HTTP durum + gövdeden eşleme (spec B.2 kodları).
  static AppFailure fromResponse(
    int status,
    Object? body, {
    String? retryAfterHeader,
  }) {
    final p = Problem.tryParse(body, status: status);
    final detail = p?.detail;
    final code = p?.code;
    switch (status) {
      case 400:
      case 422:
        if (code == 'validation' ||
            (code == null && (p?.errors.isNotEmpty ?? false))) {
          return ValidationFailure(
            p?.errors ?? const {},
            message: detail ?? p?.firstError,
            problem: p,
          );
        }
        return BusinessFailure(
          detail ?? p?.firstError ?? 'İşlem tamamlanamadı.',
          problem: p,
          statusCode: status,
        );
      case 401:
        return UnauthorizedFailure(
          code ?? 'unauthorized',
          message: detail,
          problem: p,
        );
      case 403:
        return ForbiddenFailure(message: detail, problem: p);
      case 404:
        return NotFoundFailure(message: detail, problem: p);
      case 409:
        return ConflictFailure(
          code ?? 'concurrency_conflict',
          message: detail,
          problem: p,
        );
      case 426:
        return UpdateRequiredFailure(message: detail, problem: p);
      case 429:
        return RateLimitedFailure(
          _retryAfter(retryAfterHeader, p),
          message: detail,
          problem: p,
        );
      default:
        if (status >= 500) {
          return ServerFailure(
            message: detail,
            problem: p,
            statusCode: status,
            retryAfter: _retryAfter(retryAfterHeader, p),
          );
        }
        if (status >= 400) {
          return BusinessFailure(
            detail ?? 'İşlem tamamlanamadı.',
            problem: p,
            statusCode: status,
          );
        }
        return const UnknownFailure();
    }
  }

  /// `Retry-After` başlığı (saniye); yoksa ProblemDetails gövdesindeki `retryAfter`.
  static Duration? _retryAfter(String? header, Problem? p) {
    final s = int.tryParse(header?.trim() ?? '') ?? p?.retryAfterSeconds;
    return s == null || s < 0 ? null : Duration(seconds: s);
  }

  @override
  String toString() =>
      '$runtimeType(${statusCode ?? ''} ${code ?? ''}: $message)';
}

/// Bağlantı yok.
final class OfflineFailure extends AppFailure {
  const OfflineFailure([
    super.message =
        'İnternet bağlantısı yok. Bağlantınızı kontrol edip tekrar deneyin.',
  ]);

  @override
  bool get isUncertain => true;
  @override
  bool get isTransient => true;
}

/// Zaman aşımı.
final class TimeoutFailure extends AppFailure {
  const TimeoutFailure([
    super.message = 'Sunucu zamanında yanıt vermedi. Tekrar deneyin.',
  ]);

  @override
  bool get isUncertain => true;
  @override
  bool get isTransient => true;
}

/// 401: `unauthorized`, `token_expired`, `session_revoked` (ya da giriş ekranında hatalı şifre).
final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure(this.reason, {String? message, super.problem})
    : super(
        message ?? 'Oturumunuz sona erdi. Yeniden giriş yapın.',
        statusCode: 401,
      );

  final String reason;

  bool get isTokenExpired => reason == 'token_expired';
  bool get isSessionRevoked => reason == 'session_revoked';
}

/// 403.
final class ForbiddenFailure extends AppFailure {
  const ForbiddenFailure({String? message, super.problem})
    : super(message ?? 'Bu işlem için yetkiniz yok.', statusCode: 403);
}

/// 404.
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure({String? message, super.problem})
    : super(message ?? 'Kayıt bulunamadı ya da kaldırılmış.', statusCode: 404);
}

/// 409: `concurrency_conflict`, `already_reported`, `idempotency_in_progress`.
final class ConflictFailure extends AppFailure {
  ConflictFailure(this.conflictCode, {String? message, super.problem})
    : super(message ?? _defaultMessage(conflictCode), statusCode: 409);

  final String conflictCode;

  static String _defaultMessage(String code) => switch (code) {
    'idempotency_in_progress' =>
      'İşleminiz hâlâ sürüyor. Birkaç saniye sonra tekrar deneyin.',
    'already_reported' =>
      'Bu teslimat daha önce farklı bilgilerle bildirilmiş.',
    _ =>
      'Kayıt siz bakarken değişti. Güncel hâli yüklendi; kontrol edip tekrar deneyin.',
  };

  bool get isInProgress => conflictCode == 'idempotency_in_progress';
  bool get isConcurrency => conflictCode == 'concurrency_conflict';

  @override
  bool get isUncertain => isInProgress;
  @override
  bool get isTransient => isInProgress;
}

/// 400 `validation`: alan → mesajlar.
final class ValidationFailure extends AppFailure {
  const ValidationFailure(this.fieldErrors, {String? message, super.problem})
    : super(message ?? 'İşaretli alanları kontrol edin.', statusCode: 400);

  final Map<String, List<String>> fieldErrors;

  /// Alanın ilk hatası (anahtar büyük/küçük harf duyarsız; `Lines[0].QuantityLiters` gibi yollar dahil).
  String? errorFor(String field) {
    final f = field.asciiLower;
    for (final e in fieldErrors.entries) {
      if (e.key.asciiLower == f && e.value.isNotEmpty) return e.value.first;
    }
    return null;
  }

  /// Alanın tüm hataları alt alta (tekrarsız; anahtar büyük/küçük harf duyarsız); yoksa null.
  String? errorsFor(String field) {
    final f = field.asciiLower;
    final lines = <String>{
      for (final e in fieldErrors.entries)
        if (e.key.asciiLower == f) ...e.value,
    };
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// [fields] dışındaki alanların hataları alt alta (tekrarsız); yoksa null.
  String? errorsExcept(Iterable<String> fields) {
    final skip = {for (final f in fields) f.asciiLower};
    final lines = <String>{
      for (final e in fieldErrors.entries)
        if (!skip.contains(e.key.asciiLower)) ...e.value,
    };
    return lines.isEmpty ? null : lines.join('\n');
  }
}

/// 400 `business_rule` (ServiceException): sunucunun Türkçe mesajı.
final class BusinessFailure extends AppFailure {
  const BusinessFailure(super.message, {super.problem, super.statusCode});
}

/// 429.
final class RateLimitedFailure extends AppFailure {
  RateLimitedFailure(this.wait, {String? message, super.problem})
    : super(
        message ??
            (wait == null
                ? 'Çok fazla deneme yapıldı. Biraz bekleyip tekrar deneyin.'
                : 'Çok fazla deneme yapıldı. ${wait.inSeconds} saniye sonra tekrar deneyin.'),
        statusCode: 429,
      );

  /// `Retry-After` (saniye).
  final Duration? wait;

  @override
  Duration? get retryAfter => wait;

  @override
  bool get isTransient => true;
}

/// 426: uygulama güncellenmeli.
final class UpdateRequiredFailure extends AppFailure {
  const UpdateRequiredFailure({String? message, super.problem})
    : super(
        message ??
            'Bu sürüm artık desteklenmiyor. Devam etmek için uygulamayı güncelleyin.',
        statusCode: 426,
      );
}

/// 5xx (503 `assistant_disabled` dahil; mesaj sunucudan gelir).
final class ServerFailure extends AppFailure {
  const ServerFailure({
    String? message,
    super.problem,
    super.statusCode,
    Duration? retryAfter,
  }) : _retryAfter = retryAfter,
       super(
         message ??
             'Sunucu isteği tamamlayamadı. Birkaç dakika sonra tekrar deneyin.',
       );

  final Duration? _retryAfter;

  @override
  Duration? get retryAfter => _retryAfter;

  @override
  bool get isUncertain => true;
  @override
  bool get isTransient => statusCode != 503 || problem?.code == null;
}

/// Sınıflandırılamayan hata.
final class UnknownFailure extends AppFailure {
  const UnknownFailure([super.message = 'İşlem tamamlanamadı. Tekrar deneyin.'])
    : cancelled = false;

  /// İstek bilerek iptal edildi.
  const UnknownFailure.cancelled()
    : cancelled = true,
      super('İşlem iptal edildi.');

  /// İstek bilerek iptal edildi (ekran kapandı); kullanıcıya gösterilmez.
  final bool cancelled;

  @override
  bool get isUncertain => !cancelled;
}
