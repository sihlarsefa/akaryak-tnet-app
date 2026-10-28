import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../customer_more/api.dart';
import '../../customer_orders/api.dart';
import '../copy.dart';
import 'limits_page.dart';

/// Ana sayfada yerel tercih değişince (ipucu / asistan kartı kapatıldı) yeniden çizim.
final homeLocalRevisionProvider = NotifierProvider<HomeLocalRevision, int>(
  HomeLocalRevision.new,
);

class HomeLocalRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Bölüm kartlarının iç kenarı (satırlar, başlık ve içerik bu çizgide hizalanır).
const _gutter = 18.0;

/// Bant altındaki kartların ve kuyuların yan boşluğu: kahraman kartıyla aynı kenar (bant
/// bindirmesinin, [AknBandOverlap], yan boşluğu — tüm rollerin ana sayfasında aynı).
double homeBoxGutter(BuildContext context) => const AknBandOverlap(
  child: SizedBox.shrink(),
).padding.resolve(Directionality.of(context)).left;

/// Kuyuların (uyarı, ipucu, taslak) dış boşluğu.
EdgeInsets _wellMargin(BuildContext context, double top) {
  final g = homeBoxGutter(context);
  return EdgeInsets.fromLTRB(g, top, g, 0);
}

/// Ana sayfa kartının yüzeyi (tasarım v3 §3): beyaz, r22, yumuşak kart gölgesi (koyu temada kısa
/// gölge + 1 px çizgi); içerik köşelere kırpılır. [pressable]: basınca 0,97'ye iner ve gölge
/// sayfaya oturur.
class _HomeSurface extends StatefulWidget {
  const _HomeSurface({required this.child, this.pressable = false});

  final Widget child;
  final bool pressable;

  @override
  State<_HomeSurface> createState() => _HomeSurfaceState();
}

class _HomeSurfaceState extends State<_HomeSurface> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.pressable || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    const radius = AknRadius.section;
    Widget surface = AnimatedContainer(
      duration: AknMotion.of(
        context,
        _down ? AknMotion.press : AknMotion.pressOut,
      ),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: radius,
        boxShadow: _down ? AknShadows.pressed(c) : AknShadows.card(c),
      ),
      foregroundDecoration: c.isDark
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: c.line),
            )
          : null,
      child: ClipRRect(
        borderRadius: radius,
        child: Material(type: MaterialType.transparency, child: widget.child),
      ),
    );
    if (widget.pressable) {
      surface = Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: PressScale(child: surface),
      );
    }
    return surface;
  }
}

/// 40 px yuvarlak köşeli simge karosu (tasarım v3 §4): sessiz kuyu ve mürekkep simge; [tone]
/// verilirse tonun yumuşak kuyusu ("sıra sizde" turuncu, tamam yeşil, sorun kırmızı).
class _Tile extends StatelessWidget {
  const _Tile({this.icon, this.tone, this.child})
    : assert(icon != null || child != null);

  final IconData? icon;
  final AknTone? tone;

  /// [icon] yerine (ör. dönen gösterge).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final (bg, fg) = switch (tone) {
      null || AknTone.info => (c.surfaceAlt, c.ink),
      AknTone.neutral => (c.surfaceAlt, c.dim),
      AknTone.brand => (c.brandSoft, c.brandInk),
      final t => (c.tone(t).bg, c.tone(t).fg),
    };
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.base),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AknRadius.sm),
        ),
        child: child ?? Icon(icon, size: 22, color: fg),
      ),
    );
  }
}

/// Bölüm satırı başlığı (tasarım v3 §4 AknListTile): 15/20 600 mürekkep.
TextStyle _rowTitle(BuildContext context) => context.aknText.bodyStrong
    .copyWith(height: 20 / 15, color: context.akn.ink);

