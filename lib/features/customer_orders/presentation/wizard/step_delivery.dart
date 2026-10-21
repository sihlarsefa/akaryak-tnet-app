import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
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

/// Adım 2 (tasarım v2 §7.9 "Teslimat"): teslimat noktası satırları (seçim halkası, ad + adres,
/// teslim saatleri ve tank; seçilince erişim notları), teslim tarihi (hızlı seçimlerle; en erken
/// tarihten önce olamaz), tank aşımı uyarısı ve satır bazında farklı nokta / tarih.
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

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WizardHeading('Teslimat noktası'),
              if (points.isEmpty)
                EmptyState(
                  title: 'Teslimat noktanız yok',
                  message:
                      'Sipariş verebilmek için önce bir teslimat noktası ekleyin.',
                  illustration: AknIllustration.delivery,
                  compact: true,
                  actionLabel: 'Teslimat noktası ekle',
                  onAction: () => context.push(AppRoutes.deliveryPoints),
                )
              else
                AknLedger(
                  children: [
                    for (final p in points)
                      _PointRow(
                        point: p,
                        selected: d.pointId == p.id,
                        lastUsed: p.id == lastPoint,
                        liters: byPoint[p.id],
                        onTap: () => ctrl.setPoint(p.id),
                      ),
                  ],
                ),
              if (errorFor('point') != null) WizardError(errorFor('point')!),
              for (final warning in tank)
                WizardPad(
                  AknBanner(
                    tone: AknTone.warn,
                    icon: Icons.propane_tank_outlined,
                    title: 'Tank kapasitesi aşılıyor',
                    message: warning.message,
                  ),
                ),
              const WizardHeading('Teslim günü', top: 24),
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
              if (d.lines.length > 1) ...[
                const WizardHeading('Satır bazında', top: 24),
                WizardPad(
                  top: 0,
                  Text(
                    'Bir satır başka noktaya ya da başka güne gidecekse “Farklı nokta/tarih”i açın.',
                    style: t.bodySmall.copyWith(color: c.dim),
                  ),
                ),
                for (var i = 0; i < d.lines.length; i++)
                  _LineOverride(
                    index: i,
                    lineUid: d.lines[i].uid,
                    points: points,
                    minDate: min,
                    error: errorFor(d.lines[i].uid),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Teslimat noktası satırı: seçim halkası, ad (17/22 600) ve "Son kullanılan", adres, teslim
/// saatleri ve tank; seçiliyken erişim notu ve yetkili kişi bir Beton kuyuda.
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
    final t = context.aknText;
    final c = context.akn;
    final p = point;
    final facts = [
      if (p.windowLabel != null) 'Teslim saatleri ${p.windowLabel}',
      if (p.tankCapacityLiters != null)
        'tank ${Fmt.liters(p.tankCapacityLiters)}',
    ].join(', ');
    final notes = selected && (p.accessNotes != null || p.contactName != null);
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
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            AknHaptics.selection();
            onTap();
          },
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceAlt,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: AknSpace.row,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: _Radio(selected: selected),
                  ),
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
                              style: t.headline.copyWith(color: c.ink),
                            ),
                            if (lastUsed)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: c.surfaceAlt,
                                  borderRadius: AknRadius.tag,
                                ),
                                child: Text(
                                  'Son kullanılan',
                                  style: t.captionStrong.copyWith(color: c.ink),
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
                              : Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(top: 10),
                                  padding: AknSpace.well,
                                  decoration: BoxDecoration(
                                    color: c.surfaceAlt,
                                    borderRadius: AknRadius.card,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (p.accessNotes != null)
                                        _NoteLine(
                                          icon: Icons.door_front_door_outlined,
                                          text: 'Erişim: ${p.accessNotes}',
                                        ),
                                      if (p.contactName != null) ...[
                                        if (p.accessNotes != null)
                                          const SizedBox(height: 6),
                                        _NoteLine(
                                          icon: Icons.person_outline_rounded,
                                          text:
                                              '${p.contactName}${p.contactPhone == null ? '' : ', ${Fmt.phone(p.contactPhone)}'}',
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
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

/// Seçim halkası (§6.11): seçiliyken mürekkep dolgu ve beyaz nokta; değilse 1,6 px kontrol
/// çizgisi.
class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return AnimatedContainer(
      duration: AknMotion.of(context, AknMotion.fast),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.ink : Colors.transparent,
        border: Border.all(
          color: selected ? c.ink : c.lineStrong,
          width: selected ? 2 : 1.6,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.bg),
            )
          : null,
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
