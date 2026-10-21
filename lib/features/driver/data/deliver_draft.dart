import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/models/json.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/utils/log.dart';
import 'driver_models.dart';

/// Teslim et adımları (spec A.4 A7): litre → irsaliye no → teslim alan → fotoğraf → imza → özet.
enum DeliverStep {
  liters,
  document,
  recipient,
  photos,
  signature,
  summary;

  DeliverStep? get next => index + 1 < values.length ? values[index + 1] : null;
  DeliverStep? get previous => index > 0 ? values[index - 1] : null;
}

/// Taslaktaki fotoğraf: yerel dosya (çekildi, henüz yüklenmedi ya da yüklendi) veya önceki
/// teslimattan sunucudaki ek (düzeltmede yeniden kullanılır).
@immutable
class DraftPhoto {
  const DraftPhoto({this.path, this.publicId, this.fromServer = false});

  factory DraftPhoto.fromJson(JsonReader r) => DraftPhoto(
    path: r.nonEmpty('path'),
    publicId: r.nonEmpty('publicId'),
    fromServer: r.boolean('fromServer'),
  );

  /// Kalıcı yerel dosya (uygulama klasörü; işletim sistemi silmez).
  final String? path;

  /// Yüklendiyse ek kimliği.
  final String? publicId;

  /// Önceki teslimattan (sunucuda zaten var; dosyası yok).
  final bool fromServer;

  JsonMap toJson() => {
    ...jsonEntry('path', path),
    ...jsonEntry('publicId', publicId),
    if (fromServer) 'fromServer': true,
  };

  @override
  bool operator ==(Object other) =>
      other is DraftPhoto &&
      other.path == path &&
      other.publicId == publicId &&
      other.fromServer == fromServer;

  @override
  int get hashCode => Object.hash(path, publicId, fromServer);
}

/// Teslim et taslağı (spec A.4: her adım yerelde saklanır; uygulama yeniden açılınca 24 saat içinde
/// kaldığı yerden sürer).
@immutable
class DeliverDraft {
  const DeliverDraft({
    required this.shipmentId,
    required this.code,
    this.step = DeliverStep.liters,
    this.litersText = '',
    this.documentNo = '',
    this.recipientName = '',
    this.note = '',
    this.photos = const [],
    this.signaturePath,
    this.signaturePublicId,
    this.waiver,
    this.correction = false,
    this.fixOpId,
    required this.savedAt,
  });

