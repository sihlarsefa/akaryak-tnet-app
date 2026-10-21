import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/models.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../../../core/utils/validators.dart';
import '../../application/bayi_actions.dart';
import '../../data/dispatch_models.dart';
import '../widgets/bayi_widgets.dart';

/// Teslim bildir / Teslimatı düzelt (personel; uygulaması olmayan şoför için). Litre ≤ planlanan,
/// irsaliye no zorunlu. Bildirilirse true.
Future<bool> showReportSheet(BuildContext context, ShipmentDetail d) async {
  final fix = d.status == ShipmentStatus.disputed;
  final r = await showAppSheet<bool>(
    context: context,
    title: fix ? 'Teslimatı düzelt' : 'Teslim bildir',
    subtitle: '${d.code} · ${d.customerTitle ?? d.orderNumber}',
    builder: (_) => _ReportSheet(detail: d),
  );
  return r ?? false;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.detail});

  final ShipmentDetail detail;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _liters = TextEditingController(
    text: Fmt.number(
      widget.detail.deliveredLiters ?? widget.detail.plannedLiters,
      maxFraction: 3,
    ),
  );
  late final TextEditingController _doc = TextEditingController(
    text: widget.detail.deliveryDocumentNo ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _liters.dispose();
    _doc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final d = widget.detail;
    setState(() => _busy = true);
    try {
      await ref
          .read(bayiActionsProvider)
          .report(
            d.id,
            deliveredLiters: MoneyField.parse(_liters.text)!,
            deliveryDocumentNo: _doc.text.trim().asciiUpper,
          );
      if (!mounted) return;
      AppToast.success(
        d.status == ShipmentStatus.disputed
            ? 'Düzeltilen teslimat cari onayına gönderildi.'
            : 'Teslimat bildirildi. Carinin onayı bekleniyor.',
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
    final d = widget.detail;
    final online = ref.watch(isOnlineProvider);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (d.disputeNote != null) ...[
            AknBanner(
              tone: AknTone.danger,
              title: 'Carinin itirazı',
              message: d.disputeNote!,
            ),
            const SizedBox(height: 12),
          ],
          LitersField(
            label: 'Teslim edilen litre',
            controller: _liters,
            max: d.plannedLiters,
            requiredValue: true,
            autofocus: true,
            validator: (v) =>
                Validators.positiveNumber(v, max: d.plannedLiters),
          ),
          const SizedBox(height: 12),
          AknTextField(
            controller: _doc,
            label: 'İrsaliye no',
            requiredMark: true,
            maxLength: 100,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            validator: (v) =>
                Validators.required(v, message: 'İrsaliye numarasını girin.'),
            onSubmitted: (_) => unawaited(_submit()),
          ),
          const SizedBox(height: 8),
          Text(
            'Cari teslimatı uygulamadan onaylar ya da itiraz eder.',
            style: context.aknText.bodySmall.copyWith(color: context.akn.dim),
          ),
          const SizedBox(height: 20),
          AknButton(
            label: d.status == ShipmentStatus.disputed
                ? 'Düzeltmeyi gönder'
                : 'Teslimi bildir',
            expand: true,
            loading: _busy,
            onPressed: online ? () => unawaited(_submit()) : null,
          ),
        ],
      ),
    );
  }
}