/// Satırda tutar başlığın yanında mı durur (tasarım v3): başlık tek satırda kalmalı; sağdaki tutar
/// sütunuyla aynı satıra sığmıyorsa tutar alt satıra iner ([_AmountLine]). [width]: metin sütunu.
bool _amountBeside(
  BuildContext context, {
  required double width,
  required String title,
  String? amount,
  String? meta,
}) {
  if (amount == null && meta == null) return true;
  if (!width.isFinite) return true;
  final t = context.aknText;
  final scaler = MediaQuery.textScalerOf(context);
  double measure(String? s, TextStyle style) {
    if (s == null) return 0;
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  final right = math.max(measure(amount, t.amount), measure(meta, t.bodySmall));
  return measure(title, _rowTitle(context)) + 12 + right <= width;
}

/// Rakamdan sonra gelen birimin önündeki boşluk ("8.000 L", "338.800,00 ₺", "42,35 ₺/L").
final RegExp _unitGap = RegExp(
  r'(\d) (?=(?:L|₺|m³)(?![\p{L}\p{N}]))',
  unicode: true,
);

/// Sayıyı birimiyle aynı satırda tutar (bölünmez boşluk): satır kırılırsa "8.000" / "L" kopukluğu
/// olmaz. Görünüm aynıdır.
String _keepUnits(String text) =>
    text.replaceAllMapped(_unitGap, (m) => '${m[1]}\u00A0');

/// Satır başlığı tek satıra sığıyorsa aynen; sığmıyorsa sayı birimiyle aynı satırda kalarak
/// kaydırılır ("Motorin," / "30.000 L"). [width]: metin sütunu.
String _wrapSafeTitle(BuildContext context, String title, double width) {
  if (!width.isFinite || !_unitGap.hasMatch(title)) return title;
  final tp = TextPainter(
    text: TextSpan(text: title, style: _rowTitle(context)),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final fits = tp.width <= width;
  tp.dispose();
  return fits ? title : _keepUnits(title);
}

/// Başlığın yanına sığmayan tutar: alt satırda tablo rakamlı tutar ve küçük açıklaması.
class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.amount, this.meta});

  final String amount;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Text.rich(
      TextSpan(
        text: amount,
        style: t.amount.copyWith(color: c.ink),
        children: [
          if (meta != null)
            TextSpan(
              text: '  $meta',
              style: t.bodySmall.copyWith(color: c.dim),
            ),
        ],
      ),
    );
  }
}

/// Ana sayfa bölüm kartı (tasarım v3 §4): bandın altındaki kırık beyaz sayfada yüzen beyaz kart,
/// r22, yumuşak kart gölgesi. Bölümün başlığı ve satırları içinde durur; basılı satır vurgusu
/// köşelere kırpılır.
class HomeSectionBox extends StatelessWidget {
  const HomeSectionBox({
    super.key,
    required this.child,
    this.top = 12,
    this.padding = const EdgeInsets.only(bottom: 6),
  });

  final Widget child;

  /// Kartın üstündeki boşluk.
  final double top;

  /// Kartın iç boşluğu (bölümlerin kendi yan boşlukları korunur).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _wellMargin(context, top),
    child: _HomeSurface(
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Bölüm başlığının hemen altındaki satırın dolgusu: başlıkla satır arası sıkı (eylemli başlık
/// 48 px dokunma alanı nedeniyle zaten boşluk bırakır).
EdgeInsets homeFirstRow({required bool action}) =>
    EdgeInsets.fromLTRB(_gutter, action ? 2 : 10, _gutter, 12);

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

/// Ana sayfa bölüm başlığı (tasarım v3 §4 SectionHeader): 18/24 800 başlık, sayı hapı ve sağda
/// "Tümü" bağlantısı. Başlık satırı eylemin 48 px dokunma alanı yüzünden aşağı kaymasın diye
/// dolgusu ölçülür; böylece başlığın kartın üstüne uzaklığı her zaman [top] olur. Altındaki ilk
/// satır [homeFirstRow] dolgusunu alır.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.top = 20,
  });

  final String title;
  final int? count;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double top;

  @override
  Widget build(BuildContext context) {
    final action = actionLabel != null && onAction != null;
    var lift = 0.0;
    if (action) {
      // Başlık 18/24 (v3 §4), en çok 1,6× büyür.
      final scaler = MediaQuery.textScalerOf(context);
      final line = scaler.clamp(maxScaleFactor: 1.6).scale(18) * 24 / 18;
      final sub = subtitle == null ? 0.0 : 2 + scaler.scale(14) * 20 / 14;
      lift = ((AknSpace.minTap - line - sub) / 2).clamp(0.0, 12.0);
    }
    // Büyük yazıda sayı ayrı satıra düşmesin (pano ekran 9): sayı yalnızca normal boyutta.
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    return SectionHeader(
      title: title,
      count: large ? null : count,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      padding: EdgeInsets.fromLTRB(
        _gutter,
        (top - lift).clamp(0.0, top),
        action ? 8 : _gutter,
        0,
      ),
    );
  }
}

/// Bu ayın kahraman kartı (tasarım v3 §4 AknPlate): yönetici destesi görünmediğinde bandın üstüne
/// binen tek kart. Bu ayın harcaması (onaylanmış teklif tutarları; rakamlar yuvarlanarak gelir),
/// son altı ayın çubukları (varsa; bu ay turuncu geçişli) ve okumalar: alınan yakıt, sipariş sayısı,
/// geçen ayın toplamı. Dokununca Harcamalar açılır.
class MonthPlate extends StatelessWidget {
  const MonthPlate({
    super.key,
    required this.dashboard,
    this.months,
    this.onOpen,
    this.padding = const EdgeInsets.fromLTRB(_gutter, 4, _gutter, 0),
  });

  /// Kartın dış boşluğu (ana sayfada bant bindirmesi [AknBandOverlap] verir: sıfır).
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
      compact: compact,
      head: PlateHead(
        icon: PhosphorIconsRegular.money,
        title: HomeCopy.monthPlate,
        period: period,
      ),
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

/// Sipariş verilemiyor: neden + (finans ek bilgi istiyorsa) "Yanıtla" + bayi iletişimi.
class OrderingBanner extends StatelessWidget {
  const OrderingBanner({super.key, required this.home, this.top = 16});

