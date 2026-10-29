import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/media/image_capture.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/routing/app_location.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/cm_access.dart';
import '../../application/image_source.dart';
import '../../application/requests_controller.dart';
import '../../data/order_requests.dart';
import '../cm_widgets.dart';

/// Talep ayrıntısı: satır başına sonuç (oluşan sipariş ya da neden), ödeme ve — siparişler oluştuktan
/// sonra — ödeme belgesinin durumu (çek / senet görseli). Bekleyen kendi talebi geri çekilebilir.
/// Karar verebilen (şirket yöneticisi, onaylayan) için karar çubuğu "Karar ver": talebin kendi onay
/// kaydını açar (v4 B2; karar düğmeleri orada).
class RequestDetailPage extends ConsumerStatefulWidget {
  const RequestDetailPage({super.key, required this.requestId});

  final int requestId;

  @override
  ConsumerState<RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends ConsumerState<RequestDetailPage> {
  bool _cancelling = false;

  /// "Karar ver"e dokunuldu, onay kaydı aranıyor.
  bool _opening = false;

  int get _id => widget.requestId;

  /// Talebin karar sayfası (v4 B2): talebin onay kaydı (`/approvals/{id}?focus=request`), yoksa
  /// süzülmüş Onaylar. Onaylar bu kullanıcılarda alt menü sekmesidir: tam ekran bu sayfadan sekme
  /// yolu `push` edilirse kabuk ikinci kez kurulur (QA SC-01); sekmeye `go` ile geçilir, ayrıntı
  /// `push` ile açılır ([openAppLocation] kuralı) ve dönüşte talep yeniden okunur (karar verildiyse
  /// çubuk kalkar). Onaylar listesi henüz yükleniyorsa kısa bir süre beklenir.
  Future<void> _openDecision() async {
    if (_opening) return;
    var found = ref.read(requestApprovalProvider(_id));
    if (found.loading) {
      setState(() => _opening = true);
      final loaded = Completer<void>();
      final sub = ref.listenManual(requestApprovalProvider(_id), (_, next) {
        if (!next.loading && !loaded.isCompleted) loaded.complete();
      });
      await loaded.future.timeout(const Duration(seconds: 6), onTimeout: () {});
      sub.close();
      if (!mounted) return;
      setState(() => _opening = false);
      found = ref.read(requestApprovalProvider(_id));
    }
    if (!mounted) return;
    final location = requestDecisionLocation(found.id);
    final router = GoRouter.of(context);
    if (isShellLocation(router, location)) {
      router.go(location);
      return;
    }
    await router.push<Object?>(location);
    if (!mounted) return;
    ref.invalidate(requestsControllerProvider);
    await _refresh();
  }

  Future<void> _refresh() async {
    ref.invalidate(orderRequestProvider(_id));
    try {
      await ref.read(orderRequestProvider(_id).future);
    } catch (_) {}
  }

  Future<void> _cancel() async {
    final ok = await showConfirmSheet(
      context,
      title: 'Talebi geri çekelim mi?',
      message:
          'Talep onaya gönderilmez; gerekirse yeniden sipariş verebilirsiniz.',
      confirmLabel: 'Geri çek',
      destructive: true,
      icon: PhosphorIconsRegular.arrowUUpLeft,
    );
    if (!ok || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final message = await ref.read(requestCommandsProvider).cancel(_id);
      if (!mounted) return;
      AppToast.success(message, context: context);
      ref.invalidate(requestsControllerProvider);
    } catch (e) {
      if (mounted) {
        showFailureToast(context, e);
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(orderRequestProvider(_id));
    final online = ref.watch(isOnlineProvider);
    final policy = ref.watch(accessPolicyProvider);
    final r = async.valueOrNull;
    final canCancel = r != null && r.canCancel && policy.cmRequestCancel;
    final canDecide =
        r != null &&
        r.status == CustomerOrderRequestStatus.pending &&
        r.canDecide;
    // Onay kaydı sayfa açılırken aranmaya başlar (Onaylar › Bende listesi, aynı önbellek).
    if (canDecide) ref.watch(requestApprovalProvider(_id));
    return AppScaffold(
      // v4 §3.2: çubukta nesnenin türü; talep numarası sayfada.
      title: 'Talep',
      collapsedTitle: r == null
          ? null
          : '${r.productsSummary}, ${Fmt.liters(r.totalLiters)}',
      refreshing: async.isLoading && r != null,
      actionBar: canDecide
          // v4 P3: kararın adımı çubukta; onay ve ret talebin onay kaydında verilir.
          ? ActionBar.decision(
              primary: AknButton(
                label: 'Karar ver',
                loading: _opening,
                onPressed: () => unawaited(_openDecision()),
              ),
              caption: 'Onay talebi açılır; onaylayın ya da reddedin',
            )
          : canCancel
          ? cmBar(
              AknButton.secondary(
                label: 'Talebi geri çek',
                icon: PhosphorIconsRegular.arrowUUpLeft,
                expand: true,
                loading: _cancelling,
                onPressed: online && !_cancelling ? _cancel : null,
              ),
            )
          : null,
      body: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const LoadingView(message: 'Talep yükleniyor'),
        error: (e, _) =>
            CmFailureView(failure: AppFailure.from(e), onRetry: _refresh),
        data: (r) {
          // Bloklar açılışta sırayla yükselerek gelir.
          // Karar bekleyen talepte kararın yolu çubuktadır ("Karar ver"); sayfada ayrıca bant yok
          // (v4 §4 AknBanner: çubuğu tekrarlamaz).
          final blocks = <(String, Widget)>[
            ('hero', _Hero(request: r)),
            if (r.status != CustomerOrderRequestStatus.pending)
              ('decision', _DecisionCard(request: r)),
            ('lines', _LinesCard(request: r)),
            if (r.paymentDisplay != null || r.paymentDetails.isNotEmpty)
              ('payment', _PaymentCard(request: r)),
            if (r.hasOrders) ('doc', _PaymentDocCard(requestId: r.id)),
            if (r.note != null)
              (
                'note',
                CmSection(
                  title: 'Onaylayana not',
                  child: Text(
                    r.note!,
                    style: context.aknText.body.copyWith(
                      color: context.akn.text,
                    ),
                  ),
                ),
              ),
          ];
          return PullToRefresh(
            onRefresh: _refresh,
            child: CmRiseScope(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom: 24 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  for (final (i, (id, block)) in blocks.indexed)
                    CmRise(key: ValueKey(id), index: i, child: block),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Nesne başı (tasarım v3): `display` başlık ("Motorin, 12.000 L"; büyük yazıda litre birimiyle
/// aynı satırda kalır), kim / ne zaman, müşterinin gözünden durum lambası ve kahraman kart: tahmini
/// tutar (yoksa toplam litre), kural, okumalar (litre, satır, teslim).
class _Hero extends StatelessWidget {
  const _Hero({required this.request});

  final OrderRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final t = context.aknText;
    final c = context.akn;
    final lamp = AknStatus.companyRequestLamp(
      r.status,
      StatusViewer.customer(canDecide: r.canDecide),
      serverLabel: r.statusLabel,
    );
    final dates = [
      for (final l in r.lines)
        if (l.requestedDeliveryDate != null) l.requestedDeliveryDate!,
    ]..sort();
    final amount = r.estimatedAmount;
    final whole = amount?.truncate();
    final cents = amount == null
        ? null
        : ((amount - amount.truncate()) * 100).round().clamp(0, 99);
    final spoken = [
      amount == null
          ? 'Toplam ${Fmt.liters(r.totalLiters)}'
          : 'Tahmini tutar ${Fmt.money(amount)}',
      '${r.lines.length} satır',
      if (dates.isNotEmpty) 'teslim ${Fmt.longDate(dates.first)}',
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.5,
                child: Semantics(
                  header: true,
                  child: CmUnitText(
                    '${r.productsSummary}, ${Fmt.liters(r.totalLiters)}',
                    style: t.display.copyWith(color: c.ink),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (r.requestedByName.trim().isNotEmpty) r.requestedByName,
                  if (r.createdAt != null) Fmt.dateTime(r.createdAt),
                ].join(', '),
                style: t.bodySmall.copyWith(color: c.dim),
              ),
              const SizedBox(height: 14),
              AknLamp.status(lamp),
            ],
          ),
        ),
        CmPlate(
          semanticLabel: spoken,
          head: PlateHead(
            icon: PhosphorIconsRegular.invoice,
            title: amount == null ? 'Toplam miktar' : 'Tahmini tutar',
            period: amount == null ? null : 'bayinin güncel fiyatıyla',
          ),
          figure: amount == null
              ? PlateFigure(
                  value: Fmt.number(r.totalLiters, maxFraction: 3),
                  unit: 'L',
                )
              : PlateFigure(
                  value: Fmt.number(whole),
                  decimals: ',${cents.toString().padLeft(2, '0')}',
                  unit: '₺',
                ),
          readouts: [
            PlateReadout(
              label: 'Miktar',
              value: Fmt.number(r.totalLiters, maxFraction: 3),
              unit: 'L',
            ),
            PlateReadout(label: 'Satır', value: '${r.lines.length}'),
            PlateReadout(
              label: 'Teslim',
              value: dates.isEmpty ? Fmt.dash : Fmt.dayMonth(dates.first),
            ),
          ],
        ),
      ],
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.request});

  final OrderRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final t = context.aknText;
    final c = context.akn;
    final (title, tone) = switch (r.status) {
      CustomerOrderRequestStatus.approved => ('Onaylandı', AknTone.ok),
      CustomerOrderRequestStatus.rejected => ('Reddedildi', AknTone.danger),
      CustomerOrderRequestStatus.cancelled => ('Geri çekildi', AknTone.neutral),
      _ => ('Karar', AknTone.neutral),
    };
    return CmSection(
      title: 'Karar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknLamp(label: title, tone: tone, solid: tone == AknTone.ok),
          const SizedBox(height: 4),
          if (r.decidedByName != null)
            FactRow(
              label: r.status == CustomerOrderRequestStatus.rejected
                  ? 'Reddeden'
                  : 'Onaylayan',
              value: r.decidedByName!,
            ),
          if (r.decidedAt != null)
            FactRow(label: 'Tarih', value: Fmt.dateTime(r.decidedAt)),
          if (r.decisionNote != null) ...[
            const SizedBox(height: 4),
            Text('Gerekçe', style: t.label.copyWith(color: c.dim)),
            Text(r.decisionNote!, style: t.body.copyWith(color: c.text)),
          ],
          if (r.status == CustomerOrderRequestStatus.approved)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Onaylanan her satır ayrı sipariş olarak bayiye iletildi.',
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ),
        ],
      ),
    );
  }
}

class _LinesCard extends ConsumerWidget {
  const _LinesCard({required this.request});

