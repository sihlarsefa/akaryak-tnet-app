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
import 'payment_cards.dart';

/// Geri alınması zor geçişler: kayıt düğmesi kırmızı dolgulu (§6.21 yıkıcı onay).
bool _destructivePayment(PaymentStatus s) =>
    s == PaymentStatus.bounced ||
    s == PaymentStatus.refunded ||
    s == PaymentStatus.cancelled;

bool _destructiveInstrument(InstrumentStatus s) =>
    s == InstrumentStatus.bounced ||
    s == InstrumentStatus.returned ||
    s == InstrumentStatus.protested;

/// Ödeme durumu sayfası (tasarım v3 alt sayfası, seçenekler beyaz seçim kartları): yalnızca sunucunun
/// izin verdiği geçişler
/// (`allowedTransitions`), gerekçe zorunlu durumlarda not (`noteRequiredFor`, en az 3 karakter),
/// dayanak belge ("Dekont ekle"). [initial] izinliyse seçili açılır ("Tahsil edildi olarak
/// işaretle").
Future<String?> showPaymentStatusSheet(
  BuildContext context, {
  required int orderId,
  PaymentStatus? initial,
}) => showAppSheet<String>(
  context: context,
  title: 'Ödeme durumu',
  subtitle: 'Yalnızca bu ödemede izin verilen durumlar listelenir.',
  builder: (_) => PaymentStatusSheet(orderId: orderId, initial: initial),
);

class PaymentStatusSheet extends ConsumerStatefulWidget {
  const PaymentStatusSheet({super.key, required this.orderId, this.initial});

  final int orderId;

  /// Açılışta seçili yeni durum (izinli değilse yok sayılır).
  final PaymentStatus? initial;

  @override
  ConsumerState<PaymentStatusSheet> createState() => _PaymentStatusSheetState();
}

class _PaymentStatusSheetState extends ConsumerState<PaymentStatusSheet> {
  final _note = TextEditingController();
  late PaymentStatus? _to = _initialChoice();
  String? _attachmentId;
  bool _busy = false;

  /// Belge yüklendikten sonra kayıt yeniden okunuyor ("Durumu kaydet" kapalı).
  bool _refreshing = false;
  ActionOutcome? _problem;
  Map<String, String> _errors = const {};

  UploadTarget get _target =>
      UploadTarget(AttachmentOwnerType.order, widget.orderId);