  factory DeliverDraft.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final step = r.intOrNull('step') ?? 0;
    final waiver = r.objOrNull('waiver');
    return DeliverDraft(
      shipmentId: r.integer('shipmentId'),
      code: r.str('code'),
      step: DeliverStep.values[step.clamp(0, DeliverStep.values.length - 1)],
      litersText: r.str('litersText'),
      documentNo: r.str('documentNo'),
      recipientName: r.str('recipientName'),
      note: r.str('note'),
      photos: List.unmodifiable(r.list('photos', DraftPhoto.fromJson)),
      signaturePath: r.nonEmpty('signaturePath'),
      signaturePublicId: r.nonEmpty('signaturePublicId'),
      waiver: waiver == null ? null : SignatureWaiver.fromJson(waiver),
      correction: r.boolean('correction'),
      fixOpId: r.nonEmpty('fixOpId'),
      savedAt: r.dateUtc('savedAt') ?? DateTime.now().toUtc(),
    );
  }

  /// Taslak ömrü (spec: 24 saat).
  static const lifetime = Duration(hours: 24);

  final int shipmentId;
  final String code;
  final DeliverStep step;

  /// Tuş takımındaki metin (Türkçe ondalık virgül: `7950,5`).
  final String litersText;
  final String documentNo;
  final String recipientName;
  final String note;
  final List<DraftPhoto> photos;
  final String? signaturePath;
  final String? signaturePublicId;
  final SignatureWaiver? waiver;

  /// İtirazlı teslimatın düzeltilmesi ("Teslimatı düzelt").
  final bool correction;

  /// Sunucunun reddettiği bekleyen işlemin yerine geçer ("Düzelt").
  final String? fixOpId;
  final DateTime savedAt;

  bool isExpired(DateTime now) => now.difference(savedAt) > lifetime;

  bool get hasSignature => signaturePath != null || signaturePublicId != null;

  /// Kullanıcının girdiği bir şey var mı (çıkarken sorulur).
  bool get isDirty =>
      litersText.isNotEmpty ||
      documentNo.trim().isNotEmpty ||
      recipientName.trim().isNotEmpty ||
      note.trim().isNotEmpty ||
      photos.any((p) => !p.fromServer) ||
      signaturePath != null ||
      waiver != null;

  /// Taslağın yerel dosyaları (fotoğraflar + imza).
  List<String> get localFiles => [
    for (final p in photos)
      if (p.path != null) p.path!,
    ?signaturePath,
  ];

  DeliverDraft copyWith({
    DeliverStep? step,
    String? litersText,
    String? documentNo,
    String? recipientName,
    String? note,
    List<DraftPhoto>? photos,
    String? signaturePath,
    bool clearSignature = false,
    SignatureWaiver? waiver,
    bool clearWaiver = false,
    DateTime? savedAt,
  }) => DeliverDraft(
    shipmentId: shipmentId,
    code: code,
    step: step ?? this.step,
    litersText: litersText ?? this.litersText,
    documentNo: documentNo ?? this.documentNo,
    recipientName: recipientName ?? this.recipientName,
    note: note ?? this.note,
    photos: photos ?? this.photos,
    signaturePath: clearSignature
        ? null
        : (signaturePath ?? this.signaturePath),
    signaturePublicId: clearSignature ? null : signaturePublicId,
    waiver: clearWaiver ? null : (waiver ?? this.waiver),
    correction: correction,
    fixOpId: fixOpId,
    savedAt: savedAt ?? this.savedAt,
  );

  JsonMap toJson() => {
    'shipmentId': shipmentId,
    'code': code,
    'step': step.index,
    'litersText': litersText,
    'documentNo': documentNo,
    'recipientName': recipientName,
    'note': note,
    'photos': [for (final p in photos) p.toJson()],
    ...jsonEntry('signaturePath', signaturePath),
    ...jsonEntry('signaturePublicId', signaturePublicId),
    ...jsonEntry('waiver', waiver?.toJson()),
    if (correction) 'correction': true,
    ...jsonEntry('fixOpId', fixOpId),
    'savedAt': savedAt.toUtc().toIso8601String(),
  };
}

