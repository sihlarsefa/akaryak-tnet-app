import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/image_capture.dart';
import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_number.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/wizard_controller.dart';
import '../../application/wizard_models.dart';
import '../../application/wizard_rules.dart';
import '../../copy.dart';
import '../../data/payment_models.dart';
import '../widgets/common.dart';
import '../widgets/payment_document_flow.dart';

IconData paymentMethodIcon(String code) => switch (code) {
  PaymentCodes.cash => Icons.payments_rounded,
  PaymentCodes.transfer => Icons.swap_horiz_rounded,
  PaymentCodes.card => Icons.credit_card_rounded,
  PaymentCodes.dbs => Icons.account_balance_rounded,
  PaymentCodes.cheque => Icons.edit_document,
  PaymentCodes.promissoryNote => Icons.description_rounded,
  PaymentCodes.openAccount => Icons.menu_book_rounded,
  PaymentCodes.guarantee => Icons.shield_rounded,
  PaymentCodes.utts => Icons.directions_car_rounded,
  PaymentCodes.advance => Icons.account_balance_wallet_rounded,
  _ => Icons.radio_button_unchecked_rounded,
};

/// Adım 3: ödeme yöntemi kartları, vade / taksit, yöntem alanları (sunucu şeması), avans bakiyesi,
/// çek / senet tutarı ve vadesi (tahminden ve teslim + vadeden dolar; farklıysa uyarı),
/// finans onayı ipucu, havalede isteğe bağlı dekont.
class StepPayment extends ConsumerWidget {
  const StepPayment({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(orderWizardProvider);
    final ctrl = ref.read(orderWizardProvider.notifier);
    final t = context.aknText;
    final c = context.akn;
    final o = w.options;

    if (w.payment == null && w.loadingPayment) {
      return const SkeletonList(itemCount: 3, lines: 2);
    }
    if (w.payment == null && w.paymentError != null) {
      return Center(
        child: SingleChildScrollView(
          child: FailureView(
            failure: w.paymentError!,
            onRetry: () => ctrl.loadPayment(),
          ),
        ),
      );
    }
    if (o == null) return const SizedBox.shrink();

    final d = w.draft;
    final m = w.method;
    final issues = w.showErrors
        ? WizardRules.payment(d, options: o, estimate: w.estimate)
        : WizardRules.payment(
            d,
            options: o,
            estimate: w.estimate,
          ).where((i) => i.field == 'advance' || i.field == 'blocked').toList();
    final warnings = WizardRules.paymentWarnings(
      d,
      options: o,
      estimate: w.estimate,
    );
    String? errorFor(String f) =>
        issues.where((i) => i.field == f).firstOrNull?.message;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Semantics(
                  header: true,
                  child: Text('Ödeme yöntemi', style: t.headline),
                ),
              ),
              if (o.blockedReason != null)
                AknBanner(
                  tone: AknTone.warn,
                  icon: Icons.hourglass_top_rounded,
                  message: o.blockedReason!,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                )
              else if (o.methods.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    OrdersCopy.noMethods,
                    style: t.body.copyWith(color: c.dim),
                  ),
                )
              else ...[
                for (final method in o.methods)
                  ChoiceCard(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    title: method.displayName,
                    subtitle: method.termLabel,
                    leadingIcon: paymentMethodIcon(method.code),
                    tag: method.requiresFinance
                        ? 'Finans onayı'
                        : (method.code == o.defaultMethodCode
                              ? 'Varsayılan'
                              : null),
                    selected: d.payment.methodCode == method.code,
                    onTap: () => ctrl.selectMethod(method.code),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: d.payment.hasMethod
                        ? AknButton.ghost(
                            label: 'Ödemeyi belirtmeden gönder',
                            size: AknButtonSize.small,
                            onPressed: ctrl.clearMethod,
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 0, 8),
                            child: Text(
                              OrdersCopy.noPayment,
                              style: t.bodySmall.copyWith(color: c.dim),
                            ),
                          ),
                  ),
                ),
              ],
              SafeAnimatedSize(
                child: m == null
                    ? const SizedBox(width: double.infinity)
                    : _MethodDetail(
                        key: ValueKey(m.code),
                        method: m,
                        options: o,
                        errorFor: errorFor,
                        warnings: warnings,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MethodDetail extends ConsumerStatefulWidget {
  const _MethodDetail({
    super.key,
    required this.method,
    required this.options,
    required this.errorFor,
    required this.warnings,
  });

  final PaymentMethodOption method;
  final PaymentOptions options;
  final String? Function(String field) errorFor;
  final List<RuleIssue> warnings;

  @override
  ConsumerState<_MethodDetail> createState() => _MethodDetailState();
}

class _MethodDetailState extends ConsumerState<_MethodDetail> {
  final Map<String, TextEditingController> _text = {};

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(
    String key,
    String value, {
    bool money = false,
  }) {
    final c = _text.putIfAbsent(key, () => TextEditingController(text: value));
    final current = money ? TrNumber.parse(c.text) : c.text;
    final incoming = money ? TrNumber.parse(value) : value;
    if (current != incoming) c.text = value;
    return c;
  }

  Future<void> _pickReceipt() async {
    final img = await pickDocumentImage(
      context,
      ref,
      source: CaptureSource.camera,
      kind: AttachmentKind.transferReceipt,
    );
    if (img == null || !mounted) return;
    ref.read(orderWizardProvider.notifier).setReceipt(img.path);
  }

  Future<void> _pickReceiptFromGallery() async {
    final img = await pickDocumentImage(
      context,
      ref,
      source: CaptureSource.gallery,
      kind: AttachmentKind.transferReceipt,
    );
    if (img == null || !mounted) return;
    ref.read(orderWizardProvider.notifier).setReceipt(img.path);
  }

  /// Bankanın gönderdiği hazır dekont (PDF).
  Future<void> _pickReceiptFile() async {
    final img = await pickDocumentImage(
      context,
      ref,
      source: CaptureSource.file,
      kind: AttachmentKind.transferReceipt,
    );
    if (img == null || !mounted) return;
    ref.read(orderWizardProvider.notifier).setReceipt(img.path);
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(orderWizardProvider);
    final ctrl = ref.read(orderWizardProvider.notifier);
    final t = context.aknText;
    final c = context.akn;
    final m = widget.method;
    final d = w.draft;
    final p = d.payment;
    final children = <Widget>[];

    if (m.hasTerm) {
      final terms = WizardRules.termOptions(m, p.termDays);
      children.add(
        _Group(
          label: 'Vade (gün) *',
          helper:
              '${m.minTermDays > 0 ? m.minTermDays : 0}–${m.maxTermDays} gün'
              '${m.requiresFinance ? ' · finans onayı gerekebilir' : ''}'
              '${m.isInstrument ? ' · belgenin vadesinden hesaplanır' : ''}',
          error: widget.errorFor('term'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final days in terms)
                ChoiceChip(
                  label: Text(days == 0 ? 'Peşin' : '$days gün'),
                  selected: p.termDays == days,
                  onSelected: (_) => ctrl.setTerm(days),
                ),
            ],
          ),
        ),
      );
    }

    if (m.hasInstallments) {
      children.add(
        _Group(
          label: 'Taksit',
          helper: 'Kart bilgisi istenmez; ödeme teslimatta POS ile alınır.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in m.installmentOptions)
                ChoiceChip(
                  label: Text(n == 1 ? 'Tek çekim' : '$n taksit'),
                  selected: p.installments == n,
                  onSelected: (_) => ctrl.setInstallments(n),
                ),
            ],
          ),
        ),
      );
    }

    for (final f in m.fields) {
      children.add(_field(context, m, f, p, d));
    }

    for (final warn in widget.warnings) {
      children.add(
        AknBanner(
          tone: AknTone.warn,
          icon: Icons.compare_arrows_rounded,
          message: warn.message,
          margin: const EdgeInsets.only(top: 8),
        ),
      );
    }

    if (m.code == PaymentCodes.advance) {
      final bal = widget.options.advanceBalance;
      final err = widget.errorFor('advance');
      children.add(
        AknBanner(
          tone: err == null ? AknTone.info : AknTone.danger,
          icon: Icons.account_balance_wallet_rounded,
          title: 'Ön ödemeli bakiye',
          message:
              err ??
              (bal == null
                  ? 'Bakiye bilgisi alınamadı; sipariş anında denetlenir.'
                  : 'Kullanılabilir bakiye: ${Fmt.money(bal)} (tutar sipariş oluşunca bloke edilir).'),
          margin: const EdgeInsets.only(top: 8),
        ),
      );
    }

    if (m.isInstrument) {
      children.add(
        const _Hint(
          icon: Icons.photo_camera_outlined,
          text: OrdersCopy.instrumentPhotoLater,
        ),
      );
    }

    if (m.code == PaymentCodes.transfer) {
      children.add(_receipt(context, p));
    }

    if (m.hint != null) {
      children.add(_Hint(icon: Icons.info_outline_rounded, text: m.hint!));
    }

    if (m.requiresFinance) {
      children.add(
        const AknBanner(
          tone: AknTone.info,
          icon: Icons.shield_outlined,
          message: OrdersCopy.financeHint,
          margin: EdgeInsets.only(top: 8),
        ),
      );
    }

    final est = w.estimate;
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: AknCard(
          color: c.surfaceAlt,
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FactRow(label: 'Ödeme', value: WizardRules.paymentSummary(d, m)),
              FactRow(
                label: 'Tahmini tutar',
                value: est.value != null
                    ? Fmt.money(est.value)
                    : (est.unknown ? OrdersCopy.priceUnknown : Fmt.dash),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('${m.displayName} ayrıntıları', style: t.headline),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _receipt(BuildContext context, DraftPayment p) {
    final t = context.aknText;
    final c = context.akn;
    final path = p.receiptPath;
    return _Group(
      label: OrdersCopy.transferReceiptOptional,
      helper:
          'Sipariş oluşunca yüklenir; şimdi eklemezseniz sonra sipariş ayrıntısından ekleyebilirsiniz.',
      child: path == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ButtonRowFor(
                  children: [
                    AknButton.secondary(
                      label: 'Dekontu çek',
                      icon: Icons.photo_camera_rounded,
                      expand: true,
                      onPressed: _pickReceipt,
                    ),
                    AknButton.secondary(
                      label: 'Galeriden seç',
                      icon: Icons.photo_library_rounded,
                      expand: true,
                      onPressed: _pickReceiptFromGallery,
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AknButton.ghost(
                    label: 'Dosya (PDF) seç',
                    icon: Icons.picture_as_pdf_rounded,
                    size: AknButtonSize.small,
                    onPressed: _pickReceiptFile,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Icon(Icons.receipt_long_rounded, color: c.ok.fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dekont eklendi; sipariş oluşunca yüklenecek.',
                    style: t.bodySmall.copyWith(color: c.text),
                  ),
                ),
                AknIconButton(
                  icon: Icons.close_rounded,
                  semanticLabel: 'Dekontu kaldır',
                  onPressed: () =>
                      ref.read(orderWizardProvider.notifier).setReceipt(null),
                ),
              ],
            ),
    );
  }

  Widget _field(
    BuildContext context,
    PaymentMethodOption m,
    PaymentField f,
    DraftPayment p,
    OrderDraft d,
  ) {
    final ctrl = ref.read(orderWizardProvider.notifier);
    final value = p.fields[f.key] ?? '';
    final error = widget.errorFor(f.key);
    final label = f.label;
    String? helper;
    if (m.isInstrument && f.key == 'amount' && d.lines.length > 1) {
      helper = OrdersCopy.oneInstrumentPerGroup;
    } else if (m.isInstrument && f.key == 'amount') {
      helper = 'Tahmini tutardan dolduruldu; çekinizdeki tutarı yazın.';
    } else if (m.isInstrument && f.key == 'dueDate') {
      helper = 'Vade (gün) bu tarihten hesaplanır.';
    }
    final pad = const EdgeInsets.only(top: 12);
    switch (f.type) {
      case 'money':
        return Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MoneyField(
                label: label,
                controller: _controller(f.key, value, money: true),
                requiredValue: f.required,
                helper: helper,
                onChanged: (v) => ctrl.setField(
                  f.key,
                  v == null
                      ? ''
                      : Fmt.number(v, minFraction: 2, maxFraction: 2),
                ),
              ),
              if (error != null) _ErrorLine(error),
            ],
          ),
        );
      case 'date':
        final date = TrTime.parseDate(value);
        final isDue = f.key == 'dueDate';
        final delivery = d.date;
        return Padding(
          padding: pad,
          child: DateField(
            label: label,
            value: date,
            requiredMark: f.required,
            quickPicks: !isDue,
            firstDate: isDue
                ? TrTime.todayStart()
                : TrTime.addDays(TrTime.todayStart(), -30),
            lastDate: isDue && delivery != null && m.hasTerm
                ? TrTime.addDays(delivery, m.maxTermDays)
                : TrTime.addDays(TrTime.todayStart(), 366),
            helper: helper,
            errorText: error,
            onChanged: (v) => ctrl.setField(f.key, TrTime.isoDate(v)),
          ),
        );
      case 'select':
        final choices = f.selectChoices;
        if (choices.isEmpty) {
          return Padding(
            padding: pad,
            child: _Hint(
              icon: Icons.info_outline_rounded,
              text:
                  'Kayıtlı geçerli ${TurkishText.lower(label)} yok; bilgileri aşağıya girin.',
            ),
          );
        }
        return Padding(
          padding: pad,
          child: DropdownButtonFormField<String>(
            initialValue: choices.any((x) => x.value == value) ? value : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: f.required ? '$label *' : label,
              errorText: error,
            ),
            items: [
              for (final x in choices)
                DropdownMenuItem(value: x.value, child: Text(x.label)),
            ],
            onChanged: (v) => ctrl.setField(f.key, v ?? ''),
          ),
        );
      case 'number':
      case 'textarea':
      default:
        final multi = f.type == 'textarea';
        return Padding(
          padding: pad,
          child: AknTextField(
            controller: _controller(f.key, value),
            label: label,
            hint: f.placeholder,
            requiredMark: f.required,
            maxLength: f.maxLength,
            maxLines: multi ? 3 : 1,
            minLines: multi ? 2 : 1,
            keyboardType: f.type == 'number'
                ? TextInputType.number
                : (multi ? TextInputType.multiline : TextInputType.text),
            textCapitalization: f.key == 'serialNo'
                ? TextCapitalization.characters
                : TextCapitalization.words,
            errorText: error,
            helper: helper,
            onChanged: (v) => ctrl.setField(f.key, v),
          ),
        );
    }
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.child,
    this.helper,
    this.error,
  });

  final String label;
  final Widget child;
  final String? helper;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: t.label.copyWith(color: c.text)),
          const SizedBox(height: 8),
          child,
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(helper!, style: t.caption.copyWith(color: c.dim)),
          ],
          if (error != null) _ErrorLine(error!),
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: context.aknText.bodySmall.copyWith(color: context.akn.danger.fg),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c.dim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: t.bodySmall.copyWith(color: c.dim)),
          ),
        ],
      ),
    );
  }
}
