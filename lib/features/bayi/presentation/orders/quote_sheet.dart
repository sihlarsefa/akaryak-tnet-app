import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/models.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/bayi_actions.dart';
import '../../application/bayi_runtime.dart';
import '../../application/desk_controller.dart';
import '../../data/bayi_repository.dart';
import '../widgets/bayi_widgets.dart';

/// Tekil teklif (sipariş ayrıntısı, `orders/{id}/quote`). Sunucu limit aşımında siparişi finans onayına
/// gönderebilir: gönderimden sonra sipariş yeniden okunur ve sonuç buna göre bildirilir.
Future<bool> showQuoteSheet(
  BuildContext context,
  OrderDetail order, {
  double? suggestion,
}) async {
  final r = await showAppSheet<bool>(
    context: context,
    title: order.status == OrderStatus.revisionRequested
        ? 'Teklifi güncelle'
        : 'Teklif ver',
    subtitle: '${order.customerTitle}, ${order.orderNumber}',
    builder: (_) => _QuoteSheet(order: order, suggestion: suggestion),
  );
  return r ?? false;
}

class _QuoteSheet extends ConsumerStatefulWidget {
  const _QuoteSheet({required this.order, this.suggestion});

  final OrderDetail order;
  final double? suggestion;

  @override
  ConsumerState<_QuoteSheet> createState() => _QuoteSheetState();
}

class _QuoteSheetState extends ConsumerState<_QuoteSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _price = TextEditingController(
    text: widget.suggestion == null ? '' : formatUnitPrice(widget.suggestion!),
  );
  late DateTime _date = _defaultDate();
  bool _busy = false;

  DateTime _defaultDate() {
    final today = TrTime.todayStart();
    final requested = widget.order.requestedDeliveryDate;
    if (requested == null || requested.isBefore(today)) return today;
    return TrTime.startOfDay(requested);
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final o = widget.order;
    setState(() => _busy = true);
    try {
      final outcome = await ref
          .read(bayiActionsProvider)
          .quoteOrder(
            o.id,
            unitPrice: MoneyField.parse(_price.text)!,
            deliveryDate: _date,
            wasAwaitingFinance: o.financeStatus.isAwaitingDecision,
          );
      // Teklif kaydedildi ya da sipariş finansa gitti; sonucu okumak başarısız olsa da işlem
      // başarılıdır.
      OrderDetail? fresh;
      if (outcome != BayiOutcome.routedToFinance) {
        try {
          fresh = await ref.read(bayiRepositoryProvider).order(o.id);
        } catch (_) {
          fresh = null;
        }
      }
      if (!mounted) return;
      if (outcome == BayiOutcome.routedToFinance ||
          (fresh?.financeStatus.isAwaitingDecision ?? false)) {
        AknHaptics.warning();
        AppToast.warning(
          'Teklif cari limitini aştığı için kaydedilmedi; sipariş finans onayına gönderildi. Finans onaylayınca yeniden teklif verebilirsiniz.',
          context: context,
        );
      } else {
        AppToast.success(
          'Teklif gönderildi. Müşterinin kararı bekleniyor.',
          context: context,
        );
      }
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
    final c = context.akn;
    final o = widget.order;
    final online = ref.watch(isOnlineProvider);
    final price = MoneyField.parse(_price.text);
    final latest = o.currentQuote;
    final today = TrTime.todayStart();
    final total = price != null && price > 0 ? price * o.quantityLiters : null;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            keepUnits(
              [
                o.productName,
                Fmt.liters(o.quantityLiters),
                o.deliveryPointName,
              ].join(', '),
            ),
            style: t.body.copyWith(color: c.ink),
          ),
          if (latest?.revisionNote != null) ...[
            const SizedBox(height: 12),
            AknBanner(
              tone: AknTone.info,
              icon: Icons.chat_bubble_outline_rounded,
              title:
                  'Revize notu, önceki teklif ${Fmt.unitPrice(latest!.unitPriceTry)}',
              message: latest.revisionNote!,
            ),
          ],
          const SizedBox(height: 16),
          MoneyField.unitPrice(
            label: 'Birim fiyat',
            controller: _price,
            requiredValue: true,
            autofocus: widget.suggestion == null,
            max: QuoteDeskController.maxUnitPrice,
            helper: widget.suggestion == null
                ? null
                : 'Önerilen ${Fmt.unitPrice(widget.suggestion)}',
            validator: (v) =>
                v != null && v <= 0 ? 'Sıfırdan büyük bir değer girin.' : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          DateField(
            label: 'Teklif teslim günü',
            value: _date,
            firstDate: today,
            lastDate: TrTime.addDays(today, 365),
            requiredMark: true,
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: 16),
          // Canlı toplam: tahmini tutar sağa hizalı, sayaç sesiyle (plaka değil; sayfada tek plaka var).
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Semantics(
              liveRegion: true,
              label: total == null
                  ? 'Tahmini tutar, birim fiyat girince hesaplanır'
                  : 'Tahmini tutar ${Fmt.money(total)}',
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Tahmini tutar',
                    style: t.label.copyWith(color: c.dim),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        total == null ? Fmt.dash : Fmt.money(total),
                        style: t.amountLarge.copyWith(
                          color: total == null ? c.dim : c.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          AknButton(
            label: 'Teklifi gönder',
            expand: true,
            loading: _busy,
            onPressed: online ? () => unawaited(_submit()) : null,
          ),
          if (!online)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Çevrimdışıyken teklif gönderilemez.',
                textAlign: TextAlign.center,
                style: t.label.copyWith(color: c.dim),
              ),
            ),
        ],
      ),
    );
  }
}
