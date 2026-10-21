import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Uygulama günlüğü. `print` kullanılmaz (lint hatası); bu sınıf yalnızca debug derlemede yazar ve
/// belirteçleri, şifreleri, doğrulama kodlarını maskeler. Sürüm derlemesinde hatalar [onError]
/// kancasına gider (ileride Crashlytics; bugün boş).
abstract final class AppLog {
  /// Sürüm derlemesinde yakalanan hatalar için kanca (ör. Crashlytics). Varsayılan: hiçbir şey.
  static void Function(Object error, StackTrace? stack, String context)?
  onError;

  static void debug(String message, {String name = 'akn'}) {
    if (kDebugMode) developer.log(redact(message), name: name);
  }

  static void warn(String message, {Object? error, String name = 'akn'}) {
    if (kDebugMode) {
      developer.log(
        redact(message),
        name: name,
        level: 900,
        error: error == null ? null : redact('$error'),
      );
    }
  }

  static void error(String context, Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      developer.log(
        redact(context),
        name: 'akn',
        level: 1000,
        error: redact('$error'),
        stackTrace: stack,
      );
    }
    try {
      onError?.call(error, stack, context);
    } catch (_) {
      // Günlük kancası asla uygulamayı düşürmez.
    }
  }

  static final _bearer = RegExp(
    r'Bearer\s+[A-Za-z0-9\-_.~+/=]+',
    caseSensitive: false,
  );
  static final _jsonSecret = RegExp(
    r'"(accessToken|refreshToken|password|code|pushToken|token|otp)"\s*:\s*"[^"]*"',
    caseSensitive: false,
  );
  static final _querySecret = RegExp(
    r'((?:token|code|password)=)[^&\s]+',
    caseSensitive: false,
  );

  /// Günlüğe yazılacak metindeki gizli değerleri maskeler.
  static String redact(String text) => text
      .replaceAll(_bearer, 'Bearer ***')
      .replaceAllMapped(_jsonSecret, (m) => '"${m[1]}":"***"')
      .replaceAllMapped(_querySecret, (m) => '${m[1]}***');
}
