import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/media/attachment_gallery.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../approvals/api.dart';
import '../application/payments_providers.dart';
import '../copy.dart';
import '../data/payment_models.dart';
import 'payments_page.dart';
import 'widgets/payment_cards.dart';
import 'widgets/status_sheets.dart';

/// Ödeme ayrıntısı (spec A.4 A5; tasarım v3 "Akış"): itilen başlıkta sipariş no; gövde cari adı
/// (`display`) ve yöntem satırı, durum satırı (çip + vade ipucu; durum değişince solup büyüyerek
/// yenilenir), **kahraman kart** (tutar, Vade / Yöntem / Son gün; yükselerek gelir), sonra beyaz
/// kartlarda ödeme bilgileri, portföy kaydı, siparişe geçiş, belgeler ve durum geçmişi — kartlar art
/// arda yükselerek gelir. Alt rıhtım: "Tahsil edildi olarak işaretle" (birincil, izinliyse), "Durumu
/// değiştir", "Belgeyi kontrol et" (StationPayments Düzenler + payment.status.update; yalnızca
/// `allowedTransitions`).
class PaymentDetailPage extends ConsumerWidget {
  const PaymentDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentDetailProvider(orderId));
    final d = async.valueOrNull;
    Future<void> refresh() async {
      ref.invalidate(paymentDetailProvider(orderId));
      try {
        await ref.read(paymentDetailProvider(orderId).future);
      } catch (_) {}
    }

    if (d == null) {
      return AppScaffold(
        title: PaymentsCopy.detailTitle,
        body: async.hasError
            ? Center(
                child: SingleChildScrollView(
                  child: A5FailureView(
                    failure: AppFailure.from(async.error!),
                    onRetry: refresh,
                    notFoundTitle: PaymentsCopy.notFoundTitle,
                  ),
                ),
              )
            : const _Skeleton(),
      );
    }

    final policy = ref.watch(accessPolicyProvider);
    final features = ref.watch(appConfigProvider).features;
    final online = ref.watch(isOnlineProvider);
    final canChange =
        policy.can(Pg.stationPayments, Perm.edit) &&
        policy.hasCap(Caps.paymentStatusUpdate) &&
        d.allowedTransitions.isNotEmpty;
    final orderRoute = AppRoutes.bayiOrder(d.orderId);
    final canOpenOrder = RouteAccess.isAllowed(orderRoute, policy, features);
    final t = context.aknText;
    final c = context.akn;
    final row = d.row;

    Future<void> change({PaymentStatus? initial}) async {
      final message = await showPaymentStatusSheet(
        context,
        orderId: orderId,
        initial: initial,
      );
      if (message != null && context.mounted) {
        AppToast.success(message, context: context);
      }
    }

    Future<void> openInstrument(Instrument i) async {
      final message = await showInstrumentSheet(
        context,
        instrument: i,
        canChange: canChangeInstruments(policy),
      );
      if (message != null && context.mounted) {
        AppToast.success(message, context: context);
      }
    }

    void openDocuments([int index = 0]) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => AttachmentViewerPage(
            attachments: d.documents,
            initialIndex: index,
          ),
        ),
      );
    }

    final facts = <Widget>[
      // Siparişe gidilebiliyorsa durumu "Siparişi aç" satırında yazar.
      if (!canOpenOrder)
        FactRow(
          label: 'Sipariş durumu',
          value: row.orderStatusLabel ?? row.orderStatus.label,
        ),
      if (row.financeLabel != null)
        FactRow(
          label: 'Finans',
          value: row.financeLabel!,
          tone: AknStatus.finance(row.financeStatus).tone,
        ),
      // Taksitli ödemede plakanın üçüncü göstergesi taksittir; son gün buraya iner.
      if (row.installments != null &&
          row.installments! > 1 &&
          row.dueDate != null)
        FactRow(label: 'Son ödeme günü', value: Fmt.longDate(row.dueDate)),
      for (final l in d.detailLines) FactRow(label: l.label, value: l.value),
    ];

    return AppScaffold(
      // v4 §3.2: itilmiş sayfa nesnenin türüyle adlanır; kaydırınca carinin adı.
      title: PaymentsCopy.detailTitle,
      collapsedTitle: row.customerTitle,
      refreshing: async.isLoading,
      actionBar: _dock(
        context,
        detail: d,
        canChange: canChange,
        online: online,
        onChange: change,
        onCheckDocument: openDocuments,
      ),
      body: PullToRefresh(
        onRefresh: refresh,
        child: StaggerScope(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              FadeUp(offset: 10, child: _Header(detail: d)),
              if (row.displayAmount != null)
                // Kahraman kart ilk açılışta yükselip büyüyerek gelir.
                FadeUp(
                  offset: 24,
                  scale: 0.94,
                  duration: AknMotion.heroRise,
                  curve: AknMotion.emphasizedCurve,
                  child: _AmountPlate(detail: d),
                )
              else
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: AknBanner(
                    message: 'Tutar, bayi teklif verince belli olur.',
                  ),
                ),
              if (d.missingRequiredDocument)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: AknBanner(
                    tone: AknTone.warn,
                    message:
                        '${d.documentKindLabel ?? d.uploadKind.label} henüz yüklenmedi. Bu yöntemde belge zorunlu; yüklenince ödeme kontrole düşer.',
                    actionLabel: canChange && online ? 'Belge ekle' : null,
                    onAction: canChange && online ? change : null,
                  ),
                ),
              if (d.notice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: AknBanner(message: d.notice!),
                ),
              if (facts.isNotEmpty)
                StaggerItem(
                  index: 0,
                  child: LedgerSection(
                    title: 'Ödeme bilgileri',
                    child: FactList(facts: facts),
                  ),
                ),
              if (d.instrument != null)
                StaggerItem(
                  index: 1,
                  child: LedgerSection(
                    title: 'Portföy kaydı',
                    padded: false,
                    child: InstrumentRowCard(
                      instrument: d.instrument!,
                      showCustomer: false,
                      onTap: () => openInstrument(d.instrument!),
                    ),
                  ),
                ),
              if (canOpenOrder)
                StaggerItem(
                  index: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: LedgerItem(
                      index: 0,
                      child: AknListTile(
                        leading: ExcludeSemantics(
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(AknRadius.sm),
                            ),
                            child: Icon(
                              PhosphorIconsRegular.receipt,
                              size: 19,
                              color: c.ink,
                            ),
                          ),
                        ),
                        title: PaymentsCopy.openOrder,
                        subtitle: [
                          row.orderNumber,
                          ?row.orderStatusLabel,
                        ].join(', '),
                        showChevron: true,
                        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                        onTap: () => context.push(orderRoute),
                      ),
                    ),
                  ),
                ),
              StaggerItem(
                index: 3,
                child: LedgerSection(
                  title: 'Belgeler',
                  count: d.documents.isEmpty ? null : d.documents.length,
                  subtitle: d.documentKindLabel == null
                      ? null
                      : 'Bu yöntemin belgesi ${lowerFirst(d.documentKindLabel!)}${d.documentRequired ? ', zorunlu' : ''}.',
                  child: d.documents.isEmpty
                      ? Text(
                          'Bu ödemeye henüz belge eklenmedi.',
                          style: t.bodySmall.copyWith(color: c.dim),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < d.documents.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              _DocumentTile(
                                attachment: d.documents[i],
                                onTap: () => openDocuments(i),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              if (d.history.isNotEmpty)
                StaggerItem(
                  index: 4,
                  child: LedgerSection(
                    title: 'Durum geçmişi',
                    child: StepTimeline(
                      steps: adaptSteps(context, [
                        for (final h in d.history.reversed)
                          TimelineStep(
                            title: h.title,
                            subtitle: [
                              'Önceki durum: ${lowerFirst(h.fromTitle)}',
                              ?h.changedByDisplay,
                              ?h.note,
                            ].join('\n'),
                            time: shortStamp(h.changedAt),
                            state: h.toStatus == PaymentStatus.bounced
                                ? TimelineState.failed
                                : TimelineState.done,
                            icon: AknStatus.payment(h.toStatus).icon,
                            content: h.attachmentPublicId == null
                                ? null
                                : Align(
                                    alignment: Alignment.centerLeft,
                                    child: AknButton.ghost(
                                      label: 'Dayanak belgeyi aç',
                                      icon: PhosphorIconsRegular.paperclip,
                                      size: AknButtonSize.small,
                                      onPressed: () => openAttachmentById(
                                        context,
                                        publicId: h.attachmentPublicId!,
                                        known: d.documents,
                                      ),
                                    ),
                                  ),
                          ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Alt rıhtım (§6.1 `actionBar`, §7.14): bir birincil bölge. Yetkisi olmayana yalnızca belge
  /// görüntüleme kalır (belge yoksa rıhtım yok).
  Widget? _dock(
    BuildContext context, {
    required PaymentDetail detail,
    required bool canChange,
    required bool online,
    required Future<void> Function({PaymentStatus? initial}) onChange,
    required VoidCallback onCheckDocument,
  }) {
    final t = context.aknText;
    final hasDocs = detail.documents.isNotEmpty;
    final large = isLargeText(context);
    final checkDoc = hasDocs
        ? AknButton.secondary(
            label: PaymentsCopy.checkDocument,
            size: AknButtonSize.medium,
            expand: true,
            onPressed: onCheckDocument,
          )
        : null;
    if (!canChange) {
      return checkDoc;
    }
    final collect = detail.allowedTransitions.contains(PaymentStatus.collected);
    final changeButton = collect
        ? AknButton.secondary(
            label: PaymentsCopy.changeStatus,
            size: AknButtonSize.medium,
            expand: true,
            onPressed: online ? () => onChange() : null,
          )
        : AknButton(
            label: PaymentsCopy.changeStatus,
            expand: true,
            onPressed: online ? () => onChange() : null,
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!online)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(PaymentsCopy.offline, style: t.bodySmall),
          ),
        if (collect) ...[
          AknButton(
            label: PaymentsCopy.markCollected,
            expand: true,
            onPressed: online
                ? () => onChange(initial: PaymentStatus.collected)
                : null,
          ),
          const SizedBox(height: 8),
        ],
        if (checkDoc != null && collect && !large)
          Row(
            children: [
              Expanded(child: changeButton),
              const SizedBox(width: 8),
              Expanded(child: checkDoc),
            ],
          )
        else
          changeButton,
        if (checkDoc != null && !collect && !large) ...[
          const SizedBox(height: 8),
          checkDoc,
        ],
      ],
    );
  }
}

/// Gövdenin başı (tasarım v3): cari adı `display`, yöntem satırı, durum satırı (çip + vade ipucu;
/// durum değişince solup büyüyerek yenilenir).
class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final PaymentDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final row = detail.row;
    final status = AknStatus.payment(
      row.paymentStatus,
    ).withLabel(row.paymentStatusLabel);
    final overdue = row.isOverdue || row.overdueDays > 0;
    final hint = row.dueHint;
    final line = [
      if (row.methodName != null) '${row.methodName} ile ödeme',
      if (row.createdAt != null) 'sipariş ${dueDay(row.createdAt)}',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Nesne başlığı (§6.1) kök başlık gibi en çok 1,5× büyür.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: Semantics(
              header: true,
              child: Text(row.customerTitle, style: t.display),
            ),
          ),
          if (line.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(line, style: t.body.copyWith(color: c.dim)),
          ],
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: AknMotion.of(context, AknMotion.base),
            switchInCurve: AknMotion.standard,
            switchOutCurve: AknMotion.exit,
            layoutBuilder: (current, previous) => Stack(
              alignment: AlignmentDirectional.topStart,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                alignment: AlignmentDirectional.centerStart.resolve(
                  Directionality.of(context),
                ),
                scale: animation.drive(Tween<double>(begin: 0.92, end: 1)),
                child: child,
              ),
            ),
            child: AknStatusLine(
              key: ValueKey((row.paymentStatus, hint)),
              lamp: AknLamp.style(status),
              trailing: hint == null
                  ? null
                  : DueHint(
                      text: dueHintText(hint),
                      tone: dueTone(overdue: overdue, due: row.dueDate),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ödemenin plakası (§5.2, §7.14): tutar (kuruş birim tarzında), kural, Vade / Yöntem / Son gün.
class _AmountPlate extends StatelessWidget {
  const _AmountPlate({required this.detail});

  final PaymentDetail detail;

  @override
  Widget build(BuildContext context) {
    final row = detail.row;
    final amount = row.displayAmount!;
    final whole = amount.truncate();
    final kurus = ((amount - whole).abs() * 100).round();
    final title = switch (row.paymentStatus) {
      _ when row.isEstimate => 'Tahmini tutar',
      PaymentStatus.collected => 'Tahsil edilen tutar',
      PaymentStatus.refunded => 'İade edilen tutar',
      PaymentStatus.bounced => 'Karşılıksız çıkan tutar',
      PaymentStatus.cancelled => 'İptal edilen tutar',
      _ => 'Tahsil edilecek tutar',
    };
    final term = row.termDays;
    final installments = row.installments ?? 0;
    // Vade / Yöntem / Son gün (§7.14); bilinmeyen gösterge yerine durum gelir — plakada boş çizgi yok.
    final readouts = [
      if (term != null)
        PlateReadout(
          label: 'Vade',
          value: term == 0 ? 'Peşin' : '$term',
          unit: term == 0 ? null : 'gün',
        ),
      if (row.methodName != null)
        PlateReadout(label: 'Yöntem', value: row.methodName!),
      if (installments > 1)
        PlateReadout(label: 'Taksit', value: '$installments', unit: 'taksit')
      else if (row.dueDate != null)
        PlateReadout(label: 'Son gün', value: dueDay(row.dueDate)),
    ];
    if (readouts.length < 3) {
      readouts.add(PlateReadout(label: 'Durum', value: row.displayStatusLabel));
    }
    return AknPlate(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      semanticLabel: '$title ${Fmt.money(amount)}',
      head: PlateHead(
        icon: PhosphorIconsRegular.wallet,
        title: title,
        period: row.isEstimate ? 'teklif bekleniyor' : null,
      ),
      figure: PlateFigure(
        value: Fmt.integer(whole),
        decimals: ',${kurus.toString().padLeft(2, '0')}',
        unit: '₺',
        semanticLabel: Fmt.money(amount),
      ),
      below: plateReadouts(context, readouts),
    );
  }
}

/// Belge kutusu (§6.27): görselse küçük resim, değilse belge simgesi; dokununca görüntüleyici.
class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.attachment, required this.onTap});

  final Attachment attachment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final meta = [
      ?a.uploadedByName,
      if (a.createdAt != null) shortStamp(a.createdAt),
    ].join(', ');
    return AttachmentTile(
      fileName: a.fileName,
      kindLabel: a.kindLabel,
      sizeBytes: a.sizeBytes > 0 ? a.sizeBytes : null,
      contentType: a.contentType,
      subtitle: meta.isEmpty ? null : meta,
      thumbnail: a.isImage ? _Thumb(publicId: a.publicId) : null,
      // Büyük yazıda "Görüntüle" düğmesi satıra sığmaz; aynı eylem kısa sözle.
      actionLabel: isLargeText(context) ? 'Aç' : null,
      onTap: onTap,
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.publicId});

  final String publicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final bytes = ref.watch(
      attachmentBytesProvider((publicId: publicId, approvalId: null)),
    );
    return ColoredBox(
      color: c.surfaceAlt,
      child: bytes.maybeWhen(
        data: (b) => Image.memory(
          b,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: 120,
          errorBuilder: (_, _, _) =>
              Icon(PhosphorIconsRegular.image, color: c.dim, size: 22),
        ),
        orElse: () => Icon(PhosphorIconsRegular.image, color: c.dim, size: 22),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: const [
        SkeletonBox(height: 30, width: 240, radius: 6),
        SizedBox(height: 10),
        SkeletonBox(height: 14, width: 180),
        SizedBox(height: 20),
        SkeletonBox(height: 14, width: 120),
        SizedBox(height: 16),
        SkeletonBox(height: 196, radius: 20),
        SizedBox(height: 28),
        SkeletonBox(height: 20, width: 160),
        SizedBox(height: 16),
        SkeletonLine(),
        SizedBox(height: 14),
        SkeletonLine(widthFactor: 0.8),
        SizedBox(height: 14),
        SkeletonLine(widthFactor: 0.6),
      ],
    ),
  );
}