  final CustomerHomeData home;
  final double top;

  @override
  Widget build(BuildContext context) {
    final o = home.ordering;
    final info = o?.infoRequested ?? false;
    final approval = o?.openApprovalRequestId;
    return Padding(
      padding: _wellMargin(context, top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknBanner(
            tone: info ? AknTone.warn : AknTone.danger,
            icon: info
                ? PhosphorIconsRegular.envelopeSimple
                : PhosphorIconsRegular.prohibit,
            title: info ? HomeCopy.financeInfo : HomeCopy.blockedTitle,
            message:
                o?.blockReason ??
                (home.hasStations
                    ? 'Bu bayide şu an sipariş veremezsiniz. Bayinizi arayıp nedenini sorabilirsiniz.'
                    : 'Bağlı bayi bulunamadı. Sipariş verebilmek için bayinizin sizi cari olarak eklemesi gerekir.'),
            actionLabel: info ? 'Yanıtla' : null,
            onAction: info
                ? () => context.push(
                    approval == null
                        ? AppRoutes.financeInfo
                        : AppRoutes.approval(approval),
                  )
                : null,
          ),
          if (home.station != null) ...[
            const SizedBox(height: 8),
            StationContactButtons(station: home.station, dense: true),
          ],
        ],
      ),
    );
  }
}

/// Dokunulabilir durum kartı (tasarım v3 §4): beyaz r22 kart; başta tonun yumuşak kuyusunda simge
/// karosu, başlık, bir cümle ve ok. Basınca kart 0,97'ye iner. Taslak ve gönderim durumu.
class HomeWell extends StatelessWidget {
  const HomeWell({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.leading,
    this.tone = AknTone.info,
    this.onTap,
    this.top = 16,
  });

  final String title;
  final double top;
  final String? message;
  final IconData? icon;

