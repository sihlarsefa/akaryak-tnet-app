import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tasks/task_inbox.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../customer_more/api.dart';
import '../../customer_orders/api.dart';
import '../copy.dart';
import 'limits_page.dart';

/// Ana sayfada yerel tercih değişince (ipucu kapatıldı) yeniden çizim.
final homeLocalRevisionProvider = NotifierProvider<HomeLocalRevision, int>(
  HomeLocalRevision.new,
);

class HomeLocalRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// "1–21 Ekim": bu ayın bugüne kadarki dönemi.
String monthToDateLabel(DateTime wall) => wall.day == 1
    ? '1 ${Fmt.monthNames[wall.month - 1]}'
    : '1–${wall.day} ${Fmt.monthNames[wall.month - 1]}';

/// "2,25" + "mn ₺" (plaka okumalarında birim ayrı yazılır).
(String, String) compactMoneyParts(num value) {
  final s = Fmt.moneyCompact(value);
  final i = s.indexOf(' ');
  if (i < 0) return (s, '₺');
  return (s.substring(0, i), s.substring(i + 1));
}

// ─────────────────────────────── Sıra sizde ───────────────────────────────

/// Ana sayfa kahramanının görevleri (tasarım v4 §3.3): görev kutusunun sırası; talep eden yalnızca
/// kendi işlerini görür (yarım kalan sipariş), değilse sakin satır.
List<TaskItem> customerHeroTasks(TaskInbox inbox, CustomerUserRole role) =>
    role == CustomerUserRole.requester
    ? [
        for (final t in inbox.items)
          if (t.kind == TaskKind.draft) t,
      ]
    : inbox.items;

/// Ana sayfanın kahramanı (tasarım v4 §3.3–3.4): "Sıra sizde" kartı, görev kutusundan
/// ([customerTasksProvider]). Kart, Onaylar rozeti ve Onaylar › Bende aynı sayıyı gösterir.
/// Görevin birincil düğmesini bu ekran verir: eksik ödeme belgesi yükleme sayfasını açar, sipariş
/// kapalıysa bayi aranır, diğerleri görevin sayfasını (`?focus=` ile) açar. Satırların sözü (bayinin
/// kısa adı, kuruşsuz tutar) görev kutusundandır: Onaylar › Bende ile aynı.
class CustomerTaskHero extends ConsumerWidget {
  const CustomerTaskHero({super.key, required this.home});

  final CustomerHomeData home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(customerTasksProvider);
    final policy = ref.watch(accessPolicyProvider);
    final canCreate = policy.can(Pg.customerCreateOrder, Perm.create);
    final approvals = policy.can(Pg.customerApprovals);
    final requester = policy.customerRole == CustomerUserRole.requester;
    final items = customerHeroTasks(inbox, policy.customerRole);
    return AknTaskCard(
      tasks: [for (final t in items) _taskOf(context, ref, t)],
      total: requester ? items.where((t) => t.counts).length : inbox.count,
      calm: canCreate ? HomeCopy.calmCreate : HomeCopy.calmView,
      onSeeAll: () =>
          context.go(approvals ? AppRoutes.approvals : AppRoutes.orders),
    );
  }

  AknTask _taskOf(BuildContext context, WidgetRef ref, TaskItem t) {
    void open() => unawaited(context.push(t.location));
    switch (t.actionKind) {
      case TaskActionKind.uploadDocument:
        final doc = _documentOf(t);
        return t.toAknTask(
          onTap: open,
          onAction: doc == null
              ? open
              : () => unawaited(_upload(context, ref, doc)),
        );
      case TaskActionKind.callStation:
        final tel = ContactLinks.tel(home.station?.callNumber);
        return t.toAknTask(
          onTap: open,
          onAction: tel == null
              ? open
              : () => unawaited(
                  openExternal(
                    context,
                    ref,
                    tel,
                    failMessage: 'Arama başlatılamadı.',
                  ),
                ),
        );
      default:
        return t.toAknTask(onTap: open, onAction: open);
    }
  }

  /// Görevin eksik ödeme belgesi (ana sayfa verisinden; yükleme hedefi burada).
  PendingPaymentDocument? _documentOf(TaskItem t) {
    for (final d in home.pendingPaymentDocuments) {
      if (d.orderId != t.orderId) continue;
      if (t.documentKind != null && d.kind != t.documentKind) continue;
      return d;
    }
    return null;
  }

  static Future<void> _upload(
    BuildContext context,
    WidgetRef ref,
    PendingPaymentDocument doc,
  ) async {
    final done = await showPaymentDocumentSheet(
      context,
      target: doc.target,
      orderNumber: doc.orderNumber,
    );
    // Görev "Teklifi incele"ye döner (düğme etiketi yerinde değişir, onay işareti çıkar).
    if (done) ref.read(a2DataRevisionProvider.notifier).bump();
  }
}

