import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/json.dart';

/// Bekleyen işlemin durumu.
enum OutboxStatus {
  /// Sırada (ilk deneme ya da yeniden denemeye hazır).
  pending('Bekliyor'),

  /// Şu an gönderiliyor.
  sending('Gönderiliyor'),

  /// Geçici hata; [OutboxOp.nextAttemptAt] zamanında yeniden denenir.
  failed('Tekrar denenecek'),

  /// Sunucu reddetti (400/409/403/404): kullanıcının bakması gerekir.
  needsAttention('İlgilenmeniz gerekiyor'),

  /// Tamamlandı.
  done('Gönderildi');

  const OutboxStatus(this.label);
  final String label;

  static OutboxStatus parse(String? value) => values.firstWhere(
    (s) => s.name == value,
    orElse: () => OutboxStatus.pending,
  );

  /// Gönderilmeyi bekleyen (rozette sayılan) durumlar.
  bool get isWaiting => this == pending || this == sending || this == failed;
}

/// Çevrimdışı güvenli işlem (spec C.4 `outbox_ops`). Gövde ve Idempotency-Key kaydedilir; tekrar
/// denemeler aynı anahtarla gider, sunucu işlemi ikinci kez yapmaz.
@immutable
class OutboxOp {
  const OutboxOp({
    required this.id,
    required this.userId,
    required this.type,
    required this.payload,
    required this.idempotencyKey,
    this.dependsOn,
    this.files = const [],
    this.label,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
    this.result,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OutboxOp.fromRow(Map<String, Object?> r) => OutboxOp(
    id: r['id']! as String,
    userId: r['user_id']! as String,
    type: r['type']! as String,
    payload: JsonReader.asMap(jsonDecode(r['payload']! as String)),
    idempotencyKey: r['idempotency_key']! as String,
    dependsOn: r['depends_on'] as String?,
    files: r['files'] == null
        ? const []
        : List<String>.from(jsonDecode(r['files']! as String) as List),
    label: r['label'] as String?,
    status: OutboxStatus.parse(r['status'] as String?),
    attempts: (r['attempts'] as int?) ?? 0,
    nextAttemptAt: _ms(r['next_attempt_at']),
    lastError: r['last_error'] as String?,
    result: r['result'] == null
        ? null
        : JsonReader.asMap(jsonDecode(r['result']! as String)),
    createdAt: _ms(r['created_at']) ?? DateTime.now().toUtc(),
    updatedAt: _ms(r['updated_at']) ?? DateTime.now().toUtc(),
  );

  static DateTime? _ms(Object? v) =>
      v is int ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true) : null;

  final String id;
  final String userId;

  /// İşleyici türü: `driver.start`, `driver.deliver`, `field.saveDraft`, `lead.saveDraft`, `lead.upload`.
  final String type;
  final JsonMap payload;
  final String idempotencyKey;

  /// Önce tamamlanması gereken işlem (ör. `lead.upload` → `lead.saveDraft`).
  final String? dependsOn;

  /// Yerel dosya yolları (fotoğraf, imza); tamamlanınca silinir.
  final List<String> files;

  /// Kullanıcıya gösterilen ad ("SVK-00005002 teslimatı").
  final String? label;
  final OutboxStatus status;
  final int attempts;
  final DateTime? nextAttemptAt;

  /// Son hata (Türkçe, kullanıcıya gösterilebilir).
  final String? lastError;

  /// Tamamlanınca sunucu sonucu (bağımlı işlemler okur: ör. oluşan ön kayıt kimliği).
  final JsonMap? result;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool isDue(DateTime now) =>
      (status == OutboxStatus.pending || status == OutboxStatus.failed) &&
      (nextAttemptAt == null || !nextAttemptAt!.isAfter(now));

  OutboxOp copyWith({
    JsonMap? payload,
    OutboxStatus? status,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttempt = false,
    String? lastError,
    bool clearError = false,
    JsonMap? result,
    DateTime? updatedAt,
  }) => OutboxOp(
    id: id,
    userId: userId,
    type: type,
    payload: payload ?? this.payload,
    idempotencyKey: idempotencyKey,
    dependsOn: dependsOn,
    files: files,
    label: label,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: clearNextAttempt
        ? null
        : (nextAttemptAt ?? this.nextAttemptAt),
    lastError: clearError ? null : (lastError ?? this.lastError),
    result: result ?? this.result,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'payload': jsonEncode(payload),
    'idempotency_key': idempotencyKey,
    'depends_on': dependsOn,
    'files': files.isEmpty ? null : jsonEncode(files),
    'label': label,
    'status': status.name,
    'attempts': attempts,
    'next_attempt_at': nextAttemptAt?.millisecondsSinceEpoch,
    'last_error': lastError,
    'result': result == null ? null : jsonEncode(result),
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  @override
  String toString() => 'OutboxOp($type, $status, attempts: $attempts)';
}