  /// [icon] yerine (ör. dönen gösterge).
  final Widget? leading;
  final AknTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final msg = message;
    final tap = onTap;
    return Padding(
      padding: _wellMargin(context, top),
      child: Semantics(
        button: tap != null,
        label: msg == null || msg.isEmpty ? title : '$title. $msg',
        excludeSemantics: true,
        onTap: tap,
        child: _HomeSurface(
          pressable: tap != null,
          child: InkWell(
            onTap: tap == null
                ? null
                : () {
                    AknHaptics.selection();
                    tap();
                  },
            highlightColor: c.surfaceAlt,
            splashFactory: NoSplash.splashFactory,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    _Tile(
                      icon: icon ?? AknStatus.toneIcon(tone),
                      tone: tone,
                      child: leading,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, style: _rowTitle(context)),
                          if (msg != null && msg.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              msg,
                              style: t.bodySmall.copyWith(color: c.dim),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (tap != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        PhosphorIconsRegular.caretRight,
                        size: 18,
                        color: c.dim,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uygulama gönderim sırasında kapandıysa ana sayfada doğrulama durumu.
class SubmissionStatusCard extends ConsumerWidget {
  const SubmissionStatusCard({super.key, required this.state, this.top = 16});

  final SubmitState state;
  final double top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (tone, icon, title, message) = switch (state.phase) {
      SubmitPhase.success => (
        AknTone.ok,
        PhosphorIconsFill.checkCircle,
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
        AknTone.info,
        PhosphorIconsRegular.arrowsClockwise,
        OrdersCopy.checking,
        'Bağlantı yavaş; aynı işlem güvenle yeniden deneniyor.',
      ),
    };
    return HomeWell(
      top: top,
      tone: tone,
      icon: icon,
      leading: state.isBusy ? const ChevronSpinner(size: 20) : null,
      title: title,
      message: message,
      onTap: () => context.push(AppRoutes.orderNew),
    );
  }
}

/// "Yarım kalan siparişinize devam edin".
class ResumeDraftCard extends StatelessWidget {
  const ResumeDraftCard({super.key, required this.summary, this.top = 16});

  final DraftSummary summary;
  final double top;

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (summary.partial) 'Kalan satırlar',
      if (summary.lineCount > 0) '${summary.lineCount} satır',
      if (summary.totalLiters > 0) Fmt.liters(summary.totalLiters),
      if (summary.savedAt != null) Fmt.relative(summary.savedAt),
    ].join(', ');
    return HomeWell(
      top: top,
      tone: AknTone.brand,
      icon: summary.pendingSubmission
          ? PhosphorIconsRegular.arrowsClockwise
          : PhosphorIconsRegular.notePencil,
      title: summary.pendingSubmission
          ? HomeCopy.resumeChecking
          : HomeCopy.resumeTitle,
      message: detail,
      onTap: () => context.push(AppRoutes.orderNew),
    );
  }
}

/// İlk girişte bir kez: "İlk siparişinizi verin" (kapatılabilir).
class FirstOrderTip extends StatelessWidget {
  const FirstOrderTip({
    super.key,
    required this.onStart,
    required this.onDismiss,
    this.top = 16,
  });

  final VoidCallback onStart;
  final Future<void> Function() onDismiss;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: _wellMargin(context, top),
    child: AknBanner(
      tone: AknTone.brand,
      icon: PhosphorIconsRegular.lightbulbFilament,
      title: HomeCopy.tipTitle,
      message: HomeCopy.tipMessage,
      actionLabel: HomeCopy.newOrder,
      onAction: onStart,
      onClose: () => unawaited(onDismiss()),
    ),
  );
}

/// "22 Ekim Perşembe teslim" (teklifin ya da talebin teslim günü).
String? deliveryDayPhrase(DateTime? instant) {
  if (instant == null) return null;
  final w = TrTime.wall(instant);
  return '${w.day} ${Fmt.monthNames[w.month - 1]} '
      '${Fmt.weekdayNames[w.weekday - 1]} teslim';
}

/// Karar bekleyen teklifler (tasarım v3 §4 bölüm kartı): yalnızca en acil satır; birden fazlaysa
/// "Tümü". Satır: turuncu kuyuda teklif karosu, "Demir Petrol teklifi" ve tablo rakamlı tutar,
/// ürün / litre / nokta ve ₺/L; içeriden bir çizginin altında teslim günü ve geri sayım (karar
/// verebilen için turuncu, "sıra sizde").
class DecisionsSection extends ConsumerWidget {
  const DecisionsSection({
    super.key,
    required this.rows,
    required this.total,
    required this.expiryEnabled,
    this.canDecide = true,
    this.headerTop = 24,
  });

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final List<DashboardOrderRow> rows;
  final int total;
  final bool expiryEnabled;

  /// Onaylayan / yönetici: geri sayım "sıra sizde" rengindedir.
  final bool canDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final config = ref.watch(orderingConfigValueProvider);
    final expiry = config.expiryEnabled(expiryEnabled);
    final r = _mostUrgent(rows);
    final deadline = expiry && r.expiresAt != null
        ? config.deviceDeadline(r.expiresAt!)
        : null;
    final day = deliveryDayPhrase(
      r.latestDeliveryDate ?? r.requestedDeliveryDate,
    );
    final left = deadline?.difference(TrTime.now());
    final spoken = [
      HomeCopy.quoteTitle(r.stationTitle),
      r.orderNumber,
      ?r.productName,
      Fmt.liters(r.quantityLiters),
      ?r.deliveryPointName,
      if (r.latestTotalAmountTry != null) Fmt.money(r.latestTotalAmountTry),
      if (r.latestUnitPriceTry != null)
        'litresi ${Fmt.unitPrice(r.latestUnitPriceTry)}',
      ?day,
      if (left != null && left > Duration.zero)
        'teklif ${CountdownBadge.spoken(left)} içinde sona eriyor',
    ].join(', ');
    final lamp = deadline == null
        ? AknLamp.status(
            AknStatus.orderLamp(
              OrderStatus.awaitingApproval,
              StatusViewer.customer(canDecide: canDecide),
            ),
          )
        : (day == null
              ? null
              : Text(day, style: t.bodySmall.copyWith(color: c.dim)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: HomeCopy.decisions,
          count: total,
          actionLabel: total > 1 ? HomeCopy.all : null,
          onAction: total > 1
              ? () => context.push('${AppRoutes.orders}?segment=decision')
              : null,
        ),
        LayoutBuilder(
          builder: (context, box) {
            final title = HomeCopy.quoteTitle(r.stationTitle);
            final amount = r.latestTotalAmountTry == null
                ? null
                : Fmt.money(r.latestTotalAmountTry);
            final meta = r.latestUnitPriceTry == null
                ? null
                : Fmt.unitPrice(r.latestUnitPriceTry);
            final beside = _amountBeside(
              context,
              width: box.maxWidth - 2 * _gutter - 56,
              title: title,
              amount: amount,
              meta: meta,
            );
            return AknListTile(
              padding: homeFirstRow(action: total > 1),
              leading: _Tile(
                icon: PhosphorIconsRegular.invoice,
                tone: canDecide ? AknTone.brand : null,
              ),
              titleStyle: _rowTitle(context),
              title: title,
              subtitle: _keepUnits(
                [
                  r.productName,
                  Fmt.liters(r.quantityLiters),
                  r.deliveryPointName,
                ].whereType<String>().join(', '),
              ),
              amount: beside ? amount : null,
              amountMeta: beside ? meta : null,
              status: beside || amount == null
                  ? null
                  : _AmountLine(amount: amount, meta: meta),
              // Teslim günü ve geri sayım kart genişliğince, ince bir çizginin altında.
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(height: 1, thickness: 1, color: c.lineSoft),
                  const SizedBox(height: 10),
                  AknStatusLine(
                    lamp: lamp,
                    trailing: deadline == null
                        ? null
                        : CountdownBadge(
                            deadline: deadline,
                            yourMove: canDecide,
                            subject: 'Teklif',
                          ),
                  ),
                ],
              ),
              semanticLabel: spoken,
              onTap: () {
                AknHaptics.selection();
                context.push(AppRoutes.order(r.orderId));
              },
            );
          },
        ),
      ],
    );
  }

  static DashboardOrderRow _mostUrgent(List<DashboardOrderRow> rows) {
    var best = rows.first;
    for (final r in rows.skip(1)) {
      final a = best.expiresAt;
      final b = r.expiresAt;
      if (b != null && (a == null || b.isBefore(a))) best = r;
    }
    return best;
  }
}

