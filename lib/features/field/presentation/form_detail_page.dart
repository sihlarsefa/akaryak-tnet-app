import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/pdf/akn_pdf.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/validators.dart';
import '../application/field_access.dart';
import '../application/field_detail_controllers.dart';
import '../copy.dart';
import '../data/field_models.dart';
import '../data/field_pdf.dart';
import 'widgets/field_widgets.dart';

/// Saha formu ayrıntısı (spec A.4 A6 "Formlarım"; tasarım v3): başlıkta cari ve durum lambaları,
/// ekranın tek plakası (form tutarı yükselerek gelir, rakam döner), ardından gruplanmış bilgi
/// kartları (Satırlar, Kârlılık, Not, Ödeme ve tedarik, Onay izi, Belgeler) sırayla belirir. Dış / iç
/// belge (PDF paylaş, yazdır), e-posta, "Finans ek bilgi istedi → Yanıtla", "Dönüşümü yeniden dene".
class FieldFormDetailPage extends ConsumerWidget {
  const FieldFormDetailPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fieldFormDetailProvider(id));
    final detail = async.valueOrNull;
    final access = ref.watch(fieldAccessProvider);
    if (detail == null) {
      return AppScaffold(
        title: 'Saha formu',
        body: async.hasError
            ? _errorBody(context, ref, AppFailure.from(async.error!))
            : const _DetailSkeleton(),
      );
    }
    final form = detail.form;
    return AppScaffold(
      title: form.formNumber,
      refreshing: async.isRefreshing,
      actions: [
        AknIconButton(
          icon: PhosphorIconsRegular.export,
          semanticLabel: 'Sipariş formunu paylaş',
          onPressed: () => _showDocuments(context, ref, form, access),
        ),
      ],
      body: PullToRefresh(
        onRefresh: () =>
            ref.read(fieldFormDetailProvider(id).notifier).refresh(),
        child: FieldStaggeredList(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _Hero(form: form),
            ..._banners(context, ref, form, access),
            _LinesCard(detail: detail, access: access),
            if (form.netProfit != null ||
                form.formProfitPercent != null ||
                form.minProfitPercent != null)
              _CostCard(form: form),
            if (form.note != null)
              FieldSectionCard(
                title: 'Not',
                icon: PhosphorIconsRegular.note,
                child: Text(form.note!, style: context.aknText.body),
              ),
            _PaymentCard(form: form),
            _TrailCard(form: form),
            _DocumentsCard(form: form, access: access),
          ],
        ),
      ),
      actionBar: _actions(context, ref, form, access),
    );
  }

  Widget _errorBody(BuildContext context, WidgetRef ref, AppFailure f) =>
      switch (f) {
        NotFoundFailure() => const EmptyState(
          title: FieldCopy.notFoundTitle,
          message: FieldCopy.notFoundMessage,
          illustration: AknIllustration.search,
        ),
        ForbiddenFailure() => const EmptyState(
          title: FieldCopy.forbiddenTitle,
          message: FieldCopy.forbiddenMessage,
          illustration: AknIllustration.error,
        ),
        _ => ErrorState(
          offline: f is OfflineFailure,
          message: f is OfflineFailure ? null : f.message,
          onRetry: () => ref.invalidate(fieldFormDetailProvider(id)),
        ),
      };

  List<Widget> _banners(
    BuildContext context,
    WidgetRef ref,
    FieldForm f,
    FieldAccess access,
  ) {
    const m = EdgeInsets.fromLTRB(20, 12, 20, 0);
    final out = <Widget>[];
    switch (f.status) {
      case FieldOrderFormStatus.pendingApproval:
        out.add(
          AknBanner(
            margin: m,
            tone: AknTone.warn,
            icon: PhosphorIconsRegular.hourglassHigh,
            title: 'Onay bekliyor',
            message: [
              FieldLevels.waitingText(
                f.requiredApprovalLevel,
                barem: f.pricingModel == FieldPricingModel.barem,
              ),
              if (f.financeStatus.isAwaitingDecision)
                'Finans onayı paralel yürüyor.',
            ].join(' '),
          ),
        );
      case FieldOrderFormStatus.rejected:
      case FieldOrderFormStatus.cancelled:
        out.add(
          AknBanner(
            margin: m,
            tone: AknTone.danger,
            title: f.displayStatus,
            message: f.decisionText ?? 'Gerekçe girilmedi.',
          ),
        );
      case FieldOrderFormStatus.converted:
        out.add(
          const AknBanner(
            margin: m,
            tone: AknTone.ok,
            title: 'Siparişe dönüştü',
            message:
                'Teklif müşteri onayına gönderildi; sipariş bundan sonra normal akışla (müşteri onayı, sevkiyat, teslim) ilerler.',
          ),
        );
      default:
        break;
    }
    if (f.awaitingFinance) {
      out.add(
        AknBanner(
          margin: m,
          tone: AknTone.warn,
          icon: PhosphorIconsRegular.bank,
          title: f.financeStatusLabel ?? f.financeStatus.label,
          message:
              'Kârlılık onayı tamam; finans onayı bekleniyor. Finans onaylayınca siparişler otomatik açılır.'
              '${f.financeReasons == null ? '' : ' Gerekçe: ${f.financeReasons}'}',
        ),
      );
    }
    if (f.financeInfoOpen) {
      out.add(
        AknBanner(
          margin: m,
          tone: AknTone.warn,
          icon: PhosphorIconsRegular.chatCircleDots,
          title: 'Finans ek bilgi istedi',
          // Yer adı alt menünün kelimesi (v4 §3.2, B8); "Yanıtla" talebin yanıt alanını açar.
          message:
              'Onaylar’daki talebe not ve istenen belgeyle yanıt verin; yanıt gelince finans incelemesi sürer.',
          actionLabel: access.canOpenApprovals ? 'Yanıtla' : null,
          onAction: access.canOpenApprovals
              ? () => context.push(
                  '${AppRoutes.approval(f.financeApprovalRequestId!)}?reply=1',
                )
              : null,
        ),
      );
    }
    final conversion = f.conversionError;
    if (conversion != null) {
      out.add(
        AknBanner(
          margin: m,
          tone: AknTone.danger,
          icon: PhosphorIconsRegular.cloudWarning,
          title: 'Bazı satırlar siparişe dönüşemedi',
          message: access.canRetryConversion
              ? conversion
              : '$conversion Bayi yöneticiniz kontrol edecek.',
          actionLabel: access.canRetryConversion
              ? 'Dönüşümü yeniden dene'
              : null,
          onAction: access.canRetryConversion
              ? () => _retryConversion(context, ref)
              : null,
        ),
      );
    }
    return out;
  }

  Future<void> _retryConversion(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmSheet(
      context,
      title: 'Dönüşüm yeniden denensin mi?',
      message:
          'Açılmış siparişler korunur; kalan satırlar siparişe çevrilir ve teklifleri gönderilir.',
      confirmLabel: 'Yeniden dene',
      icon: PhosphorIconsRegular.arrowsClockwise,
    );
    if (!ok || !context.mounted) return;
    try {
      final r = await ref
          .read(fieldFormDetailProvider(id).notifier)
          .retryConversion();
      AppToast.success(
        r.message.isEmpty ? 'Dönüşüm tamamlandı.' : r.message,
        context: context.mounted ? context : null,
      );
    } on AppFailure catch (f) {
      AppToast.error(f.message, context: context.mounted ? context : null);
    }
  }

  Widget? _actions(
    BuildContext context,
    WidgetRef ref,
    FieldForm f,
    FieldAccess access,
  ) {
    final edit = f.canEdit && access.canEditForm;
    final submit = f.canSubmit && access.canCreateForm;
    final cancel = f.canCancel && access.canEditForm;
    if (!edit && !submit && !cancel) return null;
    // Alt çubuk yalnızca içeriği kadar yer kaplar (genişleyen düğmeler satırı uzatmasın).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionBar(id: id, form: f, edit: edit, submit: submit, cancel: cancel),
      ],
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({
    required this.id,
    required this.form,
    required this.edit,
    required this.submit,
    required this.cancel,
  });

  final int id;
  final FieldForm form;
  final bool edit;
  final bool submit;
  final bool cancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    final ctrl = ref.read(fieldFormDetailProvider(id).notifier);

    Future<void> doSubmit() async {
      final ok = await showConfirmSheet(
        context,
        title: 'Form onaya gönderilsin mi?',
        message:
            'Gönderilen form düzenlenemez. Kârlılık kuralı uygunsa form doğrudan siparişe dönüşür.',
        confirmLabel: 'Onaya gönder',
        icon: PhosphorIconsRegular.paperPlaneRight,
      );
      if (!ok || !context.mounted) return;
      try {
        final r = await ctrl.submit();
        if (!context.mounted) return;
        AppToast.success(
          r.message.isEmpty ? 'Form gönderildi.' : r.message,
          context: context,
        );
      } on AppFailure catch (f) {
        if (context.mounted) AppToast.error(f.message, context: context);
      }
    }

    Future<void> doCancel() async {
      final note = await _askNote(
        context,
        title: 'Form iptal edilsin mi?',
        hint: 'İptal nedeni (isteğe bağlı)',
        confirm: 'İptal et',
      );
      if (note == null || !context.mounted) return;
      try {
        final m = await ctrl.cancel(note: note.isEmpty ? null : note);
        if (context.mounted) AppToast.success(m, context: context);
      } on AppFailure catch (f) {
        if (context.mounted) AppToast.error(f.message, context: context);
      }
    }

    return Row(
      children: [
        if (cancel)
          AknIconButton(
            icon: PhosphorIconsRegular.prohibit,
            semanticLabel: 'Formu iptal et',
            onPressed: online ? doCancel : null,
          ),
        if (edit)
          Expanded(
            child: AknButton.secondary(
              label: 'Düzenle',
              icon: PhosphorIconsRegular.pencilSimple,
              expand: true,
              onPressed: () => context.push('${AppRoutes.fieldForm(id)}/edit'),
            ),
          ),
        if (edit && submit) const SizedBox(width: 12),
        if (submit)
          Expanded(
            child: AknButton(
              label: 'Onaya gönder',
              icon: PhosphorIconsRegular.paperPlaneRight,
              expand: true,
              onPressedAsync: online ? doSubmit : null,
              showSuccess: false,
            ),
          ),
      ],
    );
  }
}

