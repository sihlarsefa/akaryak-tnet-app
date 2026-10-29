import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/routing/app_location.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/storage/prefs_store.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/home_controller.dart';
import '../../application/loadable.dart';
import '../../application/wizard_controller.dart';
import '../../application/wizard_rules.dart';
import '../../data/form_models.dart';
import '../widgets/common.dart';
import 'wizard_parts.dart';

/// Adım 2 (tasarım v3 "Teslimat"): teslimat noktası seçim kartları (konum karosu, ad + adres,
/// teslim saatleri ve tank; seçilince turuncu ışık, onay işareti ve açılan erişim notları), teslim
/// tarihi (hızlı seçimlerle; en erken tarihten önce olamaz), tank aşımı uyarısı ve satır bazında
/// farklı nokta / tarih. Adım açılınca kartlar birbiri ardına yükselerek gelir.
class StepDelivery extends ConsumerWidget {
  const StepDelivery({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(orderWizardProvider);
    final ctrl = ref.read(orderWizardProvider.notifier);
    final form = ref.watch(orderFormProvider).data;
    final t = context.aknText;
    final c = context.akn;
    final d = w.draft;
    final points = form?.deliveryPoints ?? const <DeliveryPointOption>[];
    final issues = w.showErrors
        ? WizardRules.delivery(d, form: form, minDate: ctrl.minDate)
        : const <RuleIssue>[];
    String? errorFor(String f) =>
        issues.where((i) => i.field == f).firstOrNull?.message;
    final tank = WizardRules.tankWarnings(d, form);
    final uid = ref.watch(currentUserIdProvider);
    int? lastPoint;
    try {
      lastPoint = uid == null
          ? null
          : ref.read(prefsStoreProvider).getInt(A2Keys.lastPoint(uid));
    } catch (_) {
      lastPoint = null;
    }
    final min = ctrl.minDate;
    final byPoint = d.litersByPoint();
    // Bölümler ve nokta kartları birbiri ardına yükselerek gelir (v3 §5).
    final enter = WizardCascade();

    return WizardStepList(
      children: [
        enter('points-heading', const WizardHeading('Teslimat noktası')),
        if (points.isEmpty)
          enter(
            'no-points',
            EmptyState(
              title: 'Teslimat noktanız yok',
              message:
                  'Sipariş verebilmek için önce bir teslimat noktası ekleyin.',
              illustration: AknIllustration.delivery,
              compact: true,
              actionLabel: 'Teslimat noktası ekle',
              // Teslimat noktaları bazı düzenlerde alt menü sekmesidir (QA SC-01).
              onAction: () => context.openAppLocation(AppRoutes.deliveryPoints),
            ),
          )
        else
          for (final p in points)
            enter(
              'point-${p.id}',
              _PointRow(
                point: p,
                selected: d.pointId == p.id,
                lastUsed: p.id == lastPoint,
                liters: byPoint[p.id],
                onTap: () => ctrl.setPoint(p.id),
              ),
            ),
        if (errorFor('point') != null) WizardError(errorFor('point')!),
        for (final (i, warning) in tank.indexed)
          enter(
            'tank-$i',
            WizardPad(
              AknBanner(
                tone: AknTone.warn,
                icon: PhosphorIconsRegular.cylinder,
                title: 'Tank kapasitesi aşılıyor',
                message: warning.message,
              ),
            ),
          ),
        enter('date-heading', const WizardHeading('Teslim günü', top: 24)),
        enter(
          'date',
          WizardPad(
            top: 0,
            DateField(
              label: 'Teslim tarihi',
              value: d.date,
              firstDate: min,
              lastDate: TrTime.addDays(TrTime.todayStart(), 120),
              requiredMark: true,
              helper: TrTime.isSameDay(min, TrTime.todayStart())
                  ? 'Bayi teslim planına göre değişebilir.'
                  : 'En erken ${Fmt.date(min)} (bayinin teslim süresi).',
              errorText: errorFor('date'),
              onChanged: ctrl.setDate,
            ),
          ),
        ),
        if (d.lines.length > 1) ...[
          enter('lines-heading', const WizardHeading('Satır bazında', top: 24)),
          enter(
            'lines-hint',
            WizardPad(
              top: 0,
              Text(
                'Bir satır başka noktaya ya da başka güne gidecekse “Farklı nokta/tarih”i açın.',
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ),
          ),
          for (var i = 0; i < d.lines.length; i++)
            enter(
              'line-${d.lines[i].uid}',
              _LineOverride(
                index: i,
                lineUid: d.lines[i].uid,
                points: points,
                minDate: min,
                error: errorFor(d.lines[i].uid),
              ),
            ),
        ],
      ],
    );
  }
}

/// Teslimat noktası kartı (tasarım v3 §4, sihirbazın diğer seçim kartlarıyla — [ChoiceCard] — aynı
/// dil): beyaz r20 kart, başta 40 px konum karosu, ad ve "Son kullanılan" etiketi, adres, teslim
/// saatleri ve tank; sağ üstte seçim işareti. Seçilince kartın üstüne yumuşak turuncu bir ışık
/// yayılır, 2 px turuncu çerçeve gelir, karo beyaza dönüp turuncu simgeyle hafifçe yükselir ve
/// dolu onay işareti yayla belirir; erişim notu ve yetkili kişi sessiz bir kuyuda açılır. Basınca
/// kart 0,98'e iner. Renk tek başına anlam taşımaz (işaret + ekran okuyucuda "seçili").
class _PointRow extends StatelessWidget {
  const _PointRow({
    required this.point,
    required this.selected,
    required this.lastUsed,
    required this.onTap,
    this.liters,
  });

  final DeliveryPointOption point;
  final bool selected;
  final bool lastUsed;
  final double? liters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = point;
    final facts = [
      if (p.windowLabel != null) 'Teslim saatleri ${p.windowLabel}',
      if (p.tankCapacityLiters != null)
        'tank ${Fmt.liters(p.tankCapacityLiters)}',
    ].join(', ');
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: [
        p.name,
        if (lastUsed) 'son kullanılan',
        if (p.fullAddress.isNotEmpty) p.fullAddress,
        if (facts.isNotEmpty) facts,
      ].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: PressScale(
          scale: 0.98,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: selected ? 1 : 0),
            duration: AknMotion.of(context, const Duration(milliseconds: 280)),
            curve: AknMotion.standard,
            builder: (context, s, _) => _PointBody(
              row: this,
              // Sayı birimiyle aynı satırda kalır ("tank 30.000 L").
              facts: keepUnits(facts),
              progress: s,
            ),
          ),
        ),
      ),
    );
  }
}