  final OrderRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final t = context.aknText;
    final c = context.akn;
    final policy = ref.watch(accessPolicyProvider);
    final approved = r.status == CustomerOrderRequestStatus.approved;
    final failed = r.failedLineCount;
    return CmSection(
      title: 'Satırlar',
      subtitle: '${r.lines.length} satır',
      bleed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknLedger(
            children: [
              for (final l in r.lines)
                _LineRow(line: l, showResult: approved || l.error != null),
            ],
          ),
          if (approved &&
              failed > 0 &&
              policy.can(Pg.customerCreateOrder, Perm.create))
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AknButton.secondary(
                    label: 'Başarısız satırları yeni siparişe aktar',
                    expand: true,
                    onPressed: () => context.push(
                      '${AppRoutes.orderNew}?fromRequest=${r.id}',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$failed satır sipariş olarak oluşturulamadı; sipariş ekranında düzeltip gönderebilirsiniz.',
                    style: t.bodySmall.copyWith(color: c.dim),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Talep satırı (kart içinde): ürün ve litre, nokta / teslim / bayi, tahmini ₺/L; sonuç lambası
/// ("Sipariş SIP-… oluştu" dokununca siparişi açar, "Oluşturulamadı: …" tehlike).
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.showResult});

  final OrderRequestLine line;
  final bool showResult;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final ordered = showResult && l.hasOrder;
    final failed = showResult && !l.hasOrder && l.error != null;
    final result = ordered
        ? 'Sipariş ${l.orderNumber ?? '#${l.orderId}'} oluştu'
        : (failed ? 'Oluşturulamadı: ${l.error}' : null);
    final subtitle = [
      l.deliveryPointName,
      if (l.requestedDeliveryDate != null)
        'teslim ${Fmt.dayMonth(l.requestedDeliveryDate)}',
      if (l.stationTitle.isNotEmpty) l.stationTitle,
    ].where((x) => x.isNotEmpty).join(', ');
    final title = '${l.productName}, ${Fmt.liters(l.quantityLiters)}';
    return AknListTile(
      padding: cmRowPadding,
      titleStyle: cmRowTitle(context),
      title: cmKeepUnits(title),
      subtitle: subtitle,
      meta: l.estimatedUnitPrice == null
          ? null
          : Fmt.unitPrice(l.estimatedUnitPrice),
      status: result == null
          ? null
          : AknLamp(label: result, tone: ordered ? AknTone.ok : AknTone.danger),
      showChevron: ordered,
      semanticLabel: [
        title,
        if (subtitle.isNotEmpty) subtitle,
        if (l.estimatedUnitPrice != null)
          'tahmini birim fiyat ${Fmt.unitPrice(l.estimatedUnitPrice)}',
        ?result,
        if (ordered) 'siparişi aç',
      ].join(', '),
      onTap: ordered ? () => context.push(AppRoutes.order(l.orderId!)) : null,
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.request});

