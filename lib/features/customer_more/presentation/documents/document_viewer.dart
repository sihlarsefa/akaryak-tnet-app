import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/pdf/akn_pdf.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/documents_controller.dart';
import '../../copy.dart';
import '../../documents/doc_spec.dart';
import '../cm_widgets.dart';

/// Üretilen belgeyi gösterir (varsayılan: tam ekran önizleme). Testler kaydeden bir uygulama verir.
typedef DocOpener =
    Future<void> Function(BuildContext context, GeneratedDoc doc);

final cmDocOpenerProvider = Provider<DocOpener>(
  (ref) =>
      (context, doc) => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => DocumentViewerPage(doc: doc),
        ),
      ),
);

/// Belgeyi üretir (bekleme penceresiyle) ve açar. Çevrimdışıyken cihazdaki son sürümü açar.
Future<void> openGeneratedDocument(
  BuildContext context,
  WidgetRef ref,
  DocRequest request,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var closed = false;
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: AknCard(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Semantics(
              liveRegion: true,
              label: '${request.label} hazırlanıyor',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ChevronSpinner(size: 28),
                  const SizedBox(height: 12),
                  Text('${request.label} hazırlanıyor…'),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() => closed = true),
  );
  try {
    final doc = await ref.read(documentPdfServiceProvider).generate(request);
    if (!closed) navigator.pop();
    ref.invalidate(cachedDocProvider(request));
    if (!context.mounted) return;
    if (doc.fromCache) {
      AppToast.info(
        'Çevrimdışısınız; cihazda kayıtlı sürüm açıldı'
        '${doc.savedAt == null ? '' : ' (${Fmt.dateTime(doc.savedAt)})'}.',
        context: context,
      );
    }
    await ref.read(cmDocOpenerProvider)(context, doc);
  } catch (e) {
    if (!closed) navigator.pop();
    if (context.mounted) showFailureToast(context, e);
  }
}

/// Belge satırı: tür ikonu, ad ve "Cihazda kayıtlı" bilgisi.
class DocumentTile extends ConsumerWidget {
  const DocumentTile({
    super.key,
    required this.request,
    required this.onTap,
    this.padding,
  });

  final DocRequest request;
  final VoidCallback onTap;

  /// Satır dolgusu (alt sayfada kenar boşluğu sayfadan gelir); varsayılan ledger satırı.
  final EdgeInsetsGeometry? padding;

  static IconData iconOf(DocKind k) => switch (k) {
    DocKind.order => Icons.description_outlined,
    DocKind.quote => Icons.request_quote_outlined,
    DocKind.reconciliation => Icons.fact_check_outlined,
    DocKind.receipt => Icons.assignment_turned_in_outlined,
    DocKind.waybill => Icons.local_shipping_outlined,
  };

  /// Belge satırı (tasarım v2 §6.27): 24 px soluk simge, ad ve durum ("PDF oluşturulur" ya da
  /// "Cihazda kayıtlı, 21.10.2026 14:20"); kenardan kenara ledger satırı.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(cachedDocProvider(request)).valueOrNull;
    final sub = cached == null
        ? 'PDF olarak oluşturulur'
        : '${CmCopy.savedOnDevice}, ${Fmt.dateTime(cached.savedAt)}';
    return AknListTile(
      leadingIcon: iconOf(request.kind),
      title: request.label,
      subtitle: sub,
      meta: 'PDF',
      padding: padding,
      onTap: onTap,
      semanticLabel: '${request.label}, $sub',
    );
  }
}

/// Tam ekran PDF önizleme: paylaş ve yazdır.
class DocumentViewerPage extends StatelessWidget {
  const DocumentViewerPage({super.key, required this.doc});

  final GeneratedDoc doc;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: doc.title,
      subtitle: doc.fromCache ? CmCopy.savedOnDevice : null,
      showBell: false,
      leading: IconButton(
        tooltip: 'Kapat',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      actions: [
        AknIconButton(
          icon: Icons.ios_share_rounded,
          semanticLabel: 'Paylaş',
          onPressed: () => AknPdf.share(doc.bytes, doc.fileName),
        ),
        AknIconButton(
          icon: Icons.print_rounded,
          semanticLabel: 'Yazdır',
          onPressed: () => AknPdf.printDocument(doc.bytes, doc.fileName),
        ),
      ],
      body: PdfPreview(
        build: (_) async => doc.bytes,
        pdfFileName: doc.fileName,
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        loadingWidget: const Center(child: ChevronSpinner(size: 28)),
      ),
    );
  }
}