/// Yüklenmesi beklenen ödeme belgeleri (sunucu listeler; yüklenince düşer).
class PendingDocumentsSection extends StatelessWidget {
  const PendingDocumentsSection({
    super.key,
    required this.documents,
    required this.onUploaded,
    this.headerTop = 24,
  });

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final List<PendingPaymentDocument> documents;
  final Future<void> Function() onUploaded;

  @override
  Widget build(BuildContext context) {
    final shown = documents.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: HomeCopy.documents,
          count: documents.length,
          subtitle: HomeCopy.documentsHint,
        ),
        AknLedger(
          children: [
            for (final (i, d) in shown.indexed)
              AknListTile(
                padding: i == 0
                    ? homeFirstRow(action: false)
                    : const EdgeInsets.symmetric(
                        horizontal: _gutter,
                        vertical: 12,
                      ),
                leading: const _Tile(
                  icon: PhosphorIconsRegular.fileArrowUp,
                  tone: AknTone.brand,
                ),
                titleStyle: _rowTitle(context),
                title: d.label,
                subtitle: [
                  d.orderNumber,
                  if (d.stationTitle != null)
                    HomeCopy.shortCompany(d.stationTitle),
                ].join(', '),
                trailing: AknButton.secondary(
                  label: 'Yükle',
                  icon: PhosphorIconsRegular.uploadSimple,
                  size: AknButtonSize.small,
                  semanticLabel: '${d.orderNumber} ${d.label} yükle',
                  onPressed: () async {
                    final done = await showPaymentDocumentSheet(
                      context,
                      target: d.target,
                      orderNumber: d.orderNumber,
                    );
                    if (done) await onUploaded();
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Teslimat bölümü (tasarım v3 §4 bölüm kartı): sevkiyat yoldayken "Yolda", değilse "Teslimat".
/// Tek satır: tır karosu, nokta, büyük saat (planlanan varış), litre / ürün / plaka ve yoldaysa
/// turuncu rota çizgisi. Canlı konum iddiası yok: araç işareti rotanın ortasında durur, saat
/// bayinin planladığı saattir.
class ActiveDeliveryCard extends StatelessWidget {
  const ActiveDeliveryCard({
    super.key,
    required this.shipment,
    required this.openTotal,
    this.station,
    this.canDecide = true,
    this.headerTop = 24,
  });

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final DashboardShipmentRow shipment;
  final int openTotal;
  final StationContact? station;

  /// Teslimatı onaylayabilir (yönetici / onaylayan).
  final bool canDecide;

  @override
  Widget build(BuildContext context) {
    final s = shipment;
    final inTransit = s.status == ShipmentStatus.inTransit;
    void open() => context.push(AppRoutes.shipment(s.shipmentId));
    final many = openTotal > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: inTransit ? HomeCopy.inTransit : HomeCopy.delivery,
          actionLabel: many ? HomeCopy.all : HomeCopy.track,
          onAction: many ? () => context.push(AppRoutes.shipments) : open,
        ),
        DeliveryRow(
          shipment: s,
          canDecide: canDecide,
          onTap: open,
          padding: homeFirstRow(action: true).copyWith(bottom: 14),
        ),
      ],
    );
  }
}

/// Teslimat satırı: başlık ve saat (sayı yazısı, sağda), ikinci satır ve "planlanan varış", durum
/// lambası (yolda değilken) ve rota çizgisi (yoldayken). Dar ekranda ve büyük yazıda saat başlığın
/// altına iner.
class DeliveryRow extends StatefulWidget {
  const DeliveryRow({
    super.key,
    required this.shipment,
    required this.onTap,
    this.canDecide = true,
    this.padding = const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 14),
  });

  final DashboardShipmentRow shipment;
  final VoidCallback onTap;
  final bool canDecide;
  final EdgeInsets padding;

  @override
  State<DeliveryRow> createState() => _DeliveryRowState();
}

class _DeliveryRowState extends State<DeliveryRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final s = widget.shipment;
    final inTransit = s.status == ShipmentStatus.inTransit;
    final at = s.scheduledAt;
    final today = at != null && TrTime.dayDiff(TrTime.now(), at) == 0;
    final (String? atText, String? atMeta) = at == null
        ? (null, null)
        : today
        ? (
            Fmt.time(at),
            inTransit ? HomeCopy.plannedArrival : HomeCopy.plannedDelivery,
          )
        : (Fmt.dayMonth(at), HomeCopy.plannedDelivery);
    final title = s.deliveryPointName ?? s.orderNumber;
    final product = s.productName == null
        ? null
        : TurkishText.lower(s.productName!);
    final liters = Fmt.liters(s.deliveredLiters ?? s.plannedLiters);
    final secondParts = [
      product == null ? liters : '$liters $product',
      if (s.vehiclePlate != null) Fmt.plate(s.vehiclePlate),
    ];
    final second = secondParts.join(', ');
    final lamp = inTransit
        ? null
        : AknLamp.status(
            AknStatus.shipmentLamp(
              s.status,
              StatusViewer.customer(canDecide: widget.canDecide),
            ),
          );
    final from = s.stationTitle == null
        ? null
        : HomeCopy.shortCompany(s.stationTitle);
    final spoken = [
      inTransit ? 'Yolda' : lamp?.label,
      if (from != null) '$from bayisinden',
      title,
      second,
      if (atText != null) '$atMeta $atText',
    ].whereType<String>().join(', ');
    final whenStyle = t.number.copyWith(color: c.ink, height: 1);
    final metaStyle = t.bodySmall.copyWith(color: c.dim);
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;

    Widget content(bool stack) {
      final titleText = Text(
        title,
        style: _rowTitle(context),
        maxLines: stack ? 4 : 2,
        overflow: TextOverflow.ellipsis,
      );
      // Plaka bölünmez: sığmazsa bütün olarak alt satıra geçer.
      // Litre birimiyle aynı satırda kalır ("10.000 L motorin").
      final Widget secondText = secondParts.length < 2
          ? Text(
              _keepUnits(second),
              style: metaStyle,
              maxLines: stack ? 4 : 2,
              overflow: TextOverflow.ellipsis,
            )
          : Wrap(
              children: [
                Text('${_keepUnits(secondParts.first)}, ', style: metaStyle),
                Text(secondParts.last, style: metaStyle, softWrap: false),
              ],
            );
      final Widget main;
      if (stack) {
        main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            titleText,
            if (atText != null) ...[
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  text: atText,
                  style: whenStyle,
                  children: [TextSpan(text: '  $atMeta', style: metaStyle)],
                ),
              ),
            ],
            const SizedBox(height: 4),
            secondText,
          ],
        );
      } else {
        // Baş karosu (tır), başlık ve saat; altında ikinci satır ve "planlanan varış".
        main = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Tile(
              icon: PhosphorIconsRegular.truck,
              tone: inTransit ? null : lamp?.tone,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: titleText),
                      if (atText != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          atText,
                          style: whenStyle,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(child: secondText),
                      if (atMeta != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          atMeta,
                          style: metaStyle,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          main,
          if (lamp != null) ...[const SizedBox(height: 10), lamp],
          if (inTransit) ...[
            const SizedBox(height: 16),
            const TruckRoute(moving: true, height: 22),
          ],
        ],
      );
    }

    return Semantics(
      button: true,
      label: spoken,
      hint: 'Sevkiyatı açar',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            AknHaptics.selection();
            widget.onTap();
          },
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onHighlightChanged: (v) {
            if (v != _pressed) setState(() => _pressed = v);
          },
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedContainer(
              duration: AknMotion.of(
                context,
                _pressed ? AknMotion.press : AknMotion.pressOut,
              ),
              color: _pressed ? c.surfaceAlt : Colors.transparent,
              padding: widget.padding,
              constraints: const BoxConstraints(minHeight: 64),
              child: content(large || constraints.maxWidth < 340),
            ),
          ),
        ),
      ),
    );
  }
}