/// Uygulama gönderim sırasında kapandıysa doğrulama durumu (kahramanın hemen altında): tek,
/// dokunulabilir kart; dokununca sihirbazın sonuç ekranı açılır.
class SubmissionStatusCard extends ConsumerWidget {
  const SubmissionStatusCard({
    super.key,
    required this.state,
    this.padding = const EdgeInsets.fromLTRB(
      AknSpace.page,
      12,
      AknSpace.page,
      0,
    ),
  });

  final SubmitState state;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final (tone, icon, title, message) = switch (state.phase) {
      SubmitPhase.success => (
        AknTone.ok,
        PhosphorIconsBold.check,
        OrdersCopy.successTitle,
        state.result?.message ?? '',
      ),
      SubmitPhase.partial => (
        AknTone.warn,
        PhosphorIconsRegular.arrowsSplit,
        OrdersCopy.partialTitle,
        state.result?.partialError ?? '',
      ),
      SubmitPhase.failed => (
        AknTone.danger,
        PhosphorIconsRegular.warningCircle,
        'Sipariş gönderilemedi',
        state.failure?.message ?? '',
      ),
      SubmitPhase.uncertain || SubmitPhase.askNewKey => (
        AknTone.warn,
        PhosphorIconsRegular.clock,
        OrdersCopy.uncertainTitle,
        'Sonucu görmek için dokunun.',
      ),
      _ => (
        AknTone.neutral,
        PhosphorIconsRegular.arrowsClockwise,
        OrdersCopy.checking,
        'Bağlantı yavaş; aynı işlem güvenle yeniden deneniyor.',
      ),
    };
    return Padding(
      padding: padding,
      child: AknCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        semanticLabel: message.isEmpty ? title : '$title. $message',
        onTap: () => context.push(AppRoutes.orderNew),
        child: ExcludeSemantics(
          child: Row(
            children: [
              _ToneTile(tone: tone, icon: icon, busy: state.isBusy),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: t.bodyStrong.copyWith(
                        height: 20 / 15,
                        color: c.ink,
                      ),
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        message,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall.copyWith(color: c.dim),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(PhosphorIconsRegular.caretRight, size: 18, color: c.dim),
            ],
          ),
        ),
      ),
    );
  }
}

/// 36 px durum karosu (gönderim kartı): tonun yumuşak kuyusu, sürerken dönen gösterge. Çekirdekte
/// tonlu, gösterge alabilen satır karosu yok (AknListTile yalnızca tehlike / uyarı tonlar).
class _ToneTile extends StatelessWidget {
  const _ToneTile({required this.tone, required this.icon, this.busy = false});

  final AknTone tone;
  final IconData icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tn = c.tone(tone);
    final neutral = tone == AknTone.neutral || tone == AknTone.info;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: neutral ? c.surfaceAlt : tn.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: busy
          ? const ChevronSpinner(size: 18)
          : Icon(icon, size: 20, color: neutral ? c.ink : tn.fg),
    );
  }
}

// ─────────────────────────────── İlk açılış ───────────────────────────────

/// "Nasıl çalışır" (tasarım v4 §4 AknFirstRunHint): ilk oturumda bir kez, kullanıcı başına bir
/// tercih anahtarıyla. "Anladım" kapatır; sonraki oturumlarda kendiliğinden görünmez. Siparişi
/// olmayan ve sipariş verebilen kullanıcıda "İlk siparişinizi verin" birincil düğmesi de vardır.
/// Adımlar role göredir (onaylayan, talep eden, görüntüleyen).
class HomeFirstRunHint extends ConsumerStatefulWidget {
  const HomeFirstRunHint({
    super.key,
    required this.steps,
    this.firstOrder = false,
  });

