import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_env.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../data/customer_more_repository.dart';
import '../data/documents.dart';
import '../data/pdf_cache.dart';
import '../documents/doc_builders.dart';
import '../documents/doc_renderer.dart';
import '../documents/doc_spec.dart';
import 'cm_common.dart';
import 'paged.dart';

@immutable
class DocumentsState {
  const DocumentsState({
    this.query = const DocumentArchiveQuery(),
    this.page = const PagedState(),
    this.totals = const DocumentArchiveTotals(),
  });

  final DocumentArchiveQuery query;
  final PagedState<DocumentArchiveRow> page;
  final DocumentArchiveTotals totals;

  DocumentsState copyWith({
    DocumentArchiveQuery? query,
    PagedState<DocumentArchiveRow>? page,
    DocumentArchiveTotals? totals,
  }) => DocumentsState(
    query: query ?? this.query,
    page: page ?? this.page,
    totals: totals ?? this.totals,
  );
}

/// Belge arşivi (`customers/me/documents?skip&take` → `{totals, items}`). Varsayılan ölçütün ilk sayfası
/// çevrimdışı için önbelleğe yazılır (spec C.4a).
final documentsControllerProvider =
    NotifierProvider.autoDispose<DocumentsController, DocumentsState>(
      DocumentsController.new,
    );

class DocumentsController extends AutoDisposeNotifier<DocumentsState> {
  static const take = 25;
  int _epoch = 0;
  bool _disposed = false;

  @override
  DocumentsState build() {
    ref.watch(currentUserIdProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
    });
    Future.microtask(load);
    return const DocumentsState();
  }

  CustomerMoreRepository get _repo => ref.read(customerMoreRepositoryProvider);

  Future<void> load({bool refresh = false}) async {
    if (_disposed) return;
    final epoch = ++_epoch;
    final s = state;
    state = s.copyWith(
      page: refresh && s.page.items.isNotEmpty
          ? s.page.copyWith(refreshing: true, clearError: true)
          : PagedState<DocumentArchiveRow>(items: s.page.items),
    );
    try {
      final loaded = await loadWithCache(
        cache: ref.read(cacheStoreProvider),
        userId: ref.read(currentUserIdProvider),
        name: CmCacheKeys.documentsFirstPage,
        writeCache: s.query.isDefault,
        fetch: () => _repo.documentArchiveJson(s.query, take: take),
        parse: DocumentArchivePage.fromJson,
      );
      if (epoch != _epoch) return;
      if (loaded.fromCache && !s.query.isDefault) {
        throw const OfflineFailure();
      }
      final res = loaded.value;
      state = state.copyWith(
        totals: res.totals,
        page: PagedState(
          items: res.items,
          total: res.totals.count,
          hasMore: res.items.length < res.totals.count,
          loading: false,
          fromCache: loaded.fromCache,
          storedAt: loaded.storedAt,
        ),
      );
    } catch (e) {
      if (epoch != _epoch) return;
      state = state.copyWith(
        page: state.page.copyWith(
          loading: false,
          refreshing: false,
          error: AppFailure.from(e),
        ),
      );
    }
  }

  Future<void> loadMore() async {
    final s = state;
    final p = s.page;
    if (_disposed || !p.hasMore || p.loadingMore || p.loading || p.fromCache) {
      return;
    }
    final epoch = _epoch;
    state = s.copyWith(
      page: p.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
    try {
      final json = await _repo.documentArchiveJson(
        s.query,
        skip: p.items.length,
        take: take,
      );
      if (epoch != _epoch) return;
      final res = DocumentArchivePage.fromJson(json);
      final known = {for (final r in state.page.items) r.key};
      final items = [
        ...state.page.items,
        ...res.items.where((r) => !known.contains(r.key)),
      ];
      state = state.copyWith(
        totals: res.totals,
        page: state.page.copyWith(
          items: items,
          total: res.totals.count,
          hasMore: res.items.isNotEmpty && items.length < res.totals.count,
          loadingMore: false,
        ),
      );
    } catch (e) {
      if (epoch != _epoch) return;
      state = state.copyWith(
        page: state.page.copyWith(
          loadingMore: false,
          loadMoreError: AppFailure.from(e),
        ),
      );
    }
  }

  void setQuery(DocumentArchiveQuery query) {
    if (query == state.query) return;
    state = state.copyWith(query: query);
    unawaited(load());
  }
}