/// Şirket içi talepler: onaylayan için "Onayınızı bekleyen talepler", talep eden için "Taleplerim".
/// Satırlar `customers/me/order-requests` ucundan gelir; gelmezse (eski sunucu, hata) bekleyen
/// sayısıyla tek bir satır gösterilir.
class CompanyRequestsSection extends ConsumerWidget {
  const CompanyRequestsSection({
    super.key,
    required this.approver,
    this.waiting = 0,
    this.headerTop = 24,
    this.boxTop,
  });

  /// Doluysa bölüm [HomeSectionBox] içinde, üstünde bu kadar boşlukla çizilir (boşken kutu da yok).
  final double? boxTop;

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  /// true: onaylayan / yönetici (bekleyenler); false: talep eden (kendi talepleri).
  final bool approver;

  /// Ana sayfa verisindeki bekleyen sayısı (yedek satır için).
  final int waiting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeOrderRequestsProvider(approver)).valueOrNull;
    final items = data?.items ?? const <OrderRequest>[];
    if (!approver && items.isEmpty) return const SizedBox.shrink();
    final total = data?.total ?? waiting;
    if (approver && total <= 0) return const SizedBox.shrink();
    final allRoute = approver ? AppRoutes.approvals : AppRoutes.companyRequests;
    final action = total > items.length || !approver;
    final rows = <Widget>[
      if (items.isEmpty)
        AknListTile(
          padding: homeFirstRow(action: action),
          leading: const _Tile(
            icon: PhosphorIconsRegular.userCircleCheck,
            tone: AknTone.brand,
          ),
          titleStyle: _rowTitle(context),
          title: HomeCopy.approvalsWaiting(total),
          status: AknLamp.status(
            AknStatus.companyRequestLamp(
              CustomerOrderRequestStatus.pending,
              const StatusViewer.customer(),
            ),
          ),
          showChevron: true,
          semanticLabel: HomeCopy.approvalsWaiting(total),
          onTap: () => context.push(AppRoutes.approvals),
        )
      else
        for (final (i, r) in items.indexed)
          _RequestRow(
            padding: i == 0
                ? homeFirstRow(action: action)
                : const EdgeInsets.symmetric(horizontal: _gutter, vertical: 12),
            request: r,
            approver: approver,
            onTap: () => context.push(
              approver ? AppRoutes.approvals : AppRoutes.companyRequest(r.id),
            ),
          ),
    ];
    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: approver ? HomeCopy.companyApprovals : HomeCopy.myRequests,
          count: total,
          actionLabel: action ? HomeCopy.all : null,
          onAction: () => context.push(allRoute),
        ),
        AknLedger(children: rows),
      ],
    );
    final box = boxTop;
    return box == null ? section : HomeSectionBox(top: box, child: section);
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.approver,
    required this.onTap,
    this.padding,
  });

  final EdgeInsets? padding;
  final OrderRequest request;
  final bool approver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final r = request;
    final points = <String>{
      for (final l in r.lines)
        if (l.deliveryPointName.trim().isNotEmpty) l.deliveryPointName.trim(),
    }.toList();
    final place = points.isEmpty
        ? null
        : points.length == 1
        ? points.first
        : '${points.first} ve ${points.length - 1} nokta';
    final subtitle = [
      ?place,
      if (r.createdAt != null) Fmt.relative(r.createdAt),
    ].join(', ');
    final lamp = AknStatus.companyRequestLamp(
      r.status,
      StatusViewer.customer(canDecide: approver && r.canDecide),
      serverLabel: r.statusLabel,
    );
    final who = approver && r.requestedByName.trim().isNotEmpty
        ? '${r.requestedByName.trim()} talep etti'
        : null;
    final title = '${r.productsSummary}, ${Fmt.liters(r.totalLiters)}';
    final amount = r.estimatedAmount == null
        ? null
        : Fmt.money(r.estimatedAmount);
    final meta = r.estimatedAmount == null ? null : 'tahmini';
    final status = AknStatusLine(
      lamp: AknLamp.status(lamp),
      trailing: who == null
          ? null
          : Text(who, style: t.bodySmall.copyWith(color: c.dim)),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final pad = (padding ?? AknSpace.row).horizontal;
        final beside = _amountBeside(
          context,
          width: box.maxWidth - pad - 56,
          title: title,
          amount: amount,
          meta: meta,
        );
        return AknListTile(
          padding: padding,
          leading: _Tile(
            icon: PhosphorIconsRegular.clipboardText,
            tone: lamp.tone,
          ),
          titleStyle: _rowTitle(context),
          title: _wrapSafeTitle(context, title, box.maxWidth - pad - 56),
          subtitle: subtitle.isEmpty ? r.number : subtitle,
          amount: beside ? amount : null,
          amountMeta: beside ? meta : null,
          status: beside || amount == null
              ? status
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AmountLine(amount: amount, meta: meta),
                    const SizedBox(height: 8),
                    status,
                  ],
                ),
          semanticLabel: [
            r.number,
            title,
            if (subtitle.isNotEmpty) subtitle,
            if (r.estimatedAmount != null)
              'tahmini ${Fmt.money(r.estimatedAmount)}',
            lamp.label,
            ?who,
          ].join(', '),
          onTap: () {
            AknHaptics.selection();
            onTap();
          },
        );
      },
    );
  }
}