/// Not isteyen onay sayfası (iptal, merkeze ilet). Dönüş: not (boş olabilir) ya da vazgeçilince null.
Future<String?> _askNote(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirm,
}) async {
  final controller = TextEditingController();
  final result = await showAppSheet<String>(
    context: context,
    title: title,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AknTextField(
          controller: controller,
          label: 'Not',
          hint: hint,
          maxLines: 3,
          minLines: 2,
          maxLength: 1000,
        ),
        const SizedBox(height: 16),
        AknButton.danger(
          label: confirm,
          expand: true,
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
        ),
        AknButton.ghost(
          label: 'Vazgeç',
          expand: true,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<void> _showDocuments(
  BuildContext context,
  WidgetRef ref,
  FieldForm form,
  FieldAccess access,
) => showAppSheet<void>(
  context: context,
  title: 'Sipariş formu',
  subtitle: 'Müşteriye imzalatılan dış belge; maliyet içermez.',
  builder: (_) => _DocumentActions(form: form, access: access, sheet: true),
);

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard({required this.form, required this.access});

  final FieldForm form;
  final FieldAccess access;

  @override
  Widget build(BuildContext context) => FieldSectionCard(
    title: 'Belgeler',
    icon: PhosphorIconsRegular.filePdf,
    child: _DocumentActions(form: form, access: access),
  );
}

class _DocumentActions extends ConsumerStatefulWidget {
  const _DocumentActions({
    required this.form,
    required this.access,
    this.sheet = false,
  });

  final FieldForm form;
  final FieldAccess access;
  final bool sheet;

  @override
  ConsumerState<_DocumentActions> createState() => _DocumentActionsState();
}

class _DocumentActionsState extends ConsumerState<_DocumentActions> {
  bool get _costsVisible =>
      widget.form.netProfit != null ||
      widget.form.minProfitPercent != null ||
      widget.form.purchaseTermDays != null ||
      widget.form.lines.any((l) => l.bindirimM3 != null);

  bool get _canEmail =>
      widget.access.canEmailForm &&
      widget.form.status != FieldOrderFormStatus.draft &&
      !widget.form.isClosed;

  Future<void> _pdf({required bool internal, required bool print}) async {
    final ctrl = ref.read(fieldFormDetailProvider(widget.form.id).notifier);
    try {
      final doc = await ctrl.document(internal: internal);
      final bytes = await FieldOrderPdf.build(doc);
      if (print) {
        await AknPdf.printDocument(bytes, FieldOrderPdf.fileName(doc));
      } else {
        await AknPdf.share(bytes, FieldOrderPdf.fileName(doc));
      }
    } on AppFailure catch (f) {
      if (!mounted) return;
      AppToast.error(
        f is ForbiddenFailure
            ? 'İç sipariş formu için maliyet görme yetkisi gerekir.'
            : f.message,
        context: context,
      );
    } catch (_) {
      if (mounted) {
        AppToast.error(
          'Belge hazırlanamadı. Tekrar deneyin.',
          context: context,
        );
      }
    }
  }

  Future<void> _email() async {
    final controller = TextEditingController();
    String? error;
    final address = await showAppSheet<String>(
      context: context,
      title: 'E-posta ile gönder',
      subtitle: 'Dış belge (maliyet içermez) PDF olarak gönderilir.',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AknTextField(
              controller: controller,
              label: 'E-posta',
              hint: 'Boş bırakırsanız carinin kayıtlı e-postası',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              errorText: error,
            ),
            const SizedBox(height: 16),
            AknButton(
              label: 'Gönder',
              icon: PhosphorIconsRegular.paperPlaneRight,
              expand: true,
              onPressed: () {
                final v = controller.text.trim();
                final e = v.isEmpty ? null : Validators.email(v);
                if (e != null) {
                  setSheet(() => error = e);
                  return;
                }
                Navigator.of(ctx).pop(v);
              },
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (address == null || !mounted) return;
    try {
      final message = await ref
          .read(fieldFormDetailProvider(widget.form.id).notifier)
          .email(toEmail: address.isEmpty ? null : address);
      if (mounted) {
        AppToast.success(
          message.isEmpty
              ? 'Sipariş formu gönderilmek üzere sıraya alındı.'
              : message,
          context: context,
        );
      }
    } on AppFailure catch (f) {
      if (mounted) AppToast.error(f.message, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AknListTile(
          title: 'Sipariş formu (PDF)',
          subtitle: 'Paylaş: WhatsApp, e-posta, Dosyalar',
          leadingIcon: PhosphorIconsRegular.export,
          padding: const EdgeInsets.symmetric(vertical: 8),
          onTap: () => _pdf(internal: false, print: false),
        ),
        AknListTile(
          title: 'Yazdır',
          leadingIcon: PhosphorIconsRegular.printer,
          padding: const EdgeInsets.symmetric(vertical: 8),
          onTap: () => _pdf(internal: false, print: true),
        ),
        if (_costsVisible)
          AknListTile(
            title: 'İç sipariş formu',
            subtitle: 'Maliyet, kâr ve barem içerir; müşteriye verilmez',
            leadingIcon: PhosphorIconsRegular.lock,
            padding: const EdgeInsets.symmetric(vertical: 8),
            onTap: () => _pdf(internal: true, print: false),
          ),
        if (_canEmail)
          AknListTile(
            title: 'E-posta ile gönder',
            leadingIcon: PhosphorIconsRegular.envelopeSimple,
            padding: const EdgeInsets.symmetric(vertical: 8),
            onTap: _email,
          ),
      ],
    );
  }
}

/// Sayfanın başı (tasarım v3 §4): `display` başlıkta cari, altında form no, bayi ve temsilci; durum
/// lambaları; ardından ekranın tek plakası (beyaz, sıcak tonlu hero kartı): form tutarı (rakam döner),
/// kural, Toplam / Vade / Satır okumaları (sayaç gibi yerine oturur).
class _Hero extends StatelessWidget {
  const _Hero({required this.form});

  final FieldForm form;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final band = form.barem;
    final money = Fmt.number(form.totalAmount, minFraction: 2, maxFraction: 2);
    final comma = money.lastIndexOf(',');
    final whole = comma < 0 ? money : money.substring(0, comma);
    final decimals = comma < 0 ? null : money.substring(comma);
    final lamps = <Widget>[
      AknLamp.style(form.status.statusStyle.withLabel(form.statusLabel)),
      if (band != null && form.status == FieldOrderFormStatus.pendingApproval)
        FieldBandChip(
          band: FieldBand(key: band.bandKey, label: band.outcomeLabel),
        ),
      if (form.financeVisible)
        AknLamp.style(
          form.financeStatus.statusStyle.withLabel(form.financeStatusLabel),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  form.customerTitle,
                  style: t.display.copyWith(color: c.ink),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  form.formNumber,
                  ?form.stationTitle,
                  ?(form.salesRepresentativeName ?? form.createdByName),
                ].join(', '),
                style: t.bodySmall.copyWith(color: c.dim),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 8, children: lamps),
            ],
          ),
        ),
        AknPlate(
          margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          semanticLabel:
              'Form tutarı ${Fmt.money(form.totalAmount)}, toplam ${Fmt.liters(form.totalLiters)}, ${form.paymentTermDays == 0 ? 'peşin' : '${form.paymentTermDays} gün vade'}, ${form.lines.length} satır',
          head: PlateHead(
            icon: PhosphorIconsRegular.invoice,
            title: 'Form tutarı',
            period: form.createdAt == null
                ? null
                : fieldLowerFirst(Fmt.dayLabel(form.createdAt)),
          ),
          figure: PlateFigure(value: whole, decimals: decimals, unit: '₺'),
          below: FieldPlateReadouts(
            items: [
              PlateReadout(
                label: 'Toplam',
                value: Fmt.number(form.totalLiters, maxFraction: 3),
                unit: 'L',
              ),
              PlateReadout(
                label: 'Vade',
                value: form.paymentTermDays == 0
                    ? 'Peşin'
                    : '${form.paymentTermDays}',
                unit: form.paymentTermDays == 0 ? null : 'gün',
              ),
              PlateReadout(
                label: 'Satır',
                value: Fmt.integer(form.lines.length),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({required this.detail, required this.access});

  final FieldFormDetail detail;
  final FieldAccess access;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final form = detail.form;
    return FieldSectionCard(
      title: 'Satırlar',
      icon: PhosphorIconsRegular.listBullets,
      trailing: Text(
        '${form.lines.length} satır',
        style: t.caption.copyWith(color: c.dim),
      ),
      child: Column(
        children: [
          for (var i = 0; i < form.lines.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 1,
                  width: double.infinity,
                  child: ColoredBox(color: c.lineSoft),
                ),
              ),
            _LineRow(
              no: i + 1,
              line: form.lines[i],
              order: detail.orderOfLine(form.lines[i].id),
              canOpenOrder: access.canOpenBayiOrders,
            ),
          ],
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.no,
    required this.line,
    required this.order,
    required this.canOpenOrder,
  });

  final int no;
  final FieldFormLine line;
  final FieldLineOrder? order;
  final bool canOpenOrder;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    String pct(double? v) => v == null
        ? '—'
        : '${v >= 0 ? '+' : '−'}${Fmt.percent(v.abs(), maxFraction: 1)}';
    final orderNumber = order?.orderNumber ?? line.orderNumber;
    final orderId = order?.orderId ?? line.orderId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldTitleRow(
          title: Text(
            '$no. ${line.productName}',
            style: t.bodyStrong.copyWith(color: c.ink),
          ),
          trailing: AmountText(Fmt.money(line.amount)),
        ),
        const SizedBox(height: 2),
        Text(
          '${Fmt.liters(line.quantityLiters)} × ${Fmt.unitPrice(line.proposedUnitPrice)}',
          style: t.bodySmall.copyWith(color: c.ink),
        ),
        Text(
          '${line.deliveryPointName}, teslim ${Fmt.date(line.requestedDeliveryDate)}',
          style: t.bodySmall,
        ),
        if (line.tuprasDiffPercent != null ||
            line.pumpDiscountPercent != null) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (line.tuprasDiffPercent != null)
                'Tüpraş ${pct(line.tuprasDiffPercent)}',
              if (line.pumpDiscountPercent != null)
                (line.pumpDiscountPercent! < 0
                    ? 'Pompanın üstünde ${Fmt.percent(line.pumpDiscountPercent!.abs(), maxFraction: 1)}'
                    : 'Pompa iskontosu ${Fmt.percent(line.pumpDiscountPercent, maxFraction: 1)}'),
              if (line.tuprasOverridden) 'Tüpraş elle',
            ].join(', '),
            style: t.caption,
          ),
        ],
        if (orderNumber != null) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canOpenOrder && orderId != null)
                TextButton.icon(
                  onPressed: () => context.push(AppRoutes.bayiOrder(orderId)),
                  icon: const Icon(PhosphorIconsRegular.receipt, size: 18),
                  label: Text('Sipariş $orderNumber'),
                )
              else
                Text('Sipariş $orderNumber', style: t.label),
              if (order != null)
                StatusChip.style(
                  order!.status.statusStyle,
                  size: StatusChipSize.small,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CostCard extends StatelessWidget {
  const _CostCard({required this.form});

  final FieldForm form;

  @override
  Widget build(BuildContext context) => FieldSectionCard(
    title: 'Kârlılık (yalnızca bayi içi)',
    icon: PhosphorIconsRegular.lock,
    child: FieldFacts(
      facts: [
        (
          'Form kâr %',
          form.formProfitPercent == null && form.minProfitPercent == null
              ? null
              : Fmt.percent(
                  form.formProfitPercent ?? form.minProfitPercent,
                  maxFraction: 2,
                ),
        ),
        (
          'Net kâr (KDV hariç)',
          form.netProfit == null ? null : Fmt.money(form.netProfit),
        ),
        ('Barem', form.barem?.chipText),
      ],
    ),
  );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.form});

  final FieldForm form;

  @override
  Widget build(BuildContext context) => FieldSectionCard(
    title: 'Ödeme ve tedarik',
    icon: PhosphorIconsRegular.money,
    child: FieldFacts(
      facts: [
        ('Ödeme yöntemi', form.paymentMethodName ?? 'Belirtilmemiş'),
        (
          'Vade',
          form.paymentTermDays == 0 ? 'Peşin' : '${form.paymentTermDays} gün',
        ),
        ('Sevk tarihi', form.shipDate == null ? null : Fmt.date(form.shipDate)),
        (
          'Ödeme tarihi',
          form.paymentDueDate == null ? null : Fmt.date(form.paymentDueDate),
        ),
        ('Anadağıtım', form.distributorName),
        ('Terminal', form.terminalName),
        (
          'Nakliye',
          form.transportTotal == null || form.transportTotal == 0
              ? (form.isCombinedShipment ? 'Birleştirilmiş sevkiyat' : null)
              : Fmt.money(form.transportTotal),
        ),
        (
          'Teminat oranı',
          form.collateralRatioPercent == null
              ? null
              : Fmt.percent(form.collateralRatioPercent),
        ),
        if (form.strategicExceptionRequested)
          ('Stratejik istisna', form.exceptionJustification ?? 'İstendi'),
      ],
    ),
  );
}

