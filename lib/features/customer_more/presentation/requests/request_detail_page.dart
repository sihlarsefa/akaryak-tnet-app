import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/media/image_capture.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/offline/connectivity.dart';
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
class RequestDetailPage extends ConsumerStatefulWidget {
  const RequestDetailPage({super.key, required this.requestId});

  final int requestId;

  @override
  ConsumerState<RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends ConsumerState<RequestDetailPage> {
  bool _cancelling = false;

  int get _id => widget.requestId;

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
      icon: Icons.undo_rounded,
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
    return AppScaffold(
      title: r?.number ?? 'Talep',
      subtitle: 'Şirket içi sipariş talebi',
      refreshing: async.isLoading && r != null,
      actionBar: canCancel
          ? cmBar(
              AknButton.secondary(
                label: 'Talebi geri çek',
                icon: Icons.undo_rounded,
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
        data: (r) => PullToRefresh(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Hero(request: r),
              if (r.status == CustomerOrderRequestStatus.pending && r.canDecide)
                AknBanner(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  tone: AknTone.warn,
                  title: 'Bu talep kararınızı bekliyor',
                  message:
                      'Onay ya da ret kararını Onaylarım ekranından verebilirsiniz.',
                  actionLabel: "Onaylarım'da aç",
                  onAction: () => context.push(AppRoutes.approvals),
                ),
              if (r.status != CustomerOrderRequestStatus.pending)
                _DecisionCard(request: r),
              _LinesCard(request: r),
              if (r.paymentDisplay != null || r.paymentDetails.isNotEmpty)
                _PaymentCard(request: r),
              if (r.hasOrders) _PaymentDocCard(requestId: r.id),
              if (r.note != null)
                CmSection(
                  title: 'Onaylayana not',
                  child: Text(r.note!, style: context.aknText.body),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.request});

  final OrderRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    return AknHeroPanel(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(r.number, style: t.headline),
                  ),
                  StatusChip.style(
                    r.status.statusStyle.withLabel(r.statusLabel),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AmountText(Fmt.liters(r.totalLiters), large: true),
              if (r.estimatedAmount != null)
                Text(
                  'Tahmini ${Fmt.money(r.estimatedAmount)} · bayinin güncel fiyatıyla',
                  style: t.bodySmall,
                ),
              const SizedBox(height: 8),
              Text(
                '${r.requestedByName} · ${Fmt.dateTime(r.createdAt)}',
                style: t.caption,
              ),
            ],
          );
        },
      ),
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
    final (title, tone) = switch (r.status) {
      CustomerOrderRequestStatus.approved => ('Onaylandı', AknTone.ok),
      CustomerOrderRequestStatus.rejected => ('Reddedildi', AknTone.danger),
      CustomerOrderRequestStatus.cancelled => ('Geri çekildi', AknTone.neutral),
      _ => ('Karar', AknTone.neutral),
    };
    return CmSection(
      title: title,
      accent: tone == AknTone.neutral ? null : tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            Text('Gerekçe', style: t.label),
            Text(r.decisionNote!, style: t.body),
          ],
          if (r.status == CustomerOrderRequestStatus.approved)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Onaylanan her satır ayrı sipariş olarak bayiye iletildi.',
                style: t.caption,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < r.lines.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            _LineRow(
              line: r.lines[i],
              showResult: approved || r.lines[i].error != null,
            ),
          ],
          if (approved &&
              failed > 0 &&
              policy.can(Pg.customerCreateOrder, Perm.create)) ...[
            const SizedBox(height: 12),
            AknButton.secondary(
              label: 'Başarısız satırları yeni siparişe aktar',
              icon: Icons.playlist_add_rounded,
              expand: true,
              onPressed: () =>
                  context.push('${AppRoutes.orderNew}?fromRequest=${r.id}'),
            ),
            const SizedBox(height: 4),
            Text(
              '$failed satır sipariş olarak oluşturulamadı; sipariş ekranında düzeltip gönderebilirsiniz.',
              style: t.caption.copyWith(color: c.text),
            ),
          ],
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.showResult});

  final OrderRequestLine line;
  final bool showResult;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${l.productName} · ${Fmt.liters(l.quantityLiters)}',
          style: t.bodyStrong,
        ),
        Text(
          [
            l.deliveryPointName,
            if (l.requestedDeliveryDate != null)
              'teslim ${Fmt.date(l.requestedDeliveryDate)}',
            if (l.stationTitle.isNotEmpty) l.stationTitle,
          ].where((x) => x.isNotEmpty).join(' · '),
          style: t.bodySmall,
        ),
        if (l.estimatedUnitPrice != null)
          Text(
            'Tahmini birim fiyat ${Fmt.unitPrice(l.estimatedUnitPrice)}',
            style: t.caption,
          ),
        if (showResult) ...[
          const SizedBox(height: 6),
          if (l.hasOrder)
            Semantics(
              button: true,
              label:
                  'Sipariş ${l.orderNumber ?? l.orderId} oluştu, siparişi aç',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => context.push(AppRoutes.order(l.orderId!)),
                borderRadius: AknRadius.chip,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: c.ok.bg,
                    borderRadius: AknRadius.chip,
                    border: Border.all(color: c.ok.line),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: c.ok.fg,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sipariş ${l.orderNumber ?? '#${l.orderId}'} oluştu',
                          style: t.label.copyWith(color: c.ok.fg),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.ok.fg),
                    ],
                  ),
                ),
              ),
            )
          else if (l.error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: c.danger.bg,
                borderRadius: AknRadius.chip,
                border: Border.all(color: c.danger.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_rounded, size: 18, color: c.danger.fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Oluşturulamadı: ${l.error}',
                      style: t.bodySmall.copyWith(color: c.danger.fg),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
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
            style: t.caption,
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
            leadingIcon: Icons.photo_camera_rounded,
            title: 'Fotoğraf çek',
            onTap: () => Navigator.of(ctx).pop(CaptureSource.camera),
          ),
          AknListTile(
            leadingIcon: Icons.photo_library_rounded,
            title: 'Galeriden seç',
            onTap: () => Navigator.of(ctx).pop(CaptureSource.gallery),
          ),
          AknListTile(
            leadingIcon: Icons.picture_as_pdf_rounded,
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
          style: t.bodySmall,
        ),
      ),
      data: (state) {
        if (state == null) return const SizedBox.shrink();
        final target = state.target;
        if (state.uploaded) {
          return CmSection(
            title: 'Ödeme belgesi',
            accent: AknTone.ok,
            child: Row(
              children: [
                const StatusChip(
                  label: 'Yüklendi',
                  tone: AknTone.ok,
                  icon: Icons.check_circle_rounded,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(target.label, style: t.body)),
              ],
            ),
          );
        }
        final canUpload = target.canUpload && policy.cmPaymentUpload;
        return CmSection(
          title: 'Ödeme belgesi',
          accent: target.required ? AknTone.warn : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(
                    label: target.required ? 'Bekleniyor' : 'İsteğe bağlı',
                    tone: target.required ? AknTone.warn : AknTone.info,
                    icon: Icons.hourglass_top_rounded,
                  ),
                  Text(target.label, style: t.bodyStrong),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                target.message ??
                    (target.required
                        ? 'Teklif onayı için ${TurkishText.lower(target.label)} gerekir. Görseli yükleyin.'
                        : 'Dilerseniz ödeme belgesini ekleyebilirsiniz.'),
                style: t.bodySmall,
              ),
              if (_progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _progress, minHeight: 4),
              ],
              if (canUpload) ...[
                const SizedBox(height: 8),
                AknButton(
                  label: 'Görsel yükle',
                  icon: Icons.upload_rounded,
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
                    icon: Icons.receipt_long_rounded,
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