  final List<String> steps;

  /// Siparişi yok ve sipariş verebilir: "İlk siparişinizi verin".
  final bool firstOrder;

  /// Bu çalıştırmada gösterildi (aynı oturumda kapanana kadar kalır).
  static final Set<String> _shownThisRun = <String>{};

  /// İpucu bu kullanıcıya gösterilir mi: kapatılmadı ve (bu oturumda zaten göründü ya da hiç
  /// görülmedi).
  static bool visibleFor(PrefsStore prefs, String uid) {
    if (prefs.getBool(A2Keys.homeHintDone(uid))) return false;
    if (_shownThisRun.contains(uid)) return true;
    return !prefs.getBool(A2Keys.homeHintSeen(uid));
  }

  @override
  ConsumerState<HomeFirstRunHint> createState() => _HomeFirstRunHintState();
}

class _HomeFirstRunHintState extends ConsumerState<HomeFirstRunHint> {
  PrefsStore? _prefs() {
    try {
      return ref.read(prefsStoreProvider);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(homeLocalRevisionProvider);
    final uid = ref.watch(currentUserIdProvider);
    final prefs = _prefs();
    if (uid == null || prefs == null) return const SizedBox.shrink();
    if (!HomeFirstRunHint.visibleFor(prefs, uid)) {
      return const SizedBox.shrink();
    }
    if (HomeFirstRunHint._shownThisRun.add(uid)) {
      // Bir sonraki oturumda görünmesin.
      unawaited(prefs.setBool(A2Keys.homeHintSeen(uid), true));
    }
    return AknFirstRunHint(
      steps: widget.steps,
      primaryLabel: widget.firstOrder ? HomeCopy.firstOrder : null,
      onPrimary: widget.firstOrder
          ? () => context.push(AppRoutes.orderNew)
          : null,
      onDismiss: () async {
        await prefs.setBool(A2Keys.homeHintDone(uid), true);
        ref.read(homeLocalRevisionProvider.notifier).bump();
      },
    );
  }
}

// ─────────────────────────────── Plaka ───────────────────────────────

/// Bu ayın kartı (yönetici destesi görünmediğinde, "Sıra sizde"nin altında): bu ayın harcaması
/// (onaylanmış teklif tutarları; rakamlar yuvarlanarak gelir), son altı ayın çubukları (varsa) ve
/// okumalar: alınan yakıt, sipariş sayısı, geçen ayın toplamı. Kahraman değildir: düz beyaz kart
/// (`raised: false`), başlıkta simge yok. Dokununca Harcamalar açılır.
class MonthPlate extends StatelessWidget {
  const MonthPlate({
    super.key,
    required this.dashboard,
    this.months,
    this.onOpen,
    this.padding = const EdgeInsets.fromLTRB(
      AknSpace.page,
      16,
      AknSpace.page,
      0,
    ),
  });

  /// Kartın dış boşluğu.
  final EdgeInsetsGeometry padding;

  /// `stats` dolu olmalı.
  final CustomerDashboard dashboard;

