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
    subtitle: [?target.customerTitle, target.orderNumber].join(', '),
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

  void _setTime(int hour, int minute) {
    final w = TrTime.wall(_at);
    setState(() => _at = TrTime.fromWall(w.year, w.month, w.day, hour, minute));
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
          _PlanSummary(target: _t, windowLabel: windowLabel),
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
            const SizedBox(height: 6),
            Text(
              'Son kullanılanlar',
              style: t.label.copyWith(
                fontWeight: FontWeight.w400,
                color: c.dim,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final s in suggestions.plates.take(6))
                  AknChip(
                    label: Fmt.plate(s.value),
                    semanticLabel: s.pair == null
                        ? 'Plaka ${Fmt.plate(s.value)}'
                        : 'Plaka ${Fmt.plate(s.value)}, son şoför ${s.pair}',
                    selected: Fmt.plate(_plate.text) == Fmt.plate(s.value),
                    onTap: () => _applyPlate(s),
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
          const SizedBox(height: 14),
          _TimeChips(at: _at, onPick: _pickTime, onSet: _setTime),
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
              icon: Icons.cloud_off_outlined,
              message: 'Çevrimdışıyken sevkiyat planlanamaz.',
            ),
          ],
          const SizedBox(height: 20),
          AknButton(
            label: 'Sevkiyatı planla',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AknFieldLabel(text: 'Şoför *'),
          const SizedBox(height: 6),
          InkWell(
            onTap: onTap,
            borderRadius: AknRadius.input,
            child: InputDecorator(
              isEmpty: ch == null,
              decoration: AknTextField.decoration(
                context,
                hint: 'Seçmek için dokunun',
                errorText: error,
                suffixIcon: const Icon(Icons.expand_more_rounded),
              ),
              child: ch == null
                  ? const SizedBox(height: 22)
                  : Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          ch.displayName,
                          style: t.body.copyWith(
                            fontSize: 16,
                            height: 22 / 16,
                            color: c.ink,
                          ),
                        ),
                        if (account?.hasActiveDevice ?? false)
                          const AknLamp(
                            label: 'uygulamada',
                            tone: AknTone.ok,
                            size: AknLampSize.small,
                          ),
                        if (!ch.isAccount)
                          const AknLamp(
                            label: 'Hesapsız',
                            tone: AknTone.neutral,
                            size: AknLampSize.small,
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Planlanacak siparişin özeti: ADR levhası, ürün ve kalan litre; nokta, teslim penceresi, tank.
class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.target, this.windowLabel});

  final PlanTarget target;
  final String? windowLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final adr = AdrPlate.forProduct(target.productName, height: 30);
    final meta = [
      ?target.deliveryPointName,
      if (windowLabel != null) 'pencere $windowLabel',
      if (target.tankCapacityLiters != null)
        'tank ${Fmt.liters(target.tankCapacityLiters)}',
    ].join(', ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (adr != null) ...[adr, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                keepUnits(
                  [
                    ?target.productName,
                    'kalan ${Fmt.liters(target.remainingLiters)}',
                  ].join(', '),
                ),
                style: t.bodyStrong.copyWith(color: c.ink),
              ),
              if (meta.isNotEmpty)
                Text(
                  keepUnits(meta),
                  style: t.bodySmall.copyWith(color: c.dim),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Plan saati: sık kullanılan saatler çip olarak ("08:00", "10:00", "13:00", "15:00") ve "Başka saat"
/// (saat seçici); seçili saat mürekkep dolgulu.
class _TimeChips extends StatelessWidget {
  const _TimeChips({
    required this.at,
    required this.onPick,
    required this.onSet,
  });

  final DateTime at;
  final VoidCallback onPick;
  final void Function(int hour, int minute) onSet;

  static const _presets = [(8, 0), (10, 0), (13, 0), (15, 0)];

  @override
  Widget build(BuildContext context) {
    final w = TrTime.wall(at);
    String two(int v) => v.toString().padLeft(2, '0');
    final preset = _presets.any((p) => p.$1 == w.hour && p.$2 == w.minute);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AknFieldLabel(text: 'Plan saati'),
        Wrap(
          spacing: 8,
          children: [
            for (final (h, m) in _presets)
              AknChip(
                label: '${two(h)}:${two(m)}',
                semanticLabel: 'Plan saati ${two(h)}:${two(m)}',
                selected: w.hour == h && w.minute == m,
                onTap: () => onSet(h, m),
              ),
            AknChip(
              label: preset ? 'Başka saat' : 'Saat ${Fmt.time(at)}',
              icon: Icons.schedule_rounded,
              semanticLabel: 'Plan saati ${Fmt.time(at)}, değiştir',
              selected: !preset,
              onTap: onPick,
            ),
          ],
        ),
      ],
    );
  }
}