/// Limitler (ilk 2; "Tümü" → Limitlerim).
class LimitsSection extends StatelessWidget {
  const LimitsSection({super.key, required this.limits, this.headerTop = 24});

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final List<CustomerLimit> limits;

  @override
  Widget build(BuildContext context) {
    final withLimit = limits.where((l) => l.hasLimit).toList()
      ..sort((a, b) => b.usedPct.compareTo(a.usedPct));
    final shown = (withLimit.isEmpty ? limits : withLimit).take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          top: headerTop,
          title: HomeCopy.limits,
          actionLabel: HomeCopy.all,
          onAction: () => context.push(limitsRoute),
        ),
        AknLedger(
          children: [
            for (final (i, l) in shown.indexed)
              LimitMeter(
                limit: l,
                compact: true,
                padding: i == 0
                    ? homeFirstRow(action: true)
                    : const EdgeInsets.symmetric(
                        horizontal: _gutter,
                        vertical: 12,
                      ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Son kullanılan 3 şablon (tek dokunuşla sihirbaz).
class TemplatesSection extends StatelessWidget {
  const TemplatesSection({
    super.key,
    required this.templates,
    this.headerTop = 24,
  });

  /// Başlığın üstündeki boşluk (plakadan sonraki ilk bölümde 16).
  final double headerTop;

  final List<TemplateListItem> templates;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HomeSectionHeader(
        top: headerTop,
        title: HomeCopy.templates,
        actionLabel: HomeCopy.all,
        onAction: () => context.push(templatesRoute),
      ),
      AknLedger(
        children: [
          for (final (i, tpl) in templates.take(3).indexed)
            AknListTile(
              padding: i == 0
                  ? homeFirstRow(action: true)
                  : const EdgeInsets.symmetric(
                      horizontal: _gutter,
                      vertical: 12,
                    ),
              leading: const _Tile(
                icon: PhosphorIconsRegular.bookmarkSimple,
                tone: AknTone.brand,
              ),
              titleStyle: _rowTitle(context),
              title: tpl.name,
              subtitle: tpl.subtitle.replaceAll(' · ', ', '),
              showChevron: true,
              semanticLabel: '${tpl.name} şablonuyla sipariş ver',
              onTap: () {
                AknHaptics.selection();
                context.push('${AppRoutes.orderNew}?fromTemplate=${tpl.id}');
              },
            ),
        ],
      ),
    ],
  );
}

/// Harcama eğrisi (yönetici destesi ve ay plakası yokken; dokununca Harcamalar).
class SpendingSection extends StatelessWidget {
  const SpendingSection({super.key, required this.months});

  final List<SpendingMonth> months;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final last = months.last;
    final values = [for (final m in months) m.amount];
    final label = [
      for (final m in months)
        '${m.shortLabel ?? Fmt.monthShort[(m.month - 1).clamp(0, 11)]}: ${Fmt.moneyWhole(m.amount)}',
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: HomeCopy.spending,
          actionLabel: 'Rapor',
          onAction: () => context.push(AppRoutes.spending),
        ),
        Semantics(
          label: '${HomeCopy.spending}. $label',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AmountText(Fmt.moneyCompact(last.amount), large: true),
                Text(
                  '${last.shortLabel ?? Fmt.monthNames[(last.month - 1).clamp(0, 11)]}, ${Fmt.liters(last.liters)}',
                  style: t.bodySmall.copyWith(color: c.dim),
                ),
                const SizedBox(height: 8),
                Sparkline(values: values, height: 44, semanticLabel: null),
                const SizedBox(height: 4),
                Text(
                  HomeCopy.spendingCaption,
                  style: t.caption.copyWith(color: c.dim),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Asistana sorun" (kapatılabilir; /assistant'a gider; A8 koduna bağımlı değil): küçük logo
/// karosu, başlık ve bir cümle; sağda kapat.
class AssistantCard extends StatelessWidget {
  const AssistantCard({
    super.key,
    required this.onOpen,
    required this.onDismiss,
    this.top = 16,
  });

  final VoidCallback onOpen;
  final Future<void> Function() onDismiss;

  /// Kartın üstündeki boşluk.
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '${HomeCopy.assistantTitle}. ${HomeCopy.assistantMessage}',
              excludeSemantics: true,
              onTap: onOpen,
              child: InkWell(
                onTap: onOpen,
                splashFactory: NoSplash.splashFactory,
                highlightColor: c.surfaceAlt,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(_gutter, 12, 4, 12),
                  child: Row(
                    children: [
                      const _Tile(
                        tone: AknTone.brand,
                        child: LogoMark(size: 24, semanticLabel: null),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              HomeCopy.assistantTitle,
                              style: _rowTitle(context),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              HomeCopy.assistantMessage,
                              style: t.bodySmall.copyWith(color: c.dim),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 8),
            child: AknIconButton(
              icon: PhosphorIconsRegular.x,
              semanticLabel: 'Asistan kartını kapat',
              color: c.dim,
              size: 20,
              onPressed: () => unawaited(onDismiss()),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Bayiniz": varsayılan bayinin adı ve iletişim düğmeleri (sayfanın sonunda).
class StationSection extends StatelessWidget {
  const StationSection({super.key, required this.station, this.headerTop = 20});

  final StationContact station;

  /// Başlığın üstündeki boşluk.
  final double headerTop;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(title: HomeCopy.station, top: headerTop),
        Padding(
          padding: const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _Tile(icon: PhosphorIconsRegular.storefront),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(station.title, style: _rowTitle(context)),
                        if (station.city != null)
                          Text(
                            station.city!,
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              StationContactButtons(station: station, dense: true),
            ],
          ),
        ),
      ],
    );
  }
}
