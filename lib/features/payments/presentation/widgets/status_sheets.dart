import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../approvals/api.dart';
import '../../application/payments_providers.dart';
import '../../copy.dart';
import '../../data/payment_models.dart';

/// Ödeme durumu sayfası: yalnızca sunucunun izin verdiği geçişler (`allowedTransitions`), gerekçe
/// zorunlu durumlarda not (`noteRequiredFor`, en az 3 karakter), dayanak belge ("Dekont ekle").
Future<String?> showPaymentStatusSheet(
  BuildContext context, {
  required int orderId,
}) => showAppSheet<String>(
  context: context,
  title: 'Ödeme durumu',
  subtitle: 'Yalnızca bu ödemede izin verilen durumlar listelenir.',
  builder: (_) => PaymentStatusSheet(orderId: orderId),
);

class PaymentStatusSheet extends ConsumerStatefulWidget {
  const PaymentStatusSheet({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<PaymentStatusSheet> createState() => _PaymentStatusSheetState();
}

class _PaymentStatusSheetState extends ConsumerState<PaymentStatusSheet> {
  final _note = TextEditingController();
  PaymentStatus? _to;
  String? _attachmentId;
  bool _busy = false;

  /// Belge yüklendikten sonra kayıt yeniden okunuyor ("Durumu kaydet" kapalı).
  bool _refreshing = false;
  ActionOutcome? _problem;
  Map<String, String> _errors = const {};

  UploadTarget get _target =>
      UploadTarget(AttachmentOwnerType.order, widget.orderId);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _addDocument(PaymentDetail d) async {
    final file = await ref
        .read(a5FileSourceProvider)
        .pick(context, d.uploadKind);
    if (file == null || !mounted) return;
    final a = await ref
        .read(uploadsProvider(_target).notifier)
        .add(file, d.uploadKind);
    if (a != null && mounted) setState(() => _attachmentId = a.publicId);
  }

  /// Bekleyen ödemeye yöntemin belgesi yüklenince sunucu ödemeyi kendiliğinden "Belge yüklendi" yapar
  /// ve siparişin sürüm belirtecini yeniler. Kayıt yeniden okunmazsa ilk kayıt eski belirteçle 409
  /// alırdı; izin verilen durumlar da değişir. Okuma sürerken kayıt düğmesi kapalıdır.
  Future<void> _refreshAfterUpload(PaymentStatus before) async {
    if (!mounted) return;
    setState(() => _refreshing = true);
    final fresh = await _reload();
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (fresh != null && fresh.row.paymentStatus != before) {
      AppToast.info(
        'Belge eklendi; ödeme durumu "${fresh.row.paymentStatusLabel ?? fresh.row.paymentStatus.label}" olarak güncellendi.',
        context: context,
      );
    }
  }

  Future<void> _submit(PaymentDetail d) async {
    final to = _to;
    if (to == null || _busy || _refreshing) return;
    final note = _note.text.trim();
    if (d.noteRequiredFor.contains(to) && note.length < 3) {
      setState(
        () => _errors = {
          'note': '"${to.label}" için gerekçe girin (en az 3 karakter).',
        },
      );
      return;
    }
    if (ref
        .read(uploadsProvider(_target))
        .any((u) => u.phase == UploadPhase.uploading)) {
      AppToast.info(
        'Belge yüklemesi sürüyor; birazdan kaydedin.',
        context: context,
      );
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
      _errors = const {};
    });
    final outcome = await ref
        .read(paymentActionsProvider)
        .changeStatus(d, to, note: note, attachmentPublicId: _attachmentId);
    if (!mounted) return;
    switch (outcome) {
      case ActionDone(:final message):
        AknHaptics.success();
        Navigator.of(context).pop(message);
      case ActionInvalid(:final fieldErrors):
        setState(() {
          _busy = false;
          _errors = fieldErrors;
          _problem = fieldErrors.isEmpty ? outcome : null;
        });
      default:
        setState(() {
          _busy = false;
          _problem = outcome;
        });
    }
  }

  /// Kaydı yeniden okur; seçilen durum artık izinli değilse seçim kalkar. Okunan kayıt (hata: null).
  Future<PaymentDetail?> _reload() async {
    setState(() => _problem = null);
    ref.invalidate(paymentDetailProvider(widget.orderId));
    try {
      final fresh = await ref.read(
        paymentDetailProvider(widget.orderId).future,
      );
      if (!mounted) return fresh;
      if (_to != null && !fresh.allowedTransitions.contains(_to)) {
        setState(() => _to = null);
      }
      return fresh;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(paymentDetailProvider(widget.orderId));
    final d = async.valueOrNull;
    // Yeni yüklenen her belgeden sonra (ilk yükleme ya da "tekrar dene") kayıt tazelenir.
    ref.listen<List<UploadItem>>(uploadsProvider(_target), (prev, next) {
      final before = {
        for (final u in prev ?? const <UploadItem>[])
          if (u.attachment != null) u.localId,
      };
      final uploaded = next.any(
        (u) => u.attachment != null && !before.contains(u.localId),
      );
      final current = ref
          .read(paymentDetailProvider(widget.orderId))
          .valueOrNull;
      if (uploaded && current != null) {
        unawaited(_refreshAfterUpload(current.row.paymentStatus));
      }
    });
    if (d == null) return const SizedBox(height: 160, child: LoadingView());
    final t = context.aknText;
    final c = context.akn;
    final online = ref.watch(isOnlineProvider);
    final uploads = ref.watch(uploadsProvider(_target));
    final current = AknStatus.payment(
      d.row.paymentStatus,
    ).withLabel(d.row.paymentStatusLabel);
    final to = _to;
    final noteRequired = to != null && d.noteRequiredFor.contains(to);
    final docs = [
      ...d.documents,
      for (final u in uploads)
        if (u.attachment != null &&
            !d.documents.any((x) => x.publicId == u.attachment!.publicId))
          u.attachment!,
    ];
    final problem = _problem;
    final addLabel = d.uploadKind == AttachmentKind.transferReceipt
        ? 'Dekont ekle'
        : '${d.uploadKind.label} ekle';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Şu an', style: t.label),
            const SizedBox(width: 8),
            StatusChip.style(current, size: StatusChipSize.small),
            const Spacer(),
            Flexible(
              child: Text(
                d.row.orderNumber,
                style: t.caption,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        if (problem != null) ...[
          const SizedBox(height: 12),
          _Problem(outcome: problem, onReload: _reload),
        ],
        const SizedBox(height: 16),
        Text('Yeni durum', style: t.label),
        const SizedBox(height: 8),
        for (final s in d.allowedTransitions)
          ChoiceCard(
            title: s.label,
            subtitle: PaymentsCopy.paymentHint(s),
            leadingIcon: AknStatus.payment(s).icon,
            selected: to == s,
            margin: const EdgeInsets.only(bottom: 8),
            onTap: () => setState(() {
              _to = s;
              _errors = {..._errors}
                ..remove('toStatus')
                ..remove('note');
            }),
          ),
        if (_errors['toStatus'] != null)
          Text(
            _errors['toStatus']!,
            style: t.captionStrong.copyWith(color: c.danger.fg),
          ),
        const SizedBox(height: 8),
        AknTextField(
          controller: _note,
          label: noteRequired ? 'Gerekçe' : 'Not (isteğe bağlı)',
          requiredMark: noteRequired,
          helper: noteRequired ? 'En az 3 karakter' : null,
          errorText: _errors['note'],
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        Text('Dayanak belge (isteğe bağlı)', style: t.label),
        const SizedBox(height: 6),
        if (docs.isNotEmpty)
          FilterChips<String>(
            padding: EdgeInsets.zero,
            options: [
              for (final a in docs)
                FilterOption(
                  value: a.publicId,
                  label: '${a.kindLabel} · ${a.fileName}',
                  icon: AknStatus.attachmentKind(a.kind).icon,
                ),
            ],
            selected: {?_attachmentId},
            onChanged: (s) =>
                setState(() => _attachmentId = s.isEmpty ? null : s.first),
          ),
        if (_errors['attachmentPublicId'] != null)
          Text(
            _errors['attachmentPublicId']!,
            style: t.captionStrong.copyWith(color: c.danger.fg),
          ),
        UploadTiles(target: _target),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: AknButton.secondary(
            label: addLabel,
            icon: Icons.add_a_photo_rounded,
            size: AknButtonSize.small,
            onPressed: () => unawaited(_addDocument(d)),
          ),
        ),
        const SizedBox(height: 16),
        if (!online)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              PaymentsCopy.offline,
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        AknButton(
          label: to == null ? 'Durum seçin' : 'Durumu kaydet',
          semanticLabel: to == null
              ? null
              : 'Durumu "${to.label}" olarak kaydet',
          icon: Icons.check_rounded,
          expand: true,
          size: AknButtonSize.large,
          loading: _busy || _refreshing,
          loadingLabel: _refreshing ? 'Ödeme güncelleniyor' : 'Gönderiliyor',
          onPressed: to != null && online && !_busy && !_refreshing
              ? () => _submit(d)
              : null,
        ),
      ],
    );
  }
}

/// Çek / senet sayfası: belge ayrıntısı ve (yetkiliye) izinli durum geçişleri.
Future<String?> showInstrumentSheet(
  BuildContext context, {
  required Instrument instrument,
  required bool canChange,
}) => showAppSheet<String>(
  context: context,
  title: '${instrument.displayKindLabel} · ${instrument.headline}',
  subtitle: instrument.customerTitle,
  builder: (_) => InstrumentSheet(instrument: instrument, canChange: canChange),
);

class InstrumentSheet extends ConsumerStatefulWidget {
  const InstrumentSheet({
    super.key,
    required this.instrument,
    required this.canChange,
  });

  final Instrument instrument;

  /// StationPayments Düzenler + (payment.instrument.manage ya da payment.status.update).
  final bool canChange;

  @override
  ConsumerState<InstrumentSheet> createState() => _InstrumentSheetState();
}

class _InstrumentSheetState extends ConsumerState<InstrumentSheet> {
  final _note = TextEditingController();
  InstrumentStatus? _to;
  bool _busy = false;
  ActionOutcome? _problem;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final to = _to;
    final i = widget.instrument;
    if (to == null || _busy) return;
    final note = _note.text.trim();
    if (i.noteRequiredFor.contains(to) && note.length < 3) {
      setState(
        () => _errors = {
          'note': '"${to.label}" için açıklama girin (en az 3 karakter).',
        },
      );
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
      _errors = const {};
    });
    final outcome = await ref
        .read(paymentActionsProvider)
        .changeInstrumentStatus(i, to, note: note);
    if (!mounted) return;
    switch (outcome) {
      case ActionDone(:final message):
        AknHaptics.success();
        Navigator.of(context).pop(message);
      case ActionInvalid(:final fieldErrors):
        setState(() {
          _busy = false;
          _errors = fieldErrors;
          _problem = fieldErrors.isEmpty ? outcome : null;
        });
      default:
        setState(() {
          _busy = false;
          _problem = outcome;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final i = widget.instrument;
    final online = ref.watch(isOnlineProvider);
    final status = AknStatus.instrument(i.status).withLabel(i.statusLabel);
    final to = _to;
    final noteRequired = to != null && i.noteRequiredFor.contains(to);
    final actions = widget.canChange
        ? i.allowedTransitions
        : const <InstrumentStatus>[];
    final problem = _problem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusChip.style(status),
            if (i.dueHint != null)
              StatusChip(
                label: i.dueHint!,
                tone: i.isOverdue ? AknTone.danger : AknTone.neutral,
                icon: Icons.event_rounded,
              ),
          ],
        ),
        const SizedBox(height: 8),
        AknCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              FactRow(label: 'Tutar', value: Fmt.money(i.amount)),
              FactRow(label: 'Vade', value: Fmt.date(i.dueDate)),
              if (i.serialNo != null)
                FactRow(label: 'Seri no', value: i.serialNo!),
              if (i.bankName != null)
                FactRow(
                  label: 'Banka',
                  value: [i.bankName!, ?i.branchName].join(' · '),
                ),
              if (i.drawerName != null)
                FactRow(label: 'Keşideci', value: i.drawerName!),
              if (i.debtorName != null)
                FactRow(label: 'Borçlu', value: i.debtorName!),
              if (i.guarantorName != null)
                FactRow(label: 'Kefil', value: i.guarantorName!),
              if (i.orderNumber != null)
                FactRow(label: 'Sipariş', value: i.orderNumber!),
              if (i.note != null) FactRow(label: 'Not', value: i.note!),
            ],
          ),
        ),
        if (problem != null) ...[
          const SizedBox(height: 12),
          _Problem(outcome: problem, onReload: null),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Durumu değiştir', style: t.label),
          const SizedBox(height: 8),
          for (final s in actions)
            ChoiceCard(
              title: s.label,
              subtitle: PaymentsCopy.instrumentHint(s),
              leadingIcon: AknStatus.instrument(s).icon,
              selected: to == s,
              margin: const EdgeInsets.only(bottom: 8),
              onTap: () => setState(() {
                _to = s;
                _errors = {..._errors}..remove('note');
              }),
            ),
          if (_errors['toStatus'] != null)
            Text(
              _errors['toStatus']!,
              style: t.captionStrong.copyWith(color: c.danger.fg),
            ),
          const SizedBox(height: 8),
          AknTextField(
            controller: _note,
            label: noteRequired ? 'Açıklama' : 'Not (isteğe bağlı)',
            requiredMark: noteRequired,
            helper: noteRequired ? 'En az 3 karakter' : null,
            errorText: _errors['note'],
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          if (!online)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                PaymentsCopy.offline,
                style: t.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          AknButton(
            label: to == null ? 'Durum seçin' : 'Durumu kaydet',
            semanticLabel: to == null
                ? null
                : 'Durumu "${to.label}" olarak kaydet',
            icon: Icons.check_rounded,
            expand: true,
            loading: _busy,
            onPressed: to != null && online && !_busy ? _submit : null,
          ),
        ] else if (!widget.canChange && i.isOpen) ...[
          const SizedBox(height: 12),
          Text(
            'Durum değişikliği için muhasebe yetkisi gerekir.',
            style: t.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.outcome, required this.onReload});

  final ActionOutcome outcome;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) => switch (outcome) {
    ActionConflict(:final message) => AknBanner(
      tone: AknTone.warn,
      title: 'Bu kayıt sizden sonra güncellendi',
      message: message,
      actionLabel: onReload == null ? null : 'Yenile',
      onAction: onReload,
    ),
    ActionUnverified(:final message) => AknBanner(
      tone: AknTone.warn,
      title: 'Sonuç doğrulanamadı',
      message: message,
      actionLabel: onReload == null ? null : 'Yenile',
      onAction: onReload,
    ),
    ActionFailed(:final message) => AknBanner(
      tone: AknTone.danger,
      message: message,
    ),
    ActionInvalid(:final message) => AknBanner(
      tone: AknTone.danger,
      message: message,
    ),
    ActionDone() => const SizedBox.shrink(),
  };
}
