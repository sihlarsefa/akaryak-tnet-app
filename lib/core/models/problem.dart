import 'package:flutter/foundation.dart';

import 'json.dart';

/// RFC 7807 ProblemDetails + `code`, `traceId`, `errors` (spec B.2).
///
/// Kodlar: `validation`, `business_rule`, `unauthorized`, `token_expired`, `session_revoked`,
/// `forbidden`, `not_found`, `concurrency_conflict`, `already_reported`, `idempotency_in_progress`,
/// `app_update_required`, `rate_limited`, `server_error`, `assistant_disabled`.
@immutable
class Problem {
  const Problem({
    this.type,
    this.title,
    this.status,
    this.detail,
    this.code,
    this.traceId,
    this.errors = const {},
    this.retryAfterSeconds,
  });

  /// JSON ProblemDetails değilse null. Eski uç noktaların `{message}` / `{error}` gövdeleri de okunur.
  static Problem? tryParse(Object? body, {int? status}) {
    if (body is! Map) {
      return null;
    }
    final r = JsonReader.of(body);
    final errors = <String, List<String>>{};
    final rawErrors = r['errors'];
    if (rawErrors is Map) {
      rawErrors.forEach((k, v) {
        if (v is List) {
          errors['$k'] = [for (final e in v) '$e'];
        } else if (v != null) {
          errors['$k'] = ['$v'];
        }
      });
    }
    final detail =
        r.nonEmpty('detail') ?? r.nonEmpty('message') ?? r.nonEmpty('error');
    final p = Problem(
      type: r.nonEmpty('type'),
      title: r.nonEmpty('title'),
      status: r.intOrNull('status') ?? status,
      detail: detail,
      code: r.nonEmpty('code'),
      traceId: r.nonEmpty('traceId'),
      errors: errors,
      retryAfterSeconds: r.intOrNull('retryAfter'),
    );
    final empty =
        p.title == null &&
        p.detail == null &&
        p.code == null &&
        p.errors.isEmpty;
    return empty ? null : p;
  }

  final String? type;
  final String? title;
  final int? status;

  /// Türkçe kullanıcı mesajı (ServiceException / business_rule).
  final String? detail;
  final String? code;
  final String? traceId;

  /// Alan → mesajlar (validation).
  final Map<String, List<String>> errors;

  /// 429 gövdesindeki `retryAfter` (saniye). `Retry-After` başlığı okunamazsa bu kullanılır.
  final int? retryAfterSeconds;

  /// İlk alan hatası (form üstü özet için).
  String? get firstError {
    for (final list in errors.values) {
      if (list.isNotEmpty) return list.first;
    }
    return null;
  }

  @override
  String toString() => 'Problem($status, $code, $detail)';
}
