/// Idempotency-Key üretimi ve kullanıcı niyeti başına saklanması (F2GO `cuzdan/idempotency.dart`).
///
/// Sunucu anahtarları kullanıcı başına 24 saat tutar (spec B.2). Aynı anahtar + farklı gövde → 400;
/// ilk istek sürerken aynı anahtar → 409 `idempotency_in_progress`; tamamlanmış istek → aynı yanıt
/// (`Idempotent-Replay: true`).
library;

import 'dart:math';

import 'app_failure.dart';

/// Kanonik UUID v4 (`3f1c2d9e-7b4a-4c1e-9f0a-2b6d8e4c1a57`).
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // sürüm 4
  b[8] = (b[8] & 0x3f) | 0x80; // varyant
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-'
      '${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Anahtar geçerli biçimde mi (UUID v4, küçük harf).
bool isValidIdempotencyKey(String key) => _uuidV4.hasMatch(key);

/// Kullanıcı niyeti başına bir anahtar tutar.
///
/// - Kullanıcı onayladığında [keyFor] çağrılır: aynı niyet (ör. `orders/place:<sepet özeti>`) için
///   bekleyen anahtar varsa o döner (tekrar deneme), yoksa yeni anahtar üretilir.
/// - Sunucudan KESİN bir yanıt gelince ([settle] hatasız ya da belirsiz olmayan hatayla) anahtar bırakılır;
///   kullanıcı aynı işlemi yeniden yaparsa bu yeni bir niyettir ve yeni anahtar alır.
/// - Sonuç BELİRSİZSE ([AppFailure.isUncertain]: bağlantı koptu, zaman aşımı, 5xx, işlem sürüyor) anahtar
///   saklanır; tekrar deneme aynı anahtarla gider ve sunucu işlemi ikinci kez yapmaz.
/// - Bekleyen anahtar [lifetime] sonra unutulur (sunucu 24 saat tutar).
class IdempotencyLedger {
  IdempotencyLedger({
    this.lifetime = const Duration(minutes: 30),
    DateTime Function()? clock,
    String Function()? generator,
  }) : _clock = clock ?? DateTime.now,
       _generator = generator ?? newIdempotencyKey;

  final Duration lifetime;
  final DateTime Function() _clock;
  final String Function() _generator;
  final Map<String, ({String key, DateTime at})> _pending = {};

  /// [intent] için anahtar: bekleyen varsa o, yoksa yeni.
  String keyFor(String intent) {
    final now = _clock();
    _pending.removeWhere((_, v) => now.difference(v.at) >= lifetime);
    final existing = _pending[intent];
    if (existing != null) return existing.key;
    final key = _generator();
    _pending[intent] = (key: key, at: now);
    return key;
  }

  /// İsteğin sonucu: kesin yanıtta anahtar bırakılır, belirsizde saklanır.
  void settle(String intent, {Object? error}) {
    if (error != null && AppFailure.from(error).isUncertain) return;
    _pending.remove(intent);
  }

  /// [intent] için bekleyen anahtar (yalnızca okuma).
  String? pendingKey(String intent) => _pending[intent]?.key;

  /// Tüm bekleyen anahtarları unutur (oturum değişti).
  void clear() => _pending.clear();
}