/// Nokta kartının seçim ilerlemesindeki ([progress] 0 durgun → 1 seçili) görünümü.
class _PointBody extends StatelessWidget {
  const _PointBody({
    required this.row,
    required this.facts,
    required this.progress,
  });

  final _PointRow row;
  final String facts;
  final double progress;

  static Color _mix(Color a, Color b, double t) =>
      t <= 0 ? a : (t >= 1 ? b : Color.lerp(a, b, t)!);

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final p = row.point;
    final s = progress.clamp(0.0, 1.0);
    final selected = row.selected;
    final notes = selected && (p.accessNotes != null || p.contactName != null);
    // Yumuşak turuncu ışık: üst köşede brandSoft, karta doğru söner.
    final wash = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _mix(c.surface, c.brandSoft, s),
        _mix(c.surface, Color.lerp(c.brandSoft, c.surface, 0.45)!, s),
      ],
    );
    final restBorder = c.isDark ? c.line : c.surface.withValues(alpha: 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: wash,
        borderRadius: AknRadius.card,
        border: Border.fromBorderSide(
          BorderSide(
            color: _mix(restBorder, c.brand, s),
            width: c.isDark ? 1 + s : 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        boxShadow: c.isDark ? null : AknShadows.card(c),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AknRadius.card,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.ink.withValues(alpha: 0.04),
          onTap: () {
            if (!selected) AknHaptics.selection();
            row.onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PinTile(progress: s),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              p.name,
                              style: t.headline.copyWith(
                                fontSize: 16,
                                height: 22 / 16,
                                color: c.ink,
                              ),
                            ),
                            if (row.lastUsed)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _mix(c.surfaceAlt, c.surface, s),
                                  borderRadius: AknRadius.tag,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    'Son kullanılan',
                                    style: t.captionStrong.copyWith(
                                      color: _mix(c.ink, c.brandInk, s),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (p.fullAddress.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            p.fullAddress,
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ],
                        if (facts.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            facts,
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ],
                        SafeAnimatedSize(
                          child: !notes
                              ? const SizedBox(width: double.infinity)
                              : FadeUp(
                                  offset: 6,
                                  child: Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 10),
                                    padding: AknSpace.well,
                                    decoration: BoxDecoration(
                                      color: c.isDark
                                          ? c.surfaceAlt
                                          : c.surface.withValues(alpha: 0.72),
                                      borderRadius: AknRadius.card,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (p.accessNotes != null)
                                          _NoteLine(
                                            icon: PhosphorIconsRegular.door,
                                            text: 'Erişim: ${p.accessNotes}',
                                          ),
                                        if (p.contactName != null) ...[
                                          if (p.accessNotes != null)
                                            const SizedBox(height: 6),
                                          _NoteLine(
                                            icon: PhosphorIconsRegular.user,
                                            text:
                                                '${p.contactName}${p.contactPhone == null ? '' : ', ${Fmt.phone(p.contactPhone)}'}',
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CheckMark(selected: selected),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 40 px konum karosu: durgunken sessiz kuyu ve mürekkep iğne; seçilince beyaza (koyu temada
/// kart rengine) döner, iğne turuncu dolar ve karo hafifçe yükselir.
class _PinTile extends StatelessWidget {
  const _PinTile({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final s = progress;
    return ExcludeSemantics(
      child: Transform.scale(
        scale: 1 + 0.04 * s,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.lerp(c.surfaceAlt, c.isDark ? c.surface : c.plate, s),
            borderRadius: const BorderRadius.all(Radius.circular(AknRadius.sm)),
            boxShadow: s > 0 && !c.isDark
                ? [
                    BoxShadow(
                      color: c.plateAccent.withValues(alpha: 0.16 * s),
                      offset: Offset(0, 3 * s),
                      blurRadius: 8 * s,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          // Seçilince iğne çizgiden doluya geçer.
          child: AnimatedSwitcher(
            duration: AknMotion.of(context, AknMotion.iconSwap),
            switchInCurve: AknMotion.pop,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: a, child: child),
            ),
            child: s >= 0.5
                ? Icon(
                    PhosphorIconsFill.mapPin,
                    key: const ValueKey('on'),
                    size: 22,
                    color: c.plateAccent,
                  )
                : Icon(
                    PhosphorIconsRegular.mapPin,
                    key: const ValueKey('off'),
                    size: 22,
                    color: c.ink,
                  ),
          ),
        ),
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: c.dim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: t.bodySmall.copyWith(color: c.ink)),
        ),
      ],
    );
  }
}

/// Sağ üstteki seçim işareti (tasarım v3 §5 seçim): seçilince dolu turuncu onay yayla büyüyerek
/// belirir; değilse 1,5 px kontrol çizgili boş halka.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: SizedBox.square(
        dimension: 22,
        child: AnimatedSwitcher(
          duration: AknMotion.of(context, const Duration(milliseconds: 320)),
          reverseDuration: AknMotion.of(context, AknMotion.fast),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a.drive(CurveTween(curve: Curves.easeOut)),
            child: ScaleTransition(
              scale: a.drive(
                Tween<double>(
                  begin: 0.3,
                  end: 1,
                ).chain(CurveTween(curve: AknMotion.pop)),
              ),
              child: child,
            ),
          ),
          child: selected
              ? Icon(
                  PhosphorIconsFill.checkCircle,
                  key: const ValueKey('on'),
                  size: 22,
                  color: c.brandFill,
                )
              : Container(
                  key: const ValueKey('off'),
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.lineStrong, width: 1.5),
                  ),
                ),
        ),
      ),
    );
  }
}