  /// Son aylar (eskiden yeniye; son eleman bu ay). Biri bile yoksa çubuk çizilmez.
  final List<SpendingMonth>? months;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final stats = dashboard.stats!;
    final wall = TrTime.wall(TrTime.now());
    final period = monthToDateLabel(wall);
    final amount = stats.monthAmount;
    final m = months;
    final hasBars =
        m != null &&
        m.length > 1 &&
        m.last.year == wall.year &&
        m.last.month == wall.month;
    final values = hasBars ? [for (final x in m) x.amount] : const <double>[];
    final labels = hasBars
        ? [
            for (final x in m)
              x.shortLabel ?? Fmt.monthShort[(x.month - 1).clamp(0, 11)],
          ]
        : const <String>[];
    final projection = hasBars
        ? plateMonthEndProjection(values.last, wall)
        : null;
    final (prevValue, prevUnit) = compactMoneyParts(stats.prevMonthAmount);
    final spoken = [
      '${HomeCopy.monthPlate}, $period',
      Fmt.moneyWhole(amount),
      'alınan yakıt ${Fmt.liters(stats.monthLiters)}',
      '${stats.monthOrders} sipariş',
      'geçen ay ${Fmt.moneyCompact(stats.prevMonthAmount)}',
    ].join(', ');
    // Büyük yazıda (≥ 1,6×) destedeki gibi sıkı düzen: baş, rakam ve bir cümle (§5.3).
    final compact = MediaQuery.textScalerOf(context).scale(10) >= 16;
    final plate = AknPlate(
      raised: false,
      compact: compact,
      head: PlateHead(title: HomeCopy.monthPlate, period: period),
      figure: PlateFigure(value: Fmt.number(amount.round()), unit: '₺'),
      delta: compact
          ? PlateDelta(
              sentence:
                  '${Fmt.liters(stats.monthLiters)} yakıt, ${stats.monthOrders} sipariş',
            )
          : null,
      chart: hasBars
          ? PlateBars(
              values: values,
              labels: labels,
              projection: projection,
              valueLabels: [for (final v in values) Fmt.moneyCompact(v)],
              semanticLabels: [
                for (var i = 0; i < values.length; i++)
                  '${labels[i]}, ${Fmt.moneyWhole(values[i])}',
              ],
            )
          : null,
      below: PlateReadouts(
        items: [
          PlateReadout(
            label: 'Alınan yakıt',
            value: Fmt.number(stats.monthLiters, maxFraction: 0),
            unit: 'L',
          ),
          PlateReadout(label: 'Sipariş', value: '${stats.monthOrders}'),
          PlateReadout(label: 'Geçen ay', value: prevValue, unit: prevUnit),
        ],
      ),
    );
    return Padding(
      padding: padding,
      child: Semantics(
        label: spoken,
        button: onOpen != null,
        hint: onOpen == null ? null : 'Harcamaları açar',
        excludeSemantics: true,
        onTap: onOpen,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: plate,
        ),
      ),
    );
  }
}

// ─────────────────────────────── Bölümler ───────────────────────────────

/// Ana sayfa bölüm başlığı: çekirdeğin [SectionHeader]'ı (17/22 700, sayı soluk metin, sağda
/// "Tümü ›"), kahramanın altındaki ritimle.
Widget _header(
  String title, {
  int? count,
  String? actionLabel,
  VoidCallback? onAction,
}) => SectionHeader(
  title: title,
  count: count,
  actionLabel: onAction == null ? null : actionLabel,
  onAction: onAction,
  padding: const EdgeInsets.fromLTRB(24, 22, 12, 6),
);

/// "Yolda" (tasarım v4 §3.3): yalnızca bir araç yoldayken ya da bugün için planlıyken; tek satır,
/// sağda planlanan saat ve altında » rota çizgisi. Plaka ana sayfada yazılmaz (ayrıntıda kalır).
/// Canlı konum iddiası yok: araç işareti rotanın ortasında durur.
class OnTheWaySection extends StatelessWidget {
  const OnTheWaySection({super.key, required this.dashboard});

  final CustomerDashboard dashboard;

  /// Gösterilecek sevkiyat: yoldaki, yoksa bugün için planlı olan; ikisi de yoksa null.
  static DashboardShipmentRow? pick(CustomerDashboard d) {
    for (final s in d.shipments) {
      if (s.status == ShipmentStatus.inTransit) return s;
    }
    for (final s in d.shipments) {
      if (_today(s)) return s;
    }
    return null;
  }

  static bool _today(DashboardShipmentRow s) =>
      s.status == ShipmentStatus.planned &&
      s.scheduledAt != null &&
      TrTime.dayDiff(TrTime.now(), s.scheduledAt!) == 0;