/// Onay izi (zaman çizelgesi).
class _TrailCard extends StatelessWidget {
  const _TrailCard({required this.form});

  final FieldForm form;

  @override
  Widget build(BuildContext context) {
    final steps = <TimelineStep>[
      TimelineStep(
        title: 'Oluşturuldu',
        subtitle: form.createdByName,
        time: form.createdAt == null ? null : Fmt.dateTime(form.createdAt),
        state: TimelineState.done,
        icon: PhosphorIconsRegular.notePencil,
      ),
      if (form.submittedAt != null)
        TimelineStep(
          title: 'Gönderildi',
          subtitle: form.requiredApprovalLevel == null
              ? null
              : 'Gereken: ${FieldLevels.label(form.requiredApprovalLevel)}',
          time: Fmt.dateTime(form.submittedAt),
          state: TimelineState.done,
          icon: PhosphorIconsRegular.paperPlaneRight,
        ),
      if (form.submittedAt != null && form.financeVisible)
        TimelineStep(
          title:
              'Finans: ${form.financeStatusLabel ?? form.financeStatus.label}',
          subtitle: form.financeReasons,
          state: switch (form.financeStatus) {
            OrderFinanceStatus.approved ||
            OrderFinanceStatus.conditionallyApproved => TimelineState.done,
            OrderFinanceStatus.rejected => TimelineState.failed,
            OrderFinanceStatus.infoRequested => TimelineState.warning,
            _ => TimelineState.current,
          },
          icon: PhosphorIconsRegular.bank,
        ),
      for (final a in form.approvals)
        TimelineStep(
          title: '${a.decisionLabel}, ${a.levelLabel}',
          subtitle: [?a.approverName, ?a.note].join(', '),
          time: a.decidedAt == null ? null : Fmt.dateTime(a.decidedAt),
          state: a.isRejection ? TimelineState.failed : TimelineState.done,
          icon: a.isRejection
              ? PhosphorIconsFill.xCircle
              : PhosphorIconsFill.checkCircle,
        ),
      if (form.status == FieldOrderFormStatus.pendingApproval)
        TimelineStep(
          title: 'Onay bekleniyor',
          subtitle: FieldLevels.label(form.requiredApprovalLevel),
          state: TimelineState.current,
          icon: PhosphorIconsRegular.hourglassHigh,
        ),
      if (form.status == FieldOrderFormStatus.cancelled)
        TimelineStep(
          title: 'İptal edildi',
          subtitle: form.decidedByName,
          time: form.decidedAt == null ? null : Fmt.dateTime(form.decidedAt),
          state: TimelineState.failed,
          icon: PhosphorIconsRegular.prohibit,
        ),
      if (form.status == FieldOrderFormStatus.converted)
        TimelineStep(
          title: 'Siparişe dönüştü',
          subtitle: '${form.convertedOrderIds.length} sipariş',
          state: TimelineState.done,
          icon: PhosphorIconsFill.checkCircle,
        ),
    ];
    return FieldSectionCard(
      title: 'Onay izi',
      icon: PhosphorIconsRegular.lineSegments,
      child: StepTimeline(
        steps: fieldLargeText(context) ? _timeInSubtitle(steps) : steps,
        dense: true,
      ),
    );
  }

  /// Büyük yazıda sağdaki saat sütunu sığmaz: saat alt satıra taşınır.
  static List<TimelineStep> _timeInSubtitle(List<TimelineStep> steps) => [
    for (final s in steps)
      TimelineStep(
        title: s.title,
        subtitle: [
          if ((s.subtitle ?? '').isNotEmpty) s.subtitle!,
          ?s.time,
        ].join(', '),
        state: s.state,
        icon: s.icon,
        content: s.content,
      ),
  ];
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonList(
    itemCount: 3,
    lines: 4,
    leading: false,
    header: Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: SkeletonBox(height: 200, radius: 20),
    ),
  );
}
