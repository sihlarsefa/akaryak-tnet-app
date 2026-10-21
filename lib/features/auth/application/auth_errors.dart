import 'package:flutter/foundation.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/utils/turkish_text.dart';
import '../copy.dart';

/// Kimlik ekranlarında gösterilecek hata (spec C.7): ham yanıt asla gösterilmez; iş kuralı mesajı
/// sunucudan olduğu gibi, sunucu hatası "Beklenmeyen bir hata" + destek kodu.
@immutable
class AuthErrorInfo {
  const AuthErrorInfo({
    required this.message,
    this.title,
    this.supportCode,
    this.fieldErrors = const {},
  });

  final String message;
  final String? title;

  /// İz kimliğinin ilk 8 karakteri ("Destek kodu: 1a2b3c4d", dokununca kopyalanır).
  final String? supportCode;

  /// Alan → ilk hata (camelCase anahtar, büyük/küçük harf duyarsız: [fieldError]).
  final Map<String, String> fieldErrors;

  String? fieldError(String field) {
    final f = field.asciiLower;
    for (final e in fieldErrors.entries) {
      if (e.key.asciiLower == f) return e.value;
    }
    return null;
  }
}

/// İz kimliğinin destek için kısa hâli.
String? shortTraceId(String? traceId) {
  final t = traceId?.replaceAll(RegExp(r'[^A-Za-z0-9]'), '') ?? '';
  if (t.isEmpty) return null;
  return t.length <= 8 ? t : t.substring(0, 8);
}

/// [failure] için ekran metni. [unauthorizedMessage] girişte 401'in anlamıdır (şifre hatalı).
AuthErrorInfo describeAuthFailure(
  AppFailure failure, {
  String? title,
  String unauthorizedMessage = 'Kullanıcı adı veya şifre hatalı.',
}) {
  switch (failure) {
    case OfflineFailure():
      return AuthErrorInfo(message: AuthCopy.offline, title: title);
    case TimeoutFailure():
      return AuthErrorInfo(message: AuthCopy.timeout, title: title);
    case UnauthorizedFailure():
      return AuthErrorInfo(
        message: failure.problem?.detail ?? unauthorizedMessage,
        title: title,
      );
    case ValidationFailure(:final fieldErrors):
      return AuthErrorInfo(
        message: failure.message,
        title: title,
        fieldErrors: {
          for (final e in fieldErrors.entries)
            if (e.value.isNotEmpty) e.key: e.value.first,
        },
      );
    case ServerFailure():
      // 503 + kod (sms_not_configured, service_unavailable): sunucunun Türkçe açıklaması.
      final detail = failure.problem?.detail;
      if (failure.statusCode == 503 &&
          failure.problem?.code != null &&
          detail != null) {
        return AuthErrorInfo(message: detail, title: title);
      }
      return AuthErrorInfo(
        message: AuthCopy.server,
        title: title,
        supportCode: shortTraceId(failure.traceId),
      );
    case UnknownFailure():
      return AuthErrorInfo(
        message: failure.message,
        title: title,
        supportCode: shortTraceId(failure.traceId),
      );
    case ForbiddenFailure() ||
        NotFoundFailure() ||
        ConflictFailure() ||
        BusinessFailure() ||
        RateLimitedFailure() ||
        UpdateRequiredFailure():
      return AuthErrorInfo(message: failure.message, title: title);
  }
}