  PaymentStatus? _initialChoice() {
    final i = widget.initial;
    if (i == null) return null;
    final d = ref.read(paymentDetailProvider(widget.orderId)).valueOrNull;
    return d != null && d.allowedTransitions.contains(i) ? i : null;
  }

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
        'Belge eklendi. Ödeme durumu "${fresh.row.paymentStatusLabel ?? fresh.row.paymentStatus.label}" oldu.',
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
        'Belge yüklemesi sürüyor. Bitince durumu kaydedin.',
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
    final amount = d.row.displayAmount;
    final canSave = to != null && online && !_busy && !_refreshing;
    final saveLabel = to == null ? 'Durum seçin' : 'Durumu kaydet';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetSummary(
          title: d.row.customerTitle,
          meta: [
            d.row.orderNumber,
            if (amount != null) Fmt.money(amount),
          ].join(', '),
          lamp: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Şu an', style: t.bodySmall.copyWith(color: c.dim)),
              const SizedBox(width: 10),
              Flexible(child: AknLamp.style(current)),
            ],
          ),
        ),
        _Appear(
          child: problem == null
              ? null
              : Padding(
                  key: ValueKey(problem),
                  padding: const EdgeInsets.only(top: 12),
                  child: _Problem(outcome: problem, onReload: _reload),
                ),
        ),
        const SizedBox(height: 20),
        Text('Yeni durum', style: t.label),
        const SizedBox(height: 8),
        for (final s in d.allowedTransitions)
          ChoiceCard(
            title: s.label,
            subtitle: PaymentsCopy.paymentHint(s),
            leading: _ToneDot(tone: AknStatus.payment(s).tone),
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
          _FieldError(text: _errors['toStatus']!),
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
        const SizedBox(height: 16),
        Text('Dayanak belge (isteğe bağlı)', style: t.label),
        const SizedBox(height: 4),
        Text(
          'Seçtiğiniz belge durum geçmişinde bu değişikliğin yanında görünür.',
          style: t.bodySmall.copyWith(color: c.dim),
        ),
        if (docs.isNotEmpty) ...[
          const SizedBox(height: 4),
          FilterChips<String>(
            padding: EdgeInsets.zero,
            options: [
              for (final a in docs)
                FilterOption(
                  value: a.publicId,
                  label: '${a.kindLabel}, ${a.fileName}',
                ),
            ],
            selected: {?_attachmentId},
            onChanged: (s) =>
                setState(() => _attachmentId = s.isEmpty ? null : s.first),
          ),
        ],
        if (_errors['attachmentPublicId'] != null)
          _FieldError(text: _errors['attachmentPublicId']!),
        UploadTiles(target: _target),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: AknButton.secondary(
            label: addLabel,
            icon: PhosphorIconsRegular.cameraPlus,
            size: AknButtonSize.small,
            onPressed: () => unawaited(_addDocument(d)),
          ),
        ),
        const SizedBox(height: 24),
        if (!online)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(PaymentsCopy.offline, style: t.bodySmall),
          ),
        if (to != null && _destructivePayment(to) && !_busy && !_refreshing)
          Semantics(
            label: 'Durumu "${to.label}" olarak kaydet',
            excludeSemantics: true,
            button: true,
            enabled: canSave,
            onTap: canSave ? () => _submit(d) : null,
            child: DestructiveButton(
              label: saveLabel,
              onPressed: canSave ? () => _submit(d) : null,
            ),
          )
        else
          AknButton(
            label: saveLabel,
            semanticLabel: to == null
                ? null
                : 'Durumu "${to.label}" olarak kaydet',
            expand: true,
            size: AknButtonSize.large,
            loading: _busy || _refreshing,
            loadingLabel: _refreshing ? 'Ödeme güncelleniyor' : 'Gönderiliyor',
            onPressed: canSave ? () => _submit(d) : null,
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
  title: [instrument.displayKindLabel, ?instrument.serialNo].join(' '),
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
    final status = instrumentLamp(i);
    final to = _to;
    final noteRequired = to != null && i.noteRequiredFor.contains(to);
    final actions = widget.canChange
        ? i.allowedTransitions
        : const <InstrumentStatus>[];
    final problem = _problem;
    final hint = i.isOpen ? i.dueHint : null;
    final canSave = to != null && online && !_busy;
    final saveLabel = to == null ? 'Durum seçin' : 'Durumu kaydet';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Tutar ${Fmt.money(i.amount)}',
          excludeSemantics: true,
          child: AmountText(Fmt.money(i.amount), large: true),
        ),
        const SizedBox(height: 10),
        AknStatusLine(
          lamp: AknLamp.style(status),
          trailing: hint == null
              ? null
              : DueHint(
                  text: dueHintText(hint),
                  tone: dueTone(overdue: i.isOverdue, due: i.dueDate),
                ),
        ),
        const SizedBox(height: 12),
        FactList(
          facts: [
            FactRow(label: 'Vade', value: Fmt.longDate(i.dueDate)),
            if (i.bankName != null)
              FactRow(
                label: 'Banka',
                value: [i.bankName!, ?i.branchName].join(', '),
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
        _Appear(
          child: problem == null
              ? null
              : Padding(
                  key: ValueKey(problem),
                  padding: const EdgeInsets.only(top: 12),
                  child: _Problem(outcome: problem, onReload: null),
                ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Durumu değiştir', style: t.title),
          const SizedBox(height: 10),
          for (final s in actions)
            ChoiceCard(
              title: s.label,
              subtitle: PaymentsCopy.instrumentHint(s),
              leading: _ToneDot(tone: AknStatus.instrument(s).tone),
              selected: to == s,
              margin: const EdgeInsets.only(bottom: 8),
              onTap: () => setState(() {
                _to = s;
                _errors = {..._errors}..remove('note');
              }),
            ),
          if (_errors['toStatus'] != null)
            _FieldError(text: _errors['toStatus']!),
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
          const SizedBox(height: 16),
          if (!online)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(PaymentsCopy.offline, style: t.bodySmall),
            ),
          if (to != null && _destructiveInstrument(to) && !_busy)
            Semantics(
              label: 'Durumu "${to.label}" olarak kaydet',
              excludeSemantics: true,
              button: true,
              enabled: canSave,
              onTap: canSave ? _submit : null,
              child: DestructiveButton(
                label: saveLabel,
                onPressed: canSave ? _submit : null,
              ),
            )
          else
            AknButton(
              label: saveLabel,
              semanticLabel: to == null
                  ? null
                  : 'Durumu "${to.label}" olarak kaydet',
              expand: true,
              loading: _busy,
              onPressed: canSave ? _submit : null,
            ),
        ] else if (!widget.canChange && i.isOpen) ...[
          const SizedBox(height: 16),
          Text(
            'Durumu değiştirmek için muhasebe yetkisi gerekir. Yöneticinizden yetki isteyin.',
            style: t.bodySmall.copyWith(color: c.dim),
          ),
        ],
      ],
    );
  }
}

/// Sayfanın üstündeki kısa özet (tasarım v3): Beton kuyuda kayıt adı, kimlik ve tutar (tablo
/// rakamları), şu anki durum.
class _SheetSummary extends StatelessWidget {
  const _SheetSummary({
    required this.title,
    required this.meta,
    required this.lamp,
  });

  final String title;
  final String meta;
  final Widget lamp;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.headline),
            const SizedBox(height: 2),
            Text(
              meta,
              style: t.bodySmall.copyWith(
                color: c.dim,
                fontFeatures: AknNumerals.tabular,
              ),
            ),
            const SizedBox(height: 10),
            lamp,
          ],
        ),
      ),
    );
  }
}

/// Seçenek kartının başındaki durum noktası (lambanın noktası; kapalı durumlar halka).
class _ToneDot extends StatelessWidget {
  const _ToneDot({required this.tone});

  final AknTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final hollow = tone == AknTone.neutral;
    return ExcludeSemantics(
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hollow ? null : c.tone(tone).solid,
              border: hollow
                  ? Border.all(color: c.neutral.solid, width: 1.5)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.warningCircle, size: 16, color: c.danger.fg),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: t.label.copyWith(color: c.danger.fg)),
          ),
        ],
      ),
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
      title: 'Bu kayıt siz bakarken değişti',
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

/// Sorun kuyusu gelince yükseklik süzülerek açılır, kuyu solup büyür (v3 §5); [child] null iken yer
/// kalmaz. Hareket azaltmada doğrudan.
class _Appear extends StatelessWidget {
  const _Appear({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = child;
    if (AknMotion.reduced(context)) return c ?? const SizedBox.shrink();
    return AknAnimatedSize(
      duration: AknMotion.slow,
      curve: AknMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AknMotion.base,
        switchInCurve: AknMotion.standard,
        switchOutCurve: AknMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: animation.drive(Tween<double>(begin: 0.96, end: 1)),
            child: child,
          ),
        ),
        child:
            c ?? const SizedBox(key: ValueKey('none'), width: double.infinity),
      ),
    );
  }
}
