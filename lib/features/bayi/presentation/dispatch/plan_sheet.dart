import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../../../core/utils/validators.dart';
import '../../application/bayi_actions.dart';
import '../../application/bayi_runtime.dart';
import '../../application/dispatch_controller.dart';
import '../../data/bayi_json.dart';
import '../../data/bayi_repository.dart';
import '../../data/dispatch_models.dart';
import '../widgets/bayi_widgets.dart';
import 'driver_picker.dart';

/// Planlanacak sipariş (pano satırı ya da sipariş ayrıntısı).
@immutable
class PlanTarget {
  const PlanTarget({
    required this.orderId,
    required this.orderNumber,
    required this.remainingLiters,
    this.customerTitle,
    this.productName,
    this.deliveryDate,
    this.deliveryPointName,
    this.windowStart,
    this.windowEnd,
    this.tankCapacityLiters,
  });

  factory PlanTarget.fromBoard(BoardOrder o) => PlanTarget(
    orderId: o.orderId,
    orderNumber: o.orderNumber,
    remainingLiters: o.remainingLiters,
    customerTitle: o.customerTitle,
    productName: o.productName,
    deliveryDate: o.deliveryDate,
    deliveryPointName: o.deliveryPointName,
    windowStart: o.windowStart,
    windowEnd: o.windowEnd,
    tankCapacityLiters: o.tankCapacityLiters,
  );

  final int orderId;
  final String orderNumber;
  final double remainingLiters;
  final String? customerTitle;
  final String? productName;
  final DateTime? deliveryDate;
  final String? deliveryPointName;
  final String? windowStart;
  final String? windowEnd;
  final double? tankCapacityLiters;
}

/// Sevkiyat planla (spec A.3 adım 5): litre ≤ kalan, plaka (PlateBadge önizlemeli), şoför seçimi
/// (telefon, "uygulamada" rozeti), plan zamanı. Planlanırsa true döner.
Future<bool> showPlanSheet(BuildContext context, PlanTarget target) async {
  final r = await showAppSheet<bool>(
    context: context,
    title: 'Sevkiyat planla',
    subtitle: [target.orderNumber, ?target.customerTitle].join(' · '),
    builder: (_) => _PlanSheet(target: target),
  );
  return r ?? false;
}

class _PlanSheet extends ConsumerStatefulWidget {
  const _PlanSheet({required this.target});

  final PlanTarget target;

  @override
  ConsumerState<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _liters = TextEditingController(
    text: Fmt.number(widget.target.remainingLiters, maxFraction: 3),
  );
  final TextEditingController _plate = TextEditingController();
  DriverChoice? _driver;
  late DateTime _at = defaultScheduleFor(widget.target.deliveryDate);
  bool _checking = false;
  bool _busy = false;
  String? _driverError;

  PlanTarget get _t => widget.target;

  @override
  void dispose() {
    _liters.dispose();
    _plate.dispose();
    super.dispose();
  }

  double? get _litersValue => MoneyField.parse(_liters.text);

