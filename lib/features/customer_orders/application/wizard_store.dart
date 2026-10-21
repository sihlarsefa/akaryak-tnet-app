import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/tr_time.dart';
import '../data/place_models.dart';
import 'loadable.dart';
import 'wizard_models.dart';

/// Sonucu henüz kesinleşmemiş gönderim: anahtar + gövde (spec C.4a: "one key per intent").
@immutable
class PendingSubmission {
  const PendingSubmission({
    required this.key,
    required this.request,
    required this.startedAt,
  });

  factory PendingSubmission.fromJson(JsonReader r) => PendingSubmission(
    key: r.str('key'),
    request: PlaceOrderRequest.fromJson(r['request']),
    startedAt: r.dateUtc('startedAt') ?? DateTime.now().toUtc(),
  );

  final String key;
  final PlaceOrderRequest request;
  final DateTime startedAt;

  JsonMap toJson() => {
    'key': key,
    'request': request.toJson(),
    'startedAt': startedAt.toUtc().toIso8601String(),
  };
}

/// `CreateOrderResultDto` JSON'u (önbellek).
JsonMap createdOrderToJson(CreateOrderResult o) => {
  'orderId': o.orderId,
  'orderNumber': o.orderNumber,
  'expiresAt': o.expiresAt == null ? null : TrTime.isoLocal(o.expiresAt!),
  'financeStatus': o.financeStatus.code,
  'financeReasons': o.financeReasons,
  'paymentMethodCode': o.paymentMethodCode,
  'paymentDueDate': o.paymentDueDate == null
      ? null
      : TrTime.isoLocal(o.paymentDueDate!),
  'estimatedAmount': o.estimatedAmount,
  'paymentGroupKey': o.paymentGroupKey,
};

/// Kullanıcı başına saklanan sihirbaz durumu: taslak + bekleyen gönderim + kısmi sonuçta oluşan
/// siparişler (24 sa; başarı ya da düzenlemeyle silinir / değişir).
@immutable
class WizardSnapshot {
  const WizardSnapshot({
    required this.draft,
    this.pending,
    this.created = const [],
    this.documentUploadedGroup,
    this.savedAt,
  });

  factory WizardSnapshot.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final p = r.objOrNull('pending');
    return WizardSnapshot(
      draft: OrderDraft.fromJson(r['draft']),
      pending: p == null ? null : PendingSubmission.fromJson(p),
      created: List.unmodifiable(r.list('created', CreateOrderResult.fromJson)),
      documentUploadedGroup: r.nonEmpty('documentUploadedGroup'),
      savedAt: r.dateUtc('savedAt'),
    );
  }

  final OrderDraft draft;
  final PendingSubmission? pending;

  /// Önceki kısmi gönderimlerde oluşan siparişler.
  final List<CreateOrderResult> created;

  /// Belgesi yüklenmiş ödeme grubu (aynı çek / senet ikinci kez istenmez).
  final String? documentUploadedGroup;
  final DateTime? savedAt;

  WizardSnapshot copyWith({
    OrderDraft? draft,
    PendingSubmission? pending,
    bool clearPending = false,
    List<CreateOrderResult>? created,
    String? documentUploadedGroup,
  }) => WizardSnapshot(
    draft: draft ?? this.draft,
    pending: clearPending ? null : (pending ?? this.pending),
    created: created ?? this.created,
    documentUploadedGroup: documentUploadedGroup ?? this.documentUploadedGroup,
    savedAt: savedAt,
  );

  JsonMap toJson() => {
    'v': 1,
    'draft': draft.toJson(),
    'pending': pending?.toJson(),
    'created': [for (final o in created) createdOrderToJson(o)],
    'documentUploadedGroup': documentUploadedGroup,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

/// Sihirbaz deposu (`CacheStore`, kullanıcıya özel, 24 sa).
class WizardDraftStore {
  WizardDraftStore(this.cache, this.userId);

  static const ttl = Duration(hours: 24);

  final CacheStore cache;
  final String userId;

  String get _key => A2Keys.wizard(userId);

  Future<WizardSnapshot?> load() async {
    final e = await cache.read(_key);
    if (e == null || e.isExpired) return null;
    try {
      return WizardSnapshot.fromJson(e.value);
    } catch (err) {
      AppLog.warn('Sipariş taslağı okunamadı', error: err);
      return null;
    }
  }

  Future<void> save(WizardSnapshot s) =>
      cache.write(_key, s.toJson(), ttl: ttl, userId: userId);

  Future<void> clear() => cache.remove(_key);
}

final wizardDraftStoreProvider = Provider<WizardDraftStore?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return WizardDraftStore(ref.watch(cacheStoreProvider), uid);
});

/// Ana sayfadaki "Yarım kalan siparişinize devam edin" kartı için taslak özeti.
@immutable
class DraftSummary {
  const DraftSummary({
    required this.lineCount,
    required this.totalLiters,
    required this.pendingSubmission,
    this.savedAt,
    this.partial = false,
  });

  final int lineCount;
  final double totalLiters;

  /// Gönderimi doğrulanmayı bekliyor ("Siparişiniz kontrol ediliyor").
  final bool pendingSubmission;

  /// Kısmi gönderimden kalan satırlar.
  final bool partial;
  final DateTime? savedAt;
}

/// Kayıtlı taslak (yoksa null). Sihirbaz kaydettikçe [draftRevisionProvider] ile yenilenir.
final draftSummaryProvider = FutureProvider<DraftSummary?>((ref) async {
  ref.watch(draftRevisionProvider);
  final store = ref.watch(wizardDraftStoreProvider);
  if (store == null) return null;
  final s = await store.load();
  if (s == null) return null;
  final d = s.draft;
  if (s.pending == null && (d.isBlank || !d.dirty)) return null;
  return DraftSummary(
    lineCount: d.lines.where((l) => l.productId != null).length,
    totalLiters: d.totalLiters,
    pendingSubmission: s.pending != null,
    partial: d.origin == DraftOrigin.partial,
    savedAt: s.savedAt,
  );
});

/// Taslak değişince artan sayaç (özet sağlayıcısını tazeler).
final draftRevisionProvider = NotifierProvider<DraftRevision, int>(
  DraftRevision.new,
);

class DraftRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
