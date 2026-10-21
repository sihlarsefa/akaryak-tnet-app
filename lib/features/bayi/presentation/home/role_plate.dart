import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../data/home_models.dart';

/// Rol plakası (tasarım v2 §7.6): istatistik destesi olmayan bayi ana sayfalarında ekranın tek
/// plakası rolün sayısını taşır.
/// * Sipariş masası: "Teklif bekleyen" `6` + "sipariş"; Revize / Süresi yaklaşan / Müşteri kararında.
/// * Sevkiyat, depo: "Bugün planlı" `5` + "sevkiyat"; Yolda / Sürücüsüz / Kabul bekliyor.
/// * Finans, muhasebe (destesi yoksa): "Vadesi geçen" `184.000 ₺`; 7 gün içinde / Belge kontrolü /
///   Finans onayı.
///
/// Rakam oturumun ilk açılışında bir kez sayaç gibi döner (hareket azaltmada son kare).
class BayiRolePlate extends ConsumerWidget {
  const BayiRolePlate({
    super.key,
    required this.data,
    required this.preset,
    this.margin = const EdgeInsets.fromLTRB(20, 4, 20, 0),
  });

  final BayiHomeData data;
  final RolePreset preset;
  final EdgeInsetsGeometry margin;

  /// Bu ön ayar ve yük için rol plakası var mı.
  static bool supports(RolePreset preset, BayiHomeData data) =>
      switch (preset) {
        RolePreset.orderDesk => data.desk != null,
        RolePreset.dispatch => data.shipments != null,
        RolePreset.finance || RolePreset.accounting => data.collections != null,
        _ => false,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolled = ref.watch(_rolePlateRolledProvider);
    void markRolled() => ref.read(_rolePlateRolledProvider.notifier).mark();
    final spec = _spec(preset, data);
    if (spec == null) return const SizedBox.shrink();
    return AknPlate(
      margin: margin,
      semanticLabel: spec.spoken,
      head: PlateHead(icon: spec.icon, title: spec.title, period: spec.period),
      figure: PlateFigure(
        value: spec.figure,
        unit: spec.unit,
        word: spec.word,
        animate: !rolled,
        onRollStart: markRolled,
      ),
      delta: spec.sentence == null ? null : PlateDelta(sentence: spec.sentence),
      below: PlateReadouts(items: spec.readouts),
    );
  }

  static _PlateSpec? _spec(RolePreset preset, BayiHomeData d) {
    switch (preset) {
      case RolePreset.orderDesk:
        final desk = d.desk;
        if (desk == null) return null;
        final expiring = desk.expiryEnabled ? desk.expiringSoon : null;
        return _PlateSpec(
          icon: Icons.request_quote_outlined,
          title: 'Teklif bekleyen',
          period: 'şu an',
          figure: Fmt.integer(desk.awaitingQuote),
          word: 'sipariş',
          readouts: [
            PlateReadout(
              label: 'Revize',
              value: Fmt.integer(desk.revisionRequested),
            ),
            if (expiring != null)
              PlateReadout(
                label: 'Süresi yaklaşan',
                value: Fmt.integer(expiring),
              ),
            PlateReadout(
              label: 'Müşteri kararında',
              value: Fmt.integer(desk.awaitingCustomer),
            ),
          ],
          spoken: [
            'Teklif bekleyen ${desk.awaitingQuote} sipariş',
            'revize ${desk.revisionRequested}',
            if (expiring != null) 'süresi yaklaşan $expiring',
            'müşteri kararında ${desk.awaitingCustomer}',
          ].join(', '),
        );
      case RolePreset.dispatch:
        final s = d.shipments;
        if (s == null) return null;
        return _PlateSpec(
          icon: Icons.local_shipping_outlined,
          title: 'Bugün planlı',
          period: _today(),
          figure: Fmt.integer(s.plannedDue),
          word: 'sevkiyat',
          readouts: [
            PlateReadout(label: 'Yolda', value: Fmt.integer(s.inTransit)),
            PlateReadout(
              label: 'Sürücüsüz',
              value: Fmt.integer(s.unassignedDriver),
            ),
            PlateReadout(
              label: 'Kabul bekliyor',
              value: Fmt.integer(s.reported),
            ),
          ],
          spoken:
              'Bugün planlı ${s.plannedDue} sevkiyat, yolda ${s.inTransit}, sürücüsüz ${s.unassignedDriver}, kabul bekliyor ${s.reported}',
        );
      case RolePreset.finance:
      case RolePreset.accounting:
        final c = d.collections;
        if (c == null) return null;
        final held = d.desk?.financeHeld ?? d.finance?.pending;
        return _PlateSpec(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Vadesi geçen',
          period: 'şu an',
          figure: Fmt.integer(c.overdueAmount.round()),
          unit: '₺',
          sentence: c.overdueCount == 0
              ? 'Vadesi geçen ödeme yok.'
              : '${Fmt.integer(c.overdueCount)} ödeme tahsil edilmedi',
          readouts: [
            PlateReadout(
              label: '${c.dueSoonDays} gün içinde',
              value: _compact(c.instrumentsDueSoonAmount).$1,
              unit: _compact(c.instrumentsDueSoonAmount).$2,
            ),
            PlateReadout(
              label: 'Belge kontrolü',
              value: Fmt.integer(c.documentsAwaitingCheck),
            ),
            if (held != null)
              PlateReadout(label: 'Finans onayı', value: Fmt.integer(held)),
          ],
          spoken: [
            'Vadesi geçen ${Fmt.moneyWhole(c.overdueAmount)}, ${c.overdueCount} ödeme',
            '${c.dueSoonDays} gün içinde ${Fmt.moneyWhole(c.instrumentsDueSoonAmount)}',
            'belge kontrolü ${c.documentsAwaitingCheck}',
            if (held != null) 'finans onayı $held',
          ].join(', '),
        );
      default:
        return null;
    }
  }

  /// "460.000" + "₺" ya da "2,25" + "mn ₺" (okuma değeri sütununa sığsın).
  static (String, String) _compact(double v) {
    if (v.abs() >= 1e6) {
      return (Fmt.number(v / 1e6, minFraction: 2, maxFraction: 2), 'mn ₺');
    }
    return (Fmt.integer(v.round()), '₺');
  }

  static String _today() {
    final w = TrTime.wall(TrTime.now());
    return '${w.day} ${Fmt.monthNames[w.month - 1]}';
  }
}

class _PlateSpec {
  const _PlateSpec({
    required this.icon,
    required this.title,
    required this.figure,
    required this.readouts,
    required this.spoken,
    this.period,
    this.unit,
    this.word,
    this.sentence,
  });

  final IconData icon;
  final String title;
  final String? period;
  final String figure;
  final String? unit;
  final String? word;
  final String? sentence;
  final List<PlateReadout> readouts;
  final String spoken;
}

/// Rol plakasının rakamı bu oturumda döndü mü (sekme değişimi, yenileme tekrar döndürmez; çıkışta
/// sıfırlanır).
final _rolePlateRolledProvider = NotifierProvider<_RolledController, bool>(
  _RolledController.new,
);

class _RolledController extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(currentUserIdProvider);
    return false;
  }

  void mark() {
    if (!state) state = true;
  }
}