  Future<void> _pickDriver() async {
    final c = await showDriverPicker(context, selected: _driver);
    if (c != null && mounted) {
      setState(() {
        _driver = c;
        _driverError = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final w = TrTime.wall(_at);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: w.hour, minute: w.minute),
      helpText: 'Plan saati',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (picked != null && mounted) {
      setState(() {
        _at = TrTime.fromWall(
          w.year,
          w.month,
          w.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _setDay(DateTime day) {
    final w = TrTime.wall(_at);
    final d = TrTime.wall(day);
    setState(
      () => _at = TrTime.fromWall(d.year, d.month, d.day, w.hour, w.minute),
    );
  }

  void _applyPlate(BoardSuggestion s) {
    _plate.text = Fmt.plate(s.value);
    final pair = s.pair;
    if (_driver == null && pair != null && pair.isNotEmpty) {
      final drivers = ref.read(stationDriversProvider).valueOrNull ?? const [];
      final match = drivers.where(
        // Ad eşleşmesi Türkçe kültürle (sunucu ile aynı).
        (d) => TurkishText.lower(d.displayName) == TurkishText.lower(pair),
      );
      _driver = match.isNotEmpty
          ? DriverChoice.account(match.first)
          : DriverChoice.manual(pair);
    }
    setState(() {});
  }

  String? get _windowWarning {
    final start = _t.windowStart;
    final end = _t.windowEnd;
    if (start == null && end == null) return null;
    final w = TrTime.wall(_at);
    final hhmm =
        '${w.hour.toString().padLeft(2, '0')}:${w.minute.toString().padLeft(2, '0')}';
    final early = start != null && hhmm.compareTo(start) < 0;
    final late = end != null && end != '24:00' && hhmm.compareTo(end) > 0;
    if (!early && !late) return null;
    return 'Plan saati teslim penceresinin (${BayiJson.windowLabel(start, end)}) dışında.';
  }

  String? get _tankWarning {
    final tank = _t.tankCapacityLiters;
    final l = _litersValue;
    if (tank == null || l == null || l <= tank) return null;
    return 'Planlanan litre tank kapasitesini (${Fmt.liters(tank)}) aşıyor.';
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ok = _form.currentState?.validate() ?? false;
    if (_driver == null) setState(() => _driverError = 'Şoför seçin.');
    if (!ok || _driver == null) return;
    if (_at.isBefore(TrTime.todayStart())) {
      AppToast.error('Plan zamanı bugünden önce olamaz.', context: context);
      return;
    }
    final d = _driver!;
    final draft = PlanShipmentDraft(
      orderId: _t.orderId,
      plannedLiters: _litersValue!,
      vehiclePlate: Fmt.plate(_plate.text),
      driverName: d.displayName,
      driverUserId: d.account?.userId,
      scheduledAt: _at,
    );
    setState(() => _busy = true);
    try {
      final outcome = await ref
          .read(bayiActionsProvider)
          .planShipment(
            draft,
            onChecking: () {
              if (mounted) setState(() => _checking = true);
            },
          );
      if (!mounted) return;
      AppToast.success(
        outcome == BayiOutcome.reconciled
            ? 'Sevkiyat planı doğrulandı.'
            : 'Sevkiyat planlandı.',
        context: context,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showActionFailure(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _checking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final online = ref.watch(isOnlineProvider);
    final suggestions = ref.watch(boardSuggestionsProvider).valueOrNull;
    final today = TrTime.todayStart();
    final windowLabel = BayiJson.windowLabel(_t.windowStart, _t.windowEnd);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AknCard(
            color: c.surfaceAlt,
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    ?_t.productName,
                    'Kalan ${Fmt.liters(_t.remainingLiters)}',
                  ].join(' · '),
                  style: t.bodyStrong,
                ),
                if (_t.deliveryPointName != null) ...[
                  const SizedBox(height: 2),
                  Text(_t.deliveryPointName!, style: t.bodySmall),
                ],
                if (windowLabel != null || _t.tankCapacityLiters != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (windowLabel != null) 'Teslim penceresi $windowLabel',
                      if (_t.tankCapacityLiters != null)
                        'Tank ${Fmt.liters(_t.tankCapacityLiters)}',
                    ].join(' · '),
                    style: t.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          LitersField(
            label: 'Planlanan litre',
            controller: _liters,
            max: _t.remainingLiters,
            requiredValue: true,
            validator: (v) =>
                Validators.positiveNumber(v, max: _t.remainingLiters),
            onChanged: (_) => setState(() {}),
          ),
          if (_tankWarning != null) ...[
            const SizedBox(height: 8),
            AknBanner(tone: AknTone.warn, message: _tankWarning!),
          ],
          const SizedBox(height: 12),
          PlateField(controller: _plate, label: 'Araç plakası'),
          if (suggestions != null && suggestions.plates.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Son kullanılanlar', style: t.caption),
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              children: [
                for (final s in suggestions.plates.take(6))
                  ActionChip(
                    avatar: const Icon(Icons.local_shipping_outlined, size: 16),
                    label: Text(Fmt.plate(s.value)),
                    tooltip: s.pair == null ? null : 'Son şoför: ${s.pair}',
                    onPressed: () => _applyPlate(s),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _DriverField(
            choice: _driver,
            error: _driverError,
            onTap: _pickDriver,
          ),
          const SizedBox(height: 12),
          DateField(
            label: 'Plan günü',
            value: TrTime.startOfDay(_at),
            firstDate: today,
            lastDate: TrTime.addDays(today, 90),
            onChanged: _setDay,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: 'Plan saati ${Fmt.time(_at)}, değiştir',
              excludeSemantics: true,
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text('Saat ${Fmt.time(_at)}'),
              ),
            ),
          ),
          if (_windowWarning != null) ...[
            const SizedBox(height: 8),
            AknBanner(tone: AknTone.warn, message: _windowWarning!),
          ],
          if (_checking) ...[
            const SizedBox(height: 12),
            const AknBanner(
              tone: AknTone.info,
              icon: Icons.hourglass_top_rounded,
              message: 'Sevkiyat kontrol ediliyor…',
            ),
          ],
          if (!online) ...[
            const SizedBox(height: 12),
            const AknBanner(
              tone: AknTone.neutral,
              icon: Icons.cloud_off_rounded,
              message: 'Çevrimdışıyken sevkiyat planlanamaz.',
            ),
          ],
          const SizedBox(height: 20),
          AknButton(
            label: 'Sevkiyatı planla',
            icon: Icons.event_available_rounded,
            expand: true,
            loading: _busy,
            loadingLabel: 'Planlanıyor',
            onPressed: online ? () => unawaited(_submit()) : null,
          ),
        ],
      ),
    );
  }
}

class _DriverField extends StatelessWidget {
  const _DriverField({required this.choice, required this.onTap, this.error});

  final DriverChoice? choice;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final ch = choice;
    final account = ch?.account;
    return Semantics(
      button: true,
      label: ch == null ? 'Şoför seçin' : 'Şoför: ${ch.displayName}, değiştir',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AknRadius.input,
        child: InputDecorator(
          isEmpty: ch == null,
          decoration: InputDecoration(
            labelText: 'Şoför *',
            errorText: error,
            suffixIcon: const Icon(Icons.expand_more_rounded),
          ),
          child: ch == null
              ? const SizedBox(height: 20)
              : Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      ch.displayName,
                      style: t.body.copyWith(fontSize: 16, color: c.ink),
                    ),
                    if (account?.hasActiveDevice ?? false) const InAppBadge(),
                    if (!ch.isAccount)
                      const StatusChip(
                        label: 'Hesapsız',
                        tone: AknTone.neutral,
                        icon: Icons.person_off_outlined,
                        size: StatusChipSize.small,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