/// `documents/orders/{id}` (teklif sürümleri ve belge verisi; belge sayfasında bir kez okunur).
final orderDocumentProvider = FutureProvider.autoDispose
    .family<OrderDocument, int>((ref, orderId) {
      ref.watch(currentUserIdProvider);
      return ref.read(customerMoreRepositoryProvider).orderDocument(orderId);
    });

/// Üretilecek belge.
@immutable
sealed class DocRequest {
  const DocRequest();

  DocKind get kind;

  /// Cihazdaki dosya adı (çevrimdışı bulmak için önceden bilinir).
  String get fileName;

  /// Ekranda: "Sipariş formu", "Fiyat teklifi v2".
  String get label;
}

final class OrderDocRequest extends DocRequest {
  const OrderDocRequest(this.orderId, this.orderNumber);
  final int orderId;
  final String orderNumber;
  @override
  DocKind get kind => DocKind.order;
  @override
  String get fileName => kind.fileName(orderNumber);
  @override
  String get label => 'Sipariş formu';

  @override
  bool operator ==(Object other) =>
      other is OrderDocRequest && other.orderId == orderId;
  @override
  int get hashCode => Object.hash('order', orderId);
}

final class QuoteDocRequest extends DocRequest {
  const QuoteDocRequest(this.orderId, this.orderNumber, this.version);
  final int orderId;
  final String orderNumber;
  final int version;
  @override
  DocKind get kind => DocKind.quote;
  @override
  String get fileName => kind.fileName(DocCodes.quote(orderNumber, version));
  @override
  String get label => 'Fiyat teklifi v$version';

  @override
  bool operator ==(Object other) =>
      other is QuoteDocRequest &&
      other.orderId == orderId &&
      other.version == version;
  @override
  int get hashCode => Object.hash('quote', orderId, version);
}

final class ReconciliationDocRequest extends DocRequest {
  const ReconciliationDocRequest(this.orderId, this.orderNumber);
  final int orderId;
  final String orderNumber;
  @override
  DocKind get kind => DocKind.reconciliation;
  @override
  String get fileName => kind.fileName(orderNumber);
  @override
  String get label => 'Teslimat mutabakatı';

  @override
  bool operator ==(Object other) =>
      other is ReconciliationDocRequest && other.orderId == orderId;
  @override
  int get hashCode => Object.hash('reconciliation', orderId);
}

final class ReceiptDocRequest extends DocRequest {
  const ReceiptDocRequest(this.shipmentId);
  final int shipmentId;
  @override
  DocKind get kind => DocKind.receipt;
  @override
  String get fileName => kind.fileName(DocCodes.receipt(shipmentId));
  @override
  String get label => 'Teslim tutanağı, ${DocCodes.receipt(shipmentId)}';

  @override
  bool operator ==(Object other) =>
      other is ReceiptDocRequest && other.shipmentId == shipmentId;
  @override
  int get hashCode => Object.hash('receipt', shipmentId);
}

final class WaybillDocRequest extends DocRequest {
  const WaybillDocRequest(this.shipmentId);
  final int shipmentId;
  @override
  DocKind get kind => DocKind.waybill;
  @override
  String get fileName => kind.fileName(DocCodes.shipment(shipmentId));
  @override
  String get label => 'Sevk belgesi, ${DocCodes.shipment(shipmentId)}';

  @override
  bool operator ==(Object other) =>
      other is WaybillDocRequest && other.shipmentId == shipmentId;
  @override
  int get hashCode => Object.hash('waybill', shipmentId);
}

/// Üretilmiş belge.
@immutable
class GeneratedDoc {
  const GeneratedDoc({
    required this.fileName,
    required this.bytes,
    required this.title,
    this.fromCache = false,
    this.savedAt,
  });

