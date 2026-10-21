import '../utils/tr_time.dart';
import '../utils/turkish_text.dart';

/// JSON nesnesi.
typedef JsonMap = Map<String, dynamic>;

/// Sunucu JSON'unu tip güvenli ve hoşgörülü okur (spec C.4).
///
/// - Eksik ya da yanlış tipteki alan varsayılana düşer; şekil sorunları istisna fırlatmaz.
/// - Anahtar önce olduğu gibi (camelCase), bulunamazsa PascalCase aranır.
/// - Sayılar metin olarak da gelebilir (`"12.5"`).
/// - Tarihler an (UTC `DateTime`) olarak döner: [dateTr] ofsetsiz değeri Türkiye yerel saati,
///   [dateUtc] UTC sayar; ofsetli değerler her ikisinde de kesin andır (bkz. [TrTime]).
/// - Bilinmeyen enum kodları `unknown` değerine düşer ([enumOf]).
///
/// Modeller elle yazılır: `factory X.fromJson(JsonMap json) { final r = JsonReader(json); ... }`.
class JsonReader {
  JsonReader(this.raw);

  /// Herhangi bir değerden okuyucu (Map değilse boş).
  factory JsonReader.of(Object? json) => JsonReader(asMap(json));

  final JsonMap raw;

  /// Değeri `Map<String, dynamic>` olarak döndürür (değilse boş harita).
  static JsonMap asMap(Object? json) {
    if (json is Map<String, dynamic>) return json;
    if (json is Map) return json.map((k, v) => MapEntry('$k', v));
    return <String, dynamic>{};
  }

  /// Üst düzey JSON dizisini modele çevirir (dizi değilse boş liste).
  static List<T> parseList<T>(Object? json, T Function(JsonReader r) item) {
    if (json is! List) return <T>[];
    return [
      for (final e in json)
        if (e is Map) item(JsonReader.of(e)),
    ];
  }

  bool has(String key) => _value(key) != null;

  Object? operator [](String key) => _value(key);

  Object? _value(String key) {
    if (raw.containsKey(key)) return raw[key];
    if (key.isEmpty) return null;
    final pascal = key[0].asciiUpper + key.substring(1);
    return raw[pascal];
  }

  // ------------------------------------------------------------------ Metin

  String str(String key, [String fallback = '']) => strOrNull(key) ?? fallback;

  String? strOrNull(String key) {
    final v = _value(key);
    if (v == null) return null;
    if (v is String) return v;
    if (v is num || v is bool) return '$v';
    return null;
  }

  /// Boş ya da yalnızca boşluk ise null.
  String? nonEmpty(String key) {
    final v = strOrNull(key)?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  // ------------------------------------------------------------------ Sayılar

  int integer(String key, [int fallback = 0]) => intOrNull(key) ?? fallback;

  int? intOrNull(String key) => toInt(_value(key));

  double dec(String key, [double fallback = 0]) => decOrNull(key) ?? fallback;

  double? decOrNull(String key) => toDouble(_value(key));

  static int? toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.isFinite ? v.toInt() : null;
    if (v is String) {
      return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt();
    }
    return null;
  }

  static double? toDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  // ------------------------------------------------------------------ Mantıksal

  bool boolean(String key, [bool fallback = false]) =>
      boolOrNull(key) ?? fallback;

  bool? boolOrNull(String key) {
    final v = _value(key);
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().asciiLower;
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return null;
  }

  // ------------------------------------------------------------------ Tarihler

  /// Ofsetsiz değer Türkiye yerel saatidir (Order.CreatedAt, ExpiresAt, Shipment.ScheduledAt …).
  DateTime? dateTr(String key) => TrTime.parseLocal(strOrNull(key));

  /// Ofsetsiz değer UTC'dir (ek ve onay tarihleri, `*Utc` alanları, belirteç süreleri).
  DateTime? dateUtc(String key) => TrTime.parseUtc(strOrNull(key));

  /// Saf tarih (`yyyy-MM-dd`) → o günün Türkiye gece yarısı.
  DateTime? date(String key) => TrTime.parseDate(strOrNull(key));

  // ------------------------------------------------------------------ Koleksiyonlar

  /// İç nesne (yoksa boş okuyucu).
  JsonReader obj(String key) => JsonReader.of(_value(key));

  /// İç nesne; yoksa ya da Map değilse null.
  JsonReader? objOrNull(String key) {
    final v = _value(key);
    return v is Map ? JsonReader.of(v) : null;
  }

  /// Nesne dizisi.
  List<T> list<T>(String key, T Function(JsonReader r) item) =>
      parseList(_value(key), item);

  /// İlkel dizi (ör. sayılar); dönüştürülemeyen öğeler atlanır.
  List<T> listOf<T>(String key, T? Function(Object? v) item) {
    final v = _value(key);
    if (v is! List) return <T>[];
    final out = <T>[];
    for (final e in v) {
      final x = item(e);
      if (x != null) out.add(x);
    }
    return out;
  }

  List<String> strings(String key) =>
      listOf<String>(key, (v) => v == null ? null : '$v');

  List<int> ints(String key) => listOf<int>(key, toInt);

  /// Ham harita (yoksa boş).
  JsonMap map(String key) => asMap(_value(key));

  /// Sayısal kodlu enum: `r.enumOf('status', OrderStatus.fromCode)`. Bilinmeyen kod `unknown` döner.
  T enumOf<T>(String key, T Function(int? code) fromCode) =>
      fromCode(intOrNull(key));
}

/// JSON yazarken null alanları atlamak için yardımcı: `{...jsonEntry('note', note)}`.
Map<String, Object?> jsonEntry(String key, Object? value) =>
    value == null ? const {} : {key: value};
