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

/// Adım 2: teslimat noktası (pencere, tank, erişim notları; tank aşımı uyarısı), teslim tarihi
/// (önerilen; en erken tarihten önce olamaz), satır bazında farklı nokta / tarih.
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
                  child: Text('Teslimat noktası', style: t.headline),
                ),
              ),
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
                for (final p in points)
                  _PointCard(
                    point: p,
                    selected: d.pointId == p.id,
                    lastUsed: p.id == lastPoint,
                    liters: d.litersByPoint()[p.id],
                    onTap: () => ctrl.setPoint(p.id),
                  ),
              if (errorFor('point') != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    errorFor('point')!,
                    style: t.bodySmall.copyWith(color: c.danger.fg),
                  ),
                ),
              for (final warning in tank)
                AknBanner(
                  tone: AknTone.warn,
                  icon: Icons.propane_tank_rounded,
                  title: 'Tank kapasitesi aşılıyor',
                  message: warning.message,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: DateField(
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
                  child: Semantics(
                    header: true,
                    child: Text('Satır bazında', style: t.headline),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
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

class _PointCard extends StatelessWidget {
  const _PointCard({
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
      if (p.windowLabel != null) 'Pencere ${p.windowLabel}',
      if (p.tankCapacityLiters != null)
        'Tank ${Fmt.liters(p.tankCapacityLiters)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoiceCard(
            title: p.name,
            subtitle: [
              if (p.fullAddress.isNotEmpty) p.fullAddress,
              if (facts.isNotEmpty) facts,
            ].join('\n'),
            leadingIcon: Icons.place_rounded,
            tag: lastUsed ? 'Son kullanılan' : null,
            selected: selected,
            onTap: onTap,
          ),
          SafeAnimatedSize(
            child: !selected || (p.accessNotes == null && p.contactName == null)
                ? const SizedBox(width: double.infinity)
                : Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: AknRadius.card,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (p.accessNotes != null)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: c.dim,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Erişim: ${p.accessNotes}',
                                  style: t.bodySmall.copyWith(color: c.text),
                                ),
                              ),
                            ],
                          ),
                        if (p.contactName != null) ...[
                          if (p.accessNotes != null) const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 16,
                                color: c.dim,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${p.contactName}${p.contactPhone == null ? '' : ' · ${Fmt.phone(p.contactPhone)}'}',
                                  style: t.bodySmall.copyWith(color: c.text),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AknCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: l.custom,
              title: Text(
                'Satır ${index + 1}: $product · ${Fmt.liters(l.liters ?? 0)}',
                style: t.bodyStrong,
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
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error!,
                  style: t.bodySmall.copyWith(color: c.danger.fg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
