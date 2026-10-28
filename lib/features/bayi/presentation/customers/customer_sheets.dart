import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/bayi_actions.dart';
import '../../application/customers_controller.dart';
import '../../data/customer_models.dart';
import '../widgets/bayi_widgets.dart';

/// Limit değişikliği talebi (`CreateLimitChangeRequest`: periyot, tür, tutar, gerekçe). Merkez onayına
/// gider; talep sonuçlanana kadar yeni talep açılamaz. Gönderilirse true.
Future<bool> showLimitRequestSheet(
  BuildContext context,
  CustomerSummary s,
) async {
  final r = await showAppSheet<bool>(
    context: context,
    title: 'Limit talebi',
    subtitle: s.title,
    builder: (_) => _LimitSheet(summary: s),
  );
  return r ?? false;
}

class _LimitSheet extends ConsumerStatefulWidget {
  const _LimitSheet({required this.summary});

  final CustomerSummary summary;

  @override
  ConsumerState<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends ConsumerState<_LimitSheet> {
  final _form = GlobalKey<FormState>();
  late String _period = _initialPeriod();
  late String _type = widget.summary.limit?.limitType ?? 'Tutar';
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;

  String _initialPeriod() {
    final p = widget.summary.limit?.period;
    return p != null &&
            LimitOptions.periods.contains(p) &&
            p != LimitOptions.unlimited
        ? p
        : 'Aylık';
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _unlimited => _period == LimitOptions.unlimited;

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final s = widget.summary;
    final draft = LimitRequestDraft(
      limitPeriod: _period,
      limitType: _unlimited ? null : _type,
      limitAmount: _unlimited ? null : MoneyField.parse(_amount.text),
      reason: _reason.text,
    );
    setState(() => _busy = true);
    try {
      await ref.read(bayiActionsProvider).requestLimit(s.customerId, draft);
      if (!mounted) return;
      AknHaptics.success();
      AppToast.success(
        'Limit talebi merkez onayına gönderildi.',
        context: context,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showActionFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final online = ref.watch(isOnlineProvider);
    final limit = widget.summary.limit;
    final liters = _type == 'Litre';
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (limit != null)
            // Mevcut limit Beton kuyuda (v3 sayfa içi grup).
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.akn.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: FactRow(
                  label: 'Mevcut limit',
                  value: currentLimitText(limit),
                  padding: EdgeInsets.zero,
                  valueStyle: const TextStyle(
                    fontFeatures: AknNumerals.tabular,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Periyot', style: t.bodyStrong),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final p in LimitOptions.periods)
                ChoiceChip(
                  label: Text(p),
                  selected: _period == p,
                  onSelected: (_) => setState(() => _period = p),
                ),
            ],
          ),
          if (!_unlimited) ...[
            const SizedBox(height: 16),
            Text('Limit türü', style: t.bodyStrong),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final ty in LimitOptions.types)
                  ChoiceChip(
                    label: Text(ty),
                    selected: _type == ty,
                    onSelected: (_) => setState(() => _type = ty),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            MoneyField(
              label: liters
                  ? 'Talep edilen limit (litre)'
                  : 'Talep edilen limit',
              unit: liters ? 'L' : '₺',
              controller: _amount,
              requiredValue: true,
              validator: (v) => v != null && v <= 0
                  ? 'Sıfırdan büyük bir değer girin.'
                  : null,
            ),
          ],
          const SizedBox(height: 12),
          AknTextField(
            controller: _reason,
            label: 'Gerekçe',
            requiredMark: true,
            maxLines: 4,
            minLines: 2,
            maxLength: LimitOptions.reasonMax,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Talep gerekçesi zorunludur.'
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Talep merkez onayına gider; sonuç bildirim olarak gelir.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 20),
          AknButton(
            label: 'Talebi gönder',
            expand: true,
            loading: _busy,
            onPressed: online ? () => unawaited(_submit()) : null,
          ),
        ],
      ),
    );
  }
}

/// "Aylık 1.000.000 ₺" / "Limitsiz".
String currentLimitText(SummaryLimit l) {
  if (l.isUnlimited) return 'Limitsiz';
  final amount = l.isLiters
      ? Fmt.liters(l.amount)
      : Fmt.money(l.amount, decimals: 0);
  final period = l.periodLabel ?? l.period;
  return period == null ? amount : '$period $amount';
}

/// Görüşme notu ekle (Idempotency-Key ile; aynı not iki kez kaydedilmez).
Future<void> showAddNoteSheet(BuildContext context, int customerId) =>
    showAppSheet<void>(
      context: context,
      title: 'Görüşme notu',
      builder: (_) => _NoteSheet(customerId: customerId),
    );

class _NoteSheet extends ConsumerStatefulWidget {
  const _NoteSheet({required this.customerId});

  final int customerId;

  @override
  ConsumerState<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<_NoteSheet> {
  final _body = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _body.text.trim();
    if (_busy || text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final note = await ref
          .read(bayiActionsProvider)
          .addNote(widget.customerId, text);
      ref
          .read(customerSummaryProvider(widget.customerId).notifier)
          .prependNote(note);
      if (!mounted) return;
      AppToast.success('Not kaydedildi.', context: context);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showActionFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AknTextField(
          controller: _body,
          label: 'Not',
          hint: 'Görüşmede ne konuşuldu?',
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        AknButton(
          label: 'Notu kaydet',
          expand: true,
          loading: _busy,
          onPressed: online && _body.text.trim().isNotEmpty
              ? () => unawaited(_save())
              : null,
        ),
      ],
    );
  }
}
