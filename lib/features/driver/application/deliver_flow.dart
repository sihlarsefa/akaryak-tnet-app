import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/tr_number.dart';
import '../../../core/utils/turkish_text.dart';
import '../copy.dart';
import '../data/deliver_draft.dart';
import '../data/driver_models.dart';

/// Litre tuş takımının metin kuralları (Türkçe ondalık virgül, en çok 3 ondalık, baştaki sıfır atılır).
abstract final class LitersKeypad {
  static const backspace = 'sil';
  static const comma = ',';
  static const maxIntegerDigits = 7;
  static const maxDecimals = 3;

  /// [key]: '0'..'9', [comma] ya da [backspace].
  static String apply(String current, String key) {
    if (key == backspace) {
      return current.isEmpty ? '' : current.substring(0, current.length - 1);
    }
    if (key == comma) {
      if (current.contains(',')) return current;
      return current.isEmpty ? '0,' : '$current,';
    }
    if (key.length != 1 || !RegExp(r'\d').hasMatch(key)) return current;
    final parts = current.split(',');
    if (parts.length == 2) {
      return parts[1].length >= maxDecimals ? current : '$current$key';
    }
    if (current == '0') return key;
    if (parts[0].length >= maxIntegerDigits) return current;
    return '$current$key';
  }

  /// `7950,5` → `7.950,5` (görüntü; virgülden sonrası yazıldığı gibi).
  static String display(String text) {
    if (text.isEmpty) return '0';
    final parts = text.split(',');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final grouped = Fmt.number(int.tryParse(intPart) ?? 0);
    return parts.length > 1 ? '$grouped,${parts[1]}' : grouped;
  }

  static double? parse(String text) =>
      text.isEmpty ? null : TrNumber.parse(text);
}

/// "Teslim et" sihirbazının durumu (spec A.4 A7): adımlar, doğrulama, fotoğraf / imza / imza alınamama,
/// her değişiklikte yerel taslak (24 saat; uygulama yeniden açılınca kaldığı yerden sürer).
class DeliverFlowModel extends ChangeNotifier {
  DeliverFlowModel({
    required this.userId,
    required this.detail,
    required this.store,
    DeliverDraft? initial,
    this.saveDelay = const Duration(milliseconds: 300),
    bool correction = false,
  }) : _draft =
           initial ??
           DeliverDraft(
             shipmentId: detail.id,
             code: detail.code,
             correction: correction,
             // Düzeltmede önceki teslim bilgileri ve fotoğrafları önerilir.
             litersText: correction && detail.row.deliveredLiters != null
                 ? _litersText(detail.row.deliveredLiters!)
                 : '',
             documentNo: correction ? (detail.deliveryDocumentNo ?? '') : '',
             recipientName: correction ? (detail.recipientName ?? '') : '',
             photos: correction
                 ? [
                     for (final a in detail.deliveryPhotos)
                       DraftPhoto(publicId: a.publicId, fromServer: true),
                   ]
                 : const [],
             savedAt: DateTime.now().toUtc(),
           );

  final String userId;
  final DriverShipmentDetail detail;
  final DeliverDraftStore store;
  final Duration saveDelay;

  DeliverDraft _draft;
  Timer? _saveTimer;
  bool _disposed = false;

  /// Taslak işleme devredildi ya da silindi: bir daha yazılmaz.
  bool _closed = false;

  /// Son adım değişikliğinin yönü (geri giderken animasyon ters akar).
  bool reverse = false;

  DeliverDraft get draft => _draft;
  DeliverStep get step => _draft.step;

  static String _litersText(double v) =>
      Fmt.number(v, maxFraction: 3).replaceAll('.', '');

  // ------------------------------------------------------------------ Kurallar

  double get plannedLiters => detail.row.plannedLiters;
  double? get liters => LitersKeypad.parse(_draft.litersText);

  bool get photoRequired => detail.requirements.photo || _draft.waiver != null;
  bool get signatureRequired => detail.requirements.signature;

  /// Konum: ayar zorunlu kılıyorsa ya da imza alınamadıysa.
  bool get gpsRequired => detail.requirements.gps || _draft.waiver != null;

  int get photoCount => _draft.photos.length;

  String? get litersError {
    final v = liters;
    if (v == null || v <= 0) return DriverCopy.litersRequired;
    if (v > plannedLiters + 1e-9) {
      return DriverCopy.litersMax(Fmt.liters(plannedLiters));
    }
    final parts = _draft.litersText.split(',');
    if (parts.length > 1 && parts[1].length > LitersKeypad.maxDecimals) {
      return DriverCopy.litersDecimals;
    }
    return null;
  }

  /// Tank kapasitesini aşan litre uyarısı (engellemez).
  String? get tankWarning {
    final cap = detail.tankCapacityLiters;
    final v = liters;
    if (cap == null || cap <= 0 || v == null || v <= cap) return null;
    return DriverCopy.tankWarning(Fmt.liters(cap));
  }

  String? get documentError {
    final d = _draft.documentNo.trim();
    if (d.isEmpty) return DriverCopy.documentRequired;
    if (d.length > 100) return DriverCopy.documentTooLong;
    return null;
  }

  String? get recipientError => _draft.recipientName.trim().length > 150
      ? DriverCopy.recipientTooLong
      : null;

  String? get photosError {
    if (photoRequired && photoCount == 0) return DriverCopy.photosRequired;
    if (photoCount > 20) return DriverCopy.photoMax;
    return null;
  }

