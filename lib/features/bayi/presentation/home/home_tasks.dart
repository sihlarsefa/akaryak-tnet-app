import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/tasks/task_inbox.dart';
import '../../../../core/models/models.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/bayi_grants.dart';
import '../../data/bayi_repository.dart';
import '../../data/home_models.dart';
import '../orders/orders_page.dart' show shortProduct;
import '../orders/quote_sheet.dart';
import '../widgets/bayi_widgets.dart'
    show keepUnits, openDestination, openPortal, showActionFailure;

/// "Tüm işler" sayfasının yolu (v4 tur 2, B18): ana sayfa kartının alt satırı buraya itilir.
const bayiTasksPath = AppRoutes.bayiTasks;

/// Bayi ana sayfasının "Sıra sizde" kartı ile "Tüm işler" sayfasının ortak işleri (v4 §3.4): kutudaki
/// işi karta çevirir ve ekran eylemlerini bağlar (kutu yalnızca veri tutar).
abstract final class BayiHomeTasks {
  /// Hattın sayısını zaten söylediği kuyruk (Plan): "Bugün" defterinde sayısız yazılır.
  static bool pipelineCounts(Object id) => id == 'plan';

  /// İş izleyenin mi: teklif kuyruğu yalnızca teklif verebilene.
  static bool mine(TaskItem t, BayiGrants g) => switch (t.kind) {
    TaskKind.quotes => g.quoteOnOrder || g.quoteOnDesk,
    _ => true,
  };

  /// İzleyenin işleri, kutunun sırasıyla.
  static List<AknTask> all(
    BuildContext context,
    WidgetRef ref,
    List<TaskItem> items,
    BayiGrants g,
    BayiHomeData data, {
    required bool pipeline,
    bool lead = true,
    VoidCallback? before,
  }) {
    final out = <AknTask>[];
    for (final t in items) {
      if (!mine(t, g)) continue;
      out.add(
        task(
          context,
          ref,
          t,
          g,
          data,
          pipeline: pipeline,
          lead: lead && out.isEmpty,
          before: before,
        ),
      );
    }
    return out;
  }

  /// Kutudaki işi karta çevirir; ekran eylemleri burada (v4 §3.4).
  ///
  /// * [lead]: kartın öndeki işi. Teklif işinde başlık müşteri, alt satır "Motorin 10.000 L ·
  ///   Körfez Garaj"; fiil yalnızca düğmede ("Teklif ver", v4 A22 P4).
  /// * [unnumbered]: hattın saydığı kuyruk "Bugün"de sayısız ("Sevkiyatı planlayın", B18).
  /// * Tüpraş fiyatı web portalında girilir: alt satır bunu söyler (B15).
  static AknTask task(
    BuildContext context,
    WidgetRef ref,
    TaskItem t,
    BayiGrants g,
    BayiHomeData data, {
    required bool pipeline,
    bool lead = false,
    bool unnumbered = false,
    VoidCallback? before,
  }) {
    void run(VoidCallback f) {
      before?.call();
      f();
    }

    void open() => run(() => openTask(context, ref, t, g, data));
    VoidCallback act = open;
    final id = t.orderId;
    if (t.actionKind == TaskActionKind.giveQuote && id != null) {
      act = () => run(() => unawaited(giveQuote(context, ref, id, g)));
    }
    var title = t.title;
    var subtitle = t.subtitle;
    if (lead && t.kind == TaskKind.quotes && id != null) {
      final row = _deskRow(data, id);
      if (row != null) {
        title = row.customerTitle ?? title;
        subtitle = _quoteLine(row);
      }
    }
    if (unnumbered && t.kind == TaskKind.plan) title = 'Sevkiyatı planlayın';
    if (t.kind == TaskKind.tuprasToday) {
      subtitle ??= 'Web portalında açılır';
    }
    return AknTask(
      id: t.id,
      title: title,
      subtitle: subtitle,
      icon: TaskItem.iconOf(t.kind),
      tone: switch (t.tone) {
        TaskTone.yourMove => AknTaskTone.yourMove,
        TaskTone.danger => AknTaskTone.danger,
        TaskTone.warn => AknTaskTone.warn,
        TaskTone.neutral => AknTaskTone.neutral,
      },
      figure: t.figure,
      amount: t.amount,
      deadline: t.deadline,
      time: t.time,
      actionLabel: t.actionLabel,
      onAction: act,
      // Hat teklif sayısını zaten söylüyor: "6 sipariş teklif bekliyor" yinelenmez (P4).
      caption: t.kind == TaskKind.quotes && pipeline ? null : t.caption,
      note: t.note,
      onTap: open,
      counts: t.counts,
      // Web portalında açılan iş (bugünün Tüpraş fiyatı): kart ↗ ile önceden söyler (B15).
      external: t.external,
    );
  }

  /// Masa satırı (öndeki teklifin müşterisi, ürünü ve yeri).
  static DashboardOrderRow? _deskRow(BayiHomeData data, int orderId) {
    final d = data.desk;
    if (d == null) return null;
    for (final o in [...d.expiring, ...d.awaitingQuoteList]) {
      if (o.orderId == orderId) return o;
    }
    return null;
  }

  /// "Motorin 10.000 L · Körfez Garaj": ürün ile litresi ve yer kendi içinde bölünmez (v4 A17).
  static String _quoteLine(DashboardOrderRow o) {
    final product = o.productName == null ? null : shortProduct(o.productName!);
    final place = o.deliveryPointName ?? o.deliveryCity;
    return [
      keepUnits(
        [?product, Fmt.liters(o.quantityLiters)].join(' '),
      ).replaceAll(' ', ' '),
      ?place?.replaceAll(' ', ' '),
    ].join(' · ');
  }

  static void openTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem t,
    BayiGrants g,
    BayiHomeData data,
  ) {
    switch (t.kind) {
      case TaskKind.quotes:
        final id = t.orderId;
        if (id != null && g.viewOrders) {
          unawaited(GoRouter.of(context).push(AppRoutes.bayiOrder(id)));
        } else {
          openDestination(context, AppRoutes.quoteDesk);
        }
      case TaskKind.tuprasToday:
        final check = data.setup?.checks
            .where((c) => c.key == 'tupras-today')
            .firstOrNull;
        unawaited(openPortal(context, ref, check?.portalPath ?? ''));
      default:
        openDestination(context, t.location);
    }
  }

  /// "Teklif ver": siparişi alıp teklif sayfasını açar; teklif verilemiyorsa (yetki, finans engeli)
  /// siparişi açar.
  static Future<void> giveQuote(
    BuildContext context,
    WidgetRef ref,
    int orderId,
    BayiGrants g,
  ) async {
    if (!ref.read(isOnlineProvider)) {
      AppToast.info(
        'Çevrimdışısınız; teklif için bağlantı gerekli.',
        context: context,
      );
      return;
    }
    try {
      final order = await ref.read(bayiRepositoryProvider).order(orderId);
      if (!context.mounted) return;
      if (!g.canQuoteOrder(order.status, order.financeStatus)) {
        if (g.viewOrders) {
          unawaited(GoRouter.of(context).push(AppRoutes.bayiOrder(orderId)));
        } else {
          openDestination(context, AppRoutes.quoteDesk);
        }
        return;
      }
      await showQuoteSheet(context, order);
    } catch (e) {
      if (context.mounted) showActionFailure(context, e);
    }
  }
}