  final OrderRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final t = context.aknText;
    return CmSection(
      title: 'Ödeme',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FactRow(label: 'Ödeme şekli', value: r.paymentDisplay ?? Fmt.dash),
          for (final d in r.paymentDetails)
            FactRow(label: d.label, value: d.value),
          const SizedBox(height: 4),
          Text(
            'Onayda siparişler bu ödemeyle oluşur; vadeli yöntemlerde bayinin finans onayı beklenir.',
            style: t.bodySmall.copyWith(color: context.akn.dim),
          ),
        ],
      ),
    );
  }
}

/// Siparişler oluştuktan sonra ödeme belgesi (çek / senet görseli, dekont) durumu ve yükleme.
class _PaymentDocCard extends ConsumerStatefulWidget {
  const _PaymentDocCard({required this.requestId});

  final int requestId;

  @override
  ConsumerState<_PaymentDocCard> createState() => _PaymentDocCardState();
}

class _PaymentDocCardState extends ConsumerState<_PaymentDocCard> {
  double? _progress;

  Future<void> _upload(PaymentUploadTarget target) async {
    final source = await showAppSheet<CaptureSource>(
      context: context,
      title: target.label,
      subtitle: 'Görseli çekin, galeriden ya da PDF olarak seçin',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknListTile(
            leadingIcon: PhosphorIconsRegular.camera,
            titleStyle: cmRowTitle(ctx),
            padding: const EdgeInsets.symmetric(vertical: 10),
            title: 'Fotoğraf çek',
            onTap: () => Navigator.of(ctx).pop(CaptureSource.camera),
          ),
          AknListTile(
            leadingIcon: PhosphorIconsRegular.images,
            titleStyle: cmRowTitle(ctx),
            padding: const EdgeInsets.symmetric(vertical: 10),
            title: 'Galeriden seç',
            onTap: () => Navigator.of(ctx).pop(CaptureSource.gallery),
          ),
          AknListTile(
            leadingIcon: PhosphorIconsRegular.filePdf,
            titleStyle: cmRowTitle(ctx),
            padding: const EdgeInsets.symmetric(vertical: 10),
            title: 'Dosya (PDF)',
            onTap: () => Navigator.of(ctx).pop(CaptureSource.file),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    final image = await ref
        .read(cmImagePickerProvider)
        .pick(context, source, target.kind);
    if (image == null || !mounted) return;
    setState(() => _progress = 0);
    try {
      await ref
          .read(requestCommandsProvider)
          .uploadPaymentDoc(
            widget.requestId,
            target,
            image,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (!mounted) return;
      AknHaptics.success();
      AppToast.success('${target.label} yüklendi.', context: context);
    } catch (e) {
      if (mounted) showFailureToast(context, e);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(requestPaymentDocProvider(widget.requestId));
    final policy = ref.watch(accessPolicyProvider);
    final online = ref.watch(isOnlineProvider);
    final t = context.aknText;
    return async.when(
      loading: () => const CmSection(
        title: 'Ödeme belgesi',
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (e, _) => CmSection(
        title: 'Ödeme belgesi',
        child: Text(
          'Belge durumu okunamadı. ${failureText(AppFailure.from(e))}',
          style: t.bodySmall.copyWith(color: context.akn.text),
        ),
      ),
      data: (state) {
        if (state == null) return const SizedBox.shrink();
        final target = state.target;
        if (state.uploaded) {
          return CmSection(
            title: 'Ödeme belgesi',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.label,
                  style: t.headline.copyWith(color: context.akn.ink),
                ),
                const SizedBox(height: 4),
                const AknLamp(label: 'Yüklendi', tone: AknTone.ok),
              ],
            ),
          );
        }
        final canUpload = target.canUpload && policy.cmPaymentUpload;
        return CmSection(
          title: 'Ödeme belgesi',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                target.label,
                style: t.headline.copyWith(color: context.akn.ink),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AknLamp(
                  label: target.required ? 'Bekleniyor' : 'İsteğe bağlı',
                  tone: target.required ? AknTone.brand : AknTone.neutral,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                target.message ??
                    (target.required
                        ? 'Teklif onayı için ${TurkishText.lower(target.label)} gerekir. Görseli yükleyin.'
                        : 'Dilerseniz ödeme belgesini ekleyebilirsiniz.'),
                style: t.bodySmall.copyWith(color: context.akn.dim),
              ),
              if (_progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress, minHeight: 4),
              ],
              if (canUpload) ...[
                const SizedBox(height: 12),
                AknButton(
                  label: 'Görsel yükle',
                  icon: PhosphorIconsRegular.uploadSimple,
                  expand: true,
                  loading: _progress != null,
                  onPressed: online && _progress == null
                      ? () => _upload(target)
                      : null,
                ),
              ],
              if (target.orderId != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: AknButton.ghost(
                    label: 'Siparişi aç',
                    onPressed: () =>
                        context.push(AppRoutes.order(target.orderId!)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