  @override
  Widget build(BuildContext context) {
    final s = pick(dashboard);
    if (s == null) return const SizedBox.shrink();
    final moving = s.status == ShipmentStatus.inTransit;
    final count = dashboard.shipments
        .where((x) => x.status == ShipmentStatus.inTransit || _today(x))
        .length;
    final at = s.scheduledAt;
    final today = at != null && TrTime.dayDiff(TrTime.now(), at) == 0;
    final when = at == null
        ? null
        : today
        ? Fmt.time(at)
        : Fmt.dayMonth(at);
    final whenMeta = moving
        ? HomeCopy.plannedArrival
        : HomeCopy.plannedDelivery;
    // Ürün litreden önce, "Sıra sizde"deki gibi ("Motorin 10.000 L · Demir Petrol"; v4 P4:
    // her yerde aynı söz sırası).
    final product = s.productName;
    final liters = Fmt.liters(s.deliveredLiters ?? s.plannedLiters);
    final from = HomeCopy.shortCompany(s.stationTitle);
    final subtitle = [
      product == null || product.isEmpty ? liters : '$product $liters',
      if (from.isNotEmpty) from,
    ].join(' · ');
    final title = s.deliveryPointName ?? s.deliveryCity ?? s.orderNumber;
    void open() => context.push(AppRoutes.shipment(s.shipmentId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          moving ? HomeCopy.onTheWay : HomeCopy.arrivingToday,
          count: count > 1 ? count : null,
          actionLabel: HomeCopy.all,
          onAction: dashboard.openShipmentTotal > 1
              ? () => context.push(AppRoutes.shipments)
              : null,
        ),
        AknLedger(
          children: [
            AknListTile(
              title: title,
              subtitle: subtitle,
              amount: when,
              amountMeta: when == null ? null : whenMeta,
              footer: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TruckRoute(moving: moving, height: 22),
              ),
              semanticLabel: [
                if (moving) HomeCopy.onTheWay else HomeCopy.arrivingToday,
                title,
                subtitle,
                if (when != null) '$whenMeta $when',
              ].join(', '),
              onTap: () {
                AknHaptics.selection();
                open();
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// "Hızlı sipariş" (tasarım v4 §3.3): en çok iki satır — "Son siparişi tekrarla" (sihirbaz aynı
/// siparişle özete açılır) ve ilk şablon. Şablonlar sayfası "Tümü" ile.
class QuickOrderSection extends StatelessWidget {
  const QuickOrderSection({
    super.key,
    required this.lastOrder,
    required this.templates,
  });

  final DashboardLastOrder? lastOrder;
  final List<TemplateListItem> templates;

  @override
  Widget build(BuildContext context) {
    final last = lastOrder;
    final tpl = templates.firstOrNull;
    if (last == null && tpl == null) return const SizedBox.shrink();
    String? lastLine() {
      if (last == null) return null;
      final what = [
        if (last.productName != null && last.productName!.isNotEmpty)
          last.productName!,
        if (last.quantityLiters > 0) Fmt.liters(last.quantityLiters),
      ].join(' ');
      return [
        if (what.isNotEmpty) what,
        if (last.deliveryPointName != null) last.deliveryPointName!,
      ].join(' · ');
    }

    final rows = <Widget>[
      if (last != null)
        AknListTile(
          title: HomeCopy.reorderLast,
          subtitle: lastLine(),
          showChevron: true,
          semanticLabel: [HomeCopy.reorderLast, ?lastLine()].join(', '),
          onTap: () {
            AknHaptics.selection();
            context.push(AppRoutes.orderNewFrom(reorder: last.orderId));
          },
        ),
      if (tpl != null)
        AknListTile(
          title: tpl.name,
          subtitle: tpl.subtitle.replaceAll(', ', ' · '),
          showChevron: true,
          semanticLabel: '${tpl.name} şablonuyla sipariş ver',
          onTap: () {
            AknHaptics.selection();
            context.push(AppRoutes.orderNewFrom(template: tpl.id));
          },
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          HomeCopy.quickOrder,
          actionLabel: HomeCopy.all,
          onAction: templates.length > 1
              ? () => context.push(templatesRoute)
              : null,
        ),
        AknLedger(children: rows),
      ],
    );
  }
}

/// Başlıksız son kart (tasarım v4 §3.3): bayi başına limit kullanımı (4 px çubuk, yüzde) ve
/// "Bayiniz · Demir Petrol [Ara]". Limit satırı Limitler sayfasını açar.
class HomeLimitsLedger extends ConsumerWidget {
  const HomeLimitsLedger({super.key, required this.limits, this.station});

  final List<CustomerLimit> limits;
  final StationContact? station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final withLimit = limits.where((l) => l.hasLimit).toList()
      ..sort((a, b) => b.usedPct.compareTo(a.usedPct));
    final shown = (withLimit.isEmpty ? limits : withLimit).take(2).toList();
    final s = station;
    final rows = <Widget>[
      for (final l in shown) _LimitRow(limit: l),
      if (s != null) _StationRow(station: s),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: AknLedger(children: rows),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({required this.limit});

  final CustomerLimit limit;

  String _fmt(double? v) => v == null
      ? Fmt.dash
      : (limit.isLiters ? Fmt.liters(v) : Fmt.money(v, decimals: 0));

  @override
  Widget build(BuildContext context) {
    final l = limit;
    final title = HomeCopy.limitTitle(l.stationTitle);
    void open() {
      AknHaptics.selection();
      context.push(limitsRoute);
    }

    if (!l.hasLimit) {
      return AknListTile(
        title: title,
        amount: HomeCopy.unlimited,
        showChevron: true,
        semanticLabel: '$title: ${HomeCopy.unlimited}',
        onTap: open,
      );
    }
    final pct = '%${Fmt.number(l.usedPct, maxFraction: 0)}';
    final period = l.periodLabel.trim();
    final left = 'kalan ${_fmt(l.remaining)}';
    final full = l.usedPct >= 100;
    final near = !full && l.usedPct >= 80;
    return AknListTile(
      title: title,
      subtitle: period.isEmpty
          ? 'Kalan ${_fmt(l.remaining)}'
          : '$period · $left',
      amount: pct,
      showChevron: true,
      footer: UsageBar(
        value: (l.usedPct / 100).clamp(0.0, 1.5).toDouble(),
        height: 4,
      ),
      semanticLabel: [
        title,
        '$pct kullanıldı',
        left,
        if (full) 'limit doldu' else if (near) 'limite yaklaştınız',
      ].join(', '),
      onTap: open,
    );
  }
}

class _StationRow extends ConsumerWidget {
  const _StationRow({required this.station});

  final StationContact station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = station;
    final tel = ContactLinks.tel(s.callNumber);
    return AknListTile(
      title: HomeCopy.stationTitle(s.title),
      subtitle: s.city,
      trailing: tel == null
          ? null
          : AknButton.secondary(
              label: HomeCopy.call,
              icon: PhosphorIconsRegular.phone,
              size: AknButtonSize.small,
              semanticLabel: '${s.title} bayisini ara',
              onPressed: () => openExternal(
                context,
                ref,
                tel,
                failMessage: 'Arama başlatılamadı.',
              ),
            ),
    );
  }
}

/// Talep edenin "Taleplerim" bölümü (tasarım v4 §3.3): son talepler, durum cümlesiyle ("Şirket
/// onayında"); yalnızca reddedilen ya da iptal edilen talepte durum hapı.
class MyRequestsSection extends ConsumerWidget {
  const MyRequestsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeOrderRequestsProvider(false)).valueOrNull;
    final items = data?.items ?? const <OrderRequest>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final total = data?.total ?? items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(
          HomeCopy.myRequests,
          count: total,
          actionLabel: HomeCopy.all,
          onAction: () => context.push(AppRoutes.companyRequests),
        ),
        AknLedger(
          children: [
            for (final r in items)
              _RequestRow(
                request: r,
                onTap: () => context.push(AppRoutes.companyRequest(r.id)),
              ),
          ],
        ),
      ],
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request, required this.onTap});

  final OrderRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final lamp = AknStatus.companyRequestLamp(
      r.status,
      const StatusViewer.customer(canDecide: false),
      serverLabel: r.statusLabel,
      actor: r.decidedByName,
    );
    final points = <String>{
      for (final l in r.lines)
        if (l.deliveryPointName.trim().isNotEmpty) l.deliveryPointName.trim(),
    }.toList();
    final place = points.isEmpty
        ? null
        : points.length == 1
        ? points.first
        : '${points.first} ve ${points.length - 1} nokta';
    final title = '${r.productsSummary}, ${Fmt.liters(r.totalLiters)}';
    final subtitle = [if (!lamp.problem) lamp.label, ?place].join(' · ');
    final amount = r.estimatedAmount == null
        ? null
        : Fmt.money(r.estimatedAmount);
    return AknListTile(
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      amount: amount,
      amountMeta: amount == null ? null : 'tahmini',
      status: lamp.problem ? AknLamp.status(lamp) : null,
      semanticLabel: [
        title,
        lamp.label,
        ?place,
        if (amount != null) 'tahmini $amount',
        if (r.createdAt != null) Fmt.relative(r.createdAt),
      ].join(', '),
      onTap: () {
        AknHaptics.selection();
        onTap();
      },
    );
  }
}