class _LineOverride extends ConsumerWidget {
  const _LineOverride({
    required this.index,
    required this.lineUid,
    required this.points,
    required this.minDate,
    this.error,
  });

  final int index;
  final String lineUid;
  final List<DeliveryPointOption> points;
  final DateTime minDate;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(orderWizardProvider);
    final ctrl = ref.read(orderWizardProvider.notifier);
    final form = ref.watch(orderFormProvider).data;
    final t = context.aknText;
    final c = context.akn;
    final d = w.draft;
    final l = d.lines.firstWhere((x) => x.uid == lineUid);
    final product = form?.product(l.productId)?.name ?? 'Ürün seçilmedi';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: AknCard(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: l.custom,
              title: Text(
                'Satır ${index + 1}: $product, ${Fmt.liters(l.liters ?? 0)}',
                style: t.bodyStrong.copyWith(color: c.ink),
              ),
              subtitle: Text(
                l.custom
                    ? 'Bu satır kendi noktası ve tarihiyle gider.'
                    : 'Ana noktaya, ana tarihte gider.',
                style: t.bodySmall.copyWith(color: c.dim),
              ),
              onChanged: (v) => ctrl.setLineCustom(lineUid, v),
            ),
            if (l.custom) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DropdownButtonFormField<int>(
                  initialValue: d.pointOf(l),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Teslimat noktası',
                  ),
                  items: [
                    for (final p in points)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) ctrl.setLinePoint(lineUid, v);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DateField(
                  label: 'Satırın teslim tarihi',
                  value: d.dateOf(l),
                  firstDate: minDate,
                  lastDate: TrTime.addDays(TrTime.todayStart(), 120),
                  quickPicks: false,
                  onChanged: (v) => ctrl.setLineDate(lineUid, v),
                ),
              ),
            ],
            if (error != null)
              WizardError(error!, padding: const EdgeInsets.only(right: 8)),
          ],
        ),
      ),
    );
  }
}