  final String fileName;
  final Uint8List bytes;
  final String title;

  /// Bağlantı yok; cihazda saklanan son sürüm açıldı.
  final bool fromCache;
  final DateTime? savedAt;
}

/// Belgeleri cihazda üretir (web görünümlerinin portu), saklar ve çevrimdışı açar.
final documentPdfServiceProvider = Provider<DocumentPdfService>(
  (ref) => DocumentPdfService(ref),
);

class DocumentPdfService {
  DocumentPdfService(this.ref);

  final Ref ref;

  CustomerMoreRepository get _repo => ref.read(customerMoreRepositoryProvider);
  PdfCache get _cache => ref.read(pdfCacheProvider);
  String? get _user => ref.read(currentUserIdProvider);

  DocContext get _ctx =>
      DocContext(portalBaseUrl: ref.read(appEnvProvider).portalBaseUrl);

  /// Belge tanımı (testler ve önizleme).
  Future<DocSpec> spec(DocRequest r) async {
    switch (r) {
      case OrderDocRequest(:final orderId):
        return DocBuilders.order(await _repo.orderDocument(orderId), _ctx);
      case QuoteDocRequest(:final orderId, :final version):
        final spec = DocBuilders.quote(
          await _repo.orderDocument(orderId),
          _ctx,
          version: version,
        );
        if (spec == null) {
          throw const NotFoundFailure(
            message: 'Bu sipariş için fiyat teklifi bulunamadı.',
          );
        }
        return spec;
      case ReconciliationDocRequest(:final orderId):
        final doc = await _repo.orderDocument(orderId);
        if (!doc.canReconcile) {
          throw const BusinessFailure(
            'Mutabakat yalnızca onaylanmış ve sevkiyatı olan siparişte oluşturulur.',
          );
        }
        return DocBuilders.reconciliation(doc, _ctx);
      case ReceiptDocRequest(:final shipmentId):
        final doc = await _repo.shipmentDocument(shipmentId);
        if (doc.shipment.isCancelled) {
          throw const BusinessFailure(
            'İptal edilmiş sevkiyat için teslim tutanağı oluşturulmaz.',
          );
        }
        return DocBuilders.receipt(doc, _ctx);
      case WaybillDocRequest(:final shipmentId):
        return DocBuilders.waybill(
          await _repo.shipmentDocument(shipmentId),
          _ctx,
        );
    }
  }

  /// Sunucudan güncel veriyle üretir ve saklar; bağlantı yoksa saklanan son sürümü açar.
  Future<GeneratedDoc> generate(DocRequest r) async {
    try {
      final spec = await this.spec(r);
      final bytes = await DocRenderer.render(spec);
      final user = _user;
      if (user != null) await _cache.write(user, spec.fileName, bytes);
      return GeneratedDoc(
        fileName: spec.fileName,
        bytes: bytes,
        title: '${spec.title}, ${spec.code}',
      );
    } catch (e) {
      final user = _user;
      if (user != null && isConnectivityFailure(e)) {
        final bytes = await _cache.read(user, r.fileName);
        if (bytes != null) {
          final info = await _cache.info(user, r.fileName);
          return GeneratedDoc(
            fileName: r.fileName,
            bytes: bytes,
            title: r.label,
            fromCache: true,
            savedAt: info?.savedAt,
          );
        }
      }
      throw AppFailure.from(e);
    }
  }

  /// Cihazda saklanan sürüm (yoksa null).
  Future<CachedPdf?> cached(DocRequest r) async {
    final user = _user;
    return user == null ? null : _cache.info(user, r.fileName);
  }

  Future<List<CachedPdf>> cachedAll() async {
    final user = _user;
    return user == null ? const [] : _cache.list(user);
  }
}

/// Belge için cihazdaki kayıt (sayfada "Cihazda kayıtlı" rozeti).
final cachedDocProvider = FutureProvider.autoDispose
    .family<CachedPdf?, DocRequest>((ref, r) {
      ref.watch(currentUserIdProvider);
      return ref.read(documentPdfServiceProvider).cached(r);
    });