  String? get signatureError {
    final w = _draft.waiver;
    if (w != null) {
      if (w.validate() != null) return DriverCopy.waiverNoteRequired;
      return null;
    }
    if (signatureRequired && !_draft.hasSignature) {
      return DriverCopy.signatureRequired;
    }
    return null;
  }

  /// Adımın ilk hatası (null = geçilebilir).
  String? errorFor(DeliverStep s) => switch (s) {
    DeliverStep.liters => litersError,
    DeliverStep.document => documentError,
    DeliverStep.recipient => recipientError,
    DeliverStep.photos => photosError,
    DeliverStep.signature => signatureError,
    DeliverStep.summary => null,
  };

  /// Özetten geriye ilk hatalı adım (yoksa null).
  DeliverStep? get firstInvalidStep {
    for (final s in DeliverStep.values) {
      if (s == DeliverStep.summary) break;
      if (errorFor(s) != null) return s;
    }
    return null;
  }

  /// Gönderime hazır mı (konum hariç; konum ekranda ayrıca denetlenir).
  bool get isComplete => firstInvalidStep == null;

  bool get isDirty => _draft.isDirty;

  // ------------------------------------------------------------------ Gezinme

  /// İleri. Adım hatalıysa hatayı döndürür ve ilerlemez. İmza alınamadı + fotoğraf yoksa fotoğraf
  /// adımına döner.
  String? next() {
    final err = errorFor(step);
    if (err != null) return err;
    if (step == DeliverStep.signature &&
        _draft.waiver != null &&
        photoCount == 0) {
      goTo(DeliverStep.photos);
      return DriverCopy.waiverNeedsPhoto;
    }
    final n = step.next;
    if (n != null) goTo(n);
    return null;
  }

  void back() {
    final p = step.previous;
    if (p != null) goTo(p);
  }

  void goTo(DeliverStep s) {
    if (s == step) return;
    reverse = s.index < step.index;
    _update(_draft.copyWith(step: s));
  }

  // ------------------------------------------------------------------ Değişiklikler

  void key(String k) => _update(
    _draft.copyWith(litersText: LitersKeypad.apply(_draft.litersText, k)),
  );

  void clearLiters() => _update(_draft.copyWith(litersText: ''));

  void fillPlanned() =>
      _update(_draft.copyWith(litersText: _litersText(plannedLiters)));

  /// İrsaliye no büyük harfle saklanır (bayi "Teslim bildir" gibi; QA LF-2).
  void setDocument(String v) =>
      _update(_draft.copyWith(documentNo: v.asciiUpper));

  void setRecipient(String v) => _update(_draft.copyWith(recipientName: v));

  void setNote(String v) => _update(_draft.copyWith(note: v));

  void addPhotos(List<String> paths) {
    if (paths.isEmpty) return;
    final room = 20 - _draft.photos.length;
    if (room <= 0) return;
    _update(
      _draft.copyWith(
        photos: [
          ..._draft.photos,
          for (final p in paths.take(room)) DraftPhoto(path: p),
        ],
      ),
    );
  }

  /// Fotoğrafı taslaktan çıkarır; yerel dosyayı döndürür (çağıran siler).
  String? removePhoto(int index) {
    if (index < 0 || index >= _draft.photos.length) return null;
    final removed = _draft.photos[index];
    final list = [..._draft.photos]..removeAt(index);
    _update(_draft.copyWith(photos: list));
    return removed.path;
  }

  void setSignature(String path) =>
      _update(_draft.copyWith(signaturePath: path, clearWaiver: true));

  /// İmzayı siler; eski dosyanın yolunu döndürür (çağıran siler).
  String? clearSignature() {
    final old = _draft.signaturePath;
    _update(_draft.copyWith(clearSignature: true));
    return old;
  }

  /// İmza alınamadı. İmza (varsa) kaldırılır; eski dosyanın yolu döner.
  String? setWaiver(SignatureWaiver waiver) {
    final old = _draft.signaturePath;
    _update(_draft.copyWith(waiver: waiver, clearSignature: true));
    return old;
  }

  void clearWaiver() => _update(_draft.copyWith(clearWaiver: true));

  void _update(DeliverDraft d) {
    _draft = d;
    if (_disposed) return;
    notifyListeners();
    _scheduleSave();
  }

  // ------------------------------------------------------------------ Kalıcılık

  void _scheduleSave() {
    _saveTimer?.cancel();
    if (saveDelay == Duration.zero) {
      unawaited(flush());
      return;
    }
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
  }

  /// Taslağı hemen yazar (adım geçişi, arka plana alma, çıkış).
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_closed) return;
    if (!_draft.isDirty && _draft.step == DeliverStep.liters) return;
    await store.save(userId, _draft);
  }

  /// Taslak bekleyen işleme devredildi (komut taslağı kendisi siler).
  void markSubmitted() {
    _closed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  /// Taslağı ve (işleme devredilmemiş) dosyalarını siler.
  Future<void> discard({Set<String> keep = const {}}) async {
    _closed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    await store.remove(
      userId,
      _draft.shipmentId,
      deleteFiles: true,
      keep: keep,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    final pending = _saveTimer?.isActive ?? false;
    _saveTimer?.cancel();
    _saveTimer = null;
    if (pending && !_closed) unawaited(store.save(userId, _draft));
    super.dispose();
  }
}