/// Kullanıcının teslim taslakları (tercihlerde tek anahtar; çıkışta `PrefsStore.clearUser` siler).
class DeliverDraftStore {
  DeliverDraftStore(this.prefs, this.files, {DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  final PrefsStore prefs;
  final DriverFileStore files;
  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  static String keyFor(String userId) =>
      PrefKeys.user(userId, 'driver.deliverDrafts');

  /// Süresi geçmemiş taslaklar. Süresi geçenler (ve dosyaları) silinir.
  Map<int, DeliverDraft> all(String userId) {
    final raw = prefs.getString(keyFor(userId));
    if (raw == null || raw.isEmpty) return const {};
    final out = <int, DeliverDraft>{};
    var changed = false;
    try {
      final map = JsonReader.asMap(jsonDecode(raw));
      final now = _clock();
      for (final e in map.entries) {
        final d = DeliverDraft.fromJson(e.value);
        if (d.shipmentId <= 0) {
          changed = true;
          continue;
        }
        if (d.isExpired(now)) {
          changed = true;
          files.deleteAll(d.localFiles);
          continue;
        }
        out[d.shipmentId] = d;
      }
    } catch (e) {
      AppLog.warn('Teslim taslakları okunamadı', error: e);
      changed = true;
    }
    if (changed) unawaited(_write(userId, out));
    return out;
  }

  DeliverDraft? get(String userId, int shipmentId) => all(userId)[shipmentId];

  Future<void> save(String userId, DeliverDraft draft) {
    final map = Map.of(all(userId));
    map[draft.shipmentId] = draft.copyWith(savedAt: _clock());
    return _write(userId, map);
  }

  /// Taslağı siler. [deleteFiles] verilirse yalnızca [keep] dışındaki dosyalar silinir
  /// (bekleyen işleme devredilen dosyalar korunur).
  Future<void> remove(
    String userId,
    int shipmentId, {
    bool deleteFiles = false,
    Set<String> keep = const {},
  }) async {
    final map = Map.of(all(userId));
    final d = map.remove(shipmentId);
    if (d != null && deleteFiles) {
      files.deleteAll(d.localFiles.where((f) => !keep.contains(f)));
    }
    await _write(userId, map);
  }

  Future<void> _write(String userId, Map<int, DeliverDraft> map) {
    if (map.isEmpty) return prefs.remove(keyFor(userId));
    return prefs.setString(
      keyFor(userId),
      jsonEncode({for (final e in map.entries) '${e.key}': e.value.toJson()}),
    );
  }
}

/// Teslim fotoğrafı ve imza dosyaları: geçici klasörden uygulama klasörüne (`driver_drafts/`) kopyalanır;
/// işletim sistemi silmez, uygulama yeniden açılınca taslak sürer. Bekleyen işlem tamamlanınca
/// `OutboxRunner` dosyaları siler.
abstract class DriverFileStore {
  Future<String> persistFile(String sourcePath);

  Future<String> persistBytes(List<int> bytes, {required String extension});

  bool exists(String path);

  void deleteAll(Iterable<String> paths);

  /// [keep] dışındaki, [olderThan] süreden eski dosyaları siler (sahipsiz taslak dosyaları).
  Future<void> sweep(
    Set<String> keep, {
    Duration olderThan = const Duration(days: 3),
  });
}

/// Varsayılan: `getApplicationSupportDirectory()/driver_drafts`.
class AppDriverFileStore implements DriverFileStore {
  AppDriverFileStore({Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDir;
  Directory? _dir;
  int _seq = 0;

  Future<Directory> _folder() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await _baseDir();
    final d = Directory(p.join(base.path, 'driver_drafts'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dir = d;
  }

  String _name(String ext) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$stamp-${(_seq++).toRadixString(36)}$ext';
  }

  @override
  Future<String> persistFile(String sourcePath) async {
    final dir = await _folder();
    final ext = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final target = p.join(dir.path, _name(ext));
    await File(sourcePath).copy(target);
    return target;
  }

  @override
  Future<String> persistBytes(
    List<int> bytes, {
    required String extension,
  }) async {
    final dir = await _folder();
    final target = p.join(dir.path, _name('.$extension'));
    await File(target).writeAsBytes(bytes, flush: true);
    return target;
  }

  @override
  bool exists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  void deleteAll(Iterable<String> paths) {
    for (final path in paths) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {
        // Dosya zaten yok.
      }
    }
  }

  @override
  Future<void> sweep(
    Set<String> keep, {
    Duration olderThan = const Duration(days: 3),
  }) async {
    try {
      final dir = await _folder();
      final cutoff = DateTime.now().subtract(olderThan);
      for (final f in dir.listSync().whereType<File>()) {
        if (!keep.contains(f.path) && f.statSync().modified.isBefore(cutoff)) {
          f.deleteSync();
        }
      }
    } catch (e) {
      AppLog.debug('Teslim dosyası temizliği atlandı: $e');
    }
  }
}

final driverFileStoreProvider = Provider<DriverFileStore>(
  (ref) => AppDriverFileStore(),
);

final deliverDraftStoreProvider = Provider<DeliverDraftStore>(
  (ref) => DeliverDraftStore(
    ref.watch(prefsStoreProvider),
    ref.watch(driverFileStoreProvider),
  ),
);
