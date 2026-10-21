import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../copy.dart';

/// Sahne zaman çizelgesi: sayfa öne gelince bir kez 0 → 1 oynar (döngü yok). [animate] kapalıysa
/// (azaltılmış hareket, ekran okuyucu) doğrudan son kareyi (t = 1) çizer.
class SceneTimeline extends StatefulWidget {
  const SceneTimeline({
    super.key,
    required this.active,
    required this.animate,
    required this.builder,
    this.duration = const Duration(milliseconds: 1800),
  });

  final bool active;
  final bool animate;
  final Duration duration;
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<SceneTimeline> createState() => _SceneTimelineState();
}

class _SceneTimelineState extends State<SceneTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _sync(initial: true);
  }

  @override
  void didUpdateWidget(SceneTimeline old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate || old.active != widget.active) {
      _sync(initial: false, wasActive: old.active);
    }
  }

  void _sync({required bool initial, bool wasActive = false}) {
    if (!widget.animate) {
      _c.value = 1;
      return;
    }
    if (widget.active && (initial || !wasActive)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => widget.builder(context, _c.value),
  );
}

/// [t] içindeki [a]–[b] aralığının 0..1 ilerlemesi (eğriyle).
double _seg(double t, double a, double b, [Curve curve = AknMotion.standard]) =>
    curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// Sahnelerin tasarım genişliği: gerçek arayüzün telefon genişliği (390) eksi kenar boşlukları. Tanıtım
/// sayfası çizimi 0,9 ölçekte ve alana sığacak kadar küçülterek gösterir.
const double kSceneWidth = 350;

/// Basılan düğmenin kısa "basıldı" kareleri (0,98 ölçek) ve yerine gelen sonuç satırı.
class _PressThenResult extends StatelessWidget {
  const _PressThenResult({
    required this.t,
    required this.pressAt,
    required this.button,
    required this.result,
  });

  final double t;
  final double pressAt;
  final Widget button;
  final Widget result;

  @override
  Widget build(BuildContext context) {
    final press =
        _seg(t, pressAt, pressAt + 0.05) -
        _seg(t, pressAt + 0.05, pressAt + 0.1);
    final swap = _seg(t, pressAt + 0.12, pressAt + 0.22);
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          if (swap < 1)
            Opacity(
              opacity: 1 - swap,
              child: Transform.scale(scale: 1 - 0.02 * press, child: button),
            ),
          if (swap > 0)
            Opacity(
              opacity: swap,
              child: Transform.translate(
                offset: Offset(0, 6 * (1 - swap)),
                child: result,
              ),
            ),
        ],
      ),
    );
  }
}

/// Çizimdeki düğme (gerçek birincil düğmenin görünüşü; dokunulmaz).
class _FakeButton extends StatelessWidget {
  const _FakeButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.brandFill,
        borderRadius: AknRadius.button,
      ),
      child: Text(label, style: t.button.copyWith(color: c.onBrandFill)),
    );
  }
}

/// Sonuç satırı: yeşil onay + cümle (sonuç, düğmenin fiilini tekrar eder).
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Row(
      children: [
        Icon(Icons.check_circle_rounded, size: 24, color: c.ok.fg),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: t.bodyStrong.copyWith(color: c.ink)),
        ),
      ],
    );
  }
}

/// Sahne 1 — Sipariş: sihirbazın özet plakası ("12.500 L", motorin, yarın 09:00) sayaç gibi döner;
/// "Siparişi gönder" basılır, yerine "Siparişiniz bayiye gönderildi" gelir.
class OrderScene extends StatelessWidget {
  const OrderScene({super.key, required this.t, this.animate = true});

  final double t;

  /// Plakadaki rakam bir kez döner (azaltılmış harekette son kare).
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tx = context.aknText;
    return SizedBox(
      width: kSceneWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            OnboardingCopy.wizardTitle,
            style: tx.display.copyWith(color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            OnboardingCopy.wizardMeta,
            style: tx.bodySmall.copyWith(color: c.dim),
          ),
          const SizedBox(height: 16),
          AknPlate(
            head: const PlateHead(
              icon: Icons.local_gas_station_outlined,
              title: OnboardingCopy.summaryTitle,
            ),
            figure: PlateFigure(
              value: OnboardingCopy.litres,
              unit: 'L',
              animate: animate,
              semanticLabel: OnboardingCopy.litresSpoken,
            ),
            delta: Text(
              OnboardingCopy.orderSentence,
              style: tx.body.copyWith(
                height: 20 / 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            below: const PlateReadouts(
              items: [
                PlateReadout(
                  label: OnboardingCopy.unitPriceCaption,
                  value: '42,35',
                  unit: '₺/L',
                ),
                PlateReadout(
                  label: OnboardingCopy.total,
                  value: '529.375',
                  unit: '₺',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PressThenResult(
            t: t,
            pressAt: 0.55,
            button: const _FakeButton(label: OnboardingCopy.placeOrder),
            result: const _ResultLine(text: OnboardingCopy.sent),
          ),
        ],
      ),
    );
  }
}

/// Sahne 2 — Teklif: "Kararınızı bekliyor" + geri sayım, bayinin teklif plakası; "Teklifi onayla"
/// basılır, plaka mühürlenir (1,02 → 1), durum "Teklif onaylandı" olur.
class QuoteScene extends StatelessWidget {
  const QuoteScene({super.key, required this.t, this.animate = true});

  final double t;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tx = context.aknText;
    final approved = t >= 0.72;
    final stamp = _seg(t, 0.72, 0.81, AknMotion.emphasizedCurve);
    final scale = approved ? 1.02 - 0.02 * stamp : 1.0;
    return SizedBox(
      width: kSceneWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            OnboardingCopy.quoteOrder,
            style: tx.display.copyWith(color: c.ink),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: approved
                    ? const AknLamp(
                        label: OnboardingCopy.approved,
                        tone: AknTone.ok,
                        solid: true,
                      )
                    : const AknLamp(
                        label: OnboardingCopy.awaitingDecision,
                        tone: AknTone.brand,
                      ),
              ),
              if (!approved) ...[
                Icon(Icons.timer_outlined, size: 17, color: c.brandInk),
                const SizedBox(width: 4),
                Text(
                  OnboardingCopy.validFor,
                  style: tx.bodySmall.copyWith(
                    color: c.brandInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Transform.scale(
            scale: scale,
            child: AknPlate(
              head: const PlateHead(
                icon: Icons.request_quote_outlined,
                title: OnboardingCopy.quoteFrom,
                period: OnboardingCopy.quoteTime,
              ),
              figure: PlateFigure(
                value: '529.375',
                decimals: ',00',
                unit: '₺',
                animate: animate,
                semanticLabel: OnboardingCopy.quoteSpoken,
              ),
              below: const PlateReadouts(
                items: [
                  PlateReadout(
                    label: OnboardingCopy.unitPriceShort,
                    value: '42,35',
                    unit: '₺/L',
                  ),
                  PlateReadout(
                    label: OnboardingCopy.quantity,
                    value: '12.500',
                    unit: 'L',
                  ),
                  PlateReadout(
                    label: OnboardingCopy.deliveryDate,
                    value: OnboardingCopy.tomorrow,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PressThenResult(
            t: t,
            pressAt: 0.55,
            button: const _FakeButton(label: OnboardingCopy.approve),
            result: const _ResultLine(text: OnboardingCopy.approvedToast),
          ),
        ],
      ),
    );
  }
}

/// Sahne 3 — Teslimat: defter satırı ("Motorin, 12.500 L", "Yolda", varış), » aracı rotada ilerler;
/// altında "Planlandı, Yola çıktı, Teslim edildi" zaman çizelgesi.
class DeliveryScene extends StatelessWidget {
  const DeliveryScene({super.key, required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tx = context.aknText;
    final dispatched = t >= 0.3;
    return SizedBox(
      width: kSceneWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            OnboardingCopy.deliveryRowTitle,
            style: tx.display.copyWith(color: c.ink),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  OnboardingCopy.deliveryRowMeta,
                  style: tx.bodySmall.copyWith(color: c.dim),
                ),
              ),
              const SizedBox(width: 12),
              const PlateBadge(plate: OnboardingCopy.plate),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AknLamp(
                  label: dispatched
                      ? OnboardingCopy.inTransit
                      : OnboardingCopy.stepPlanned,
                  tone: AknTone.info,
                ),
              ),
              Text(
                OnboardingCopy.eta,
                style: tx.bodyStrong.copyWith(color: c.ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TruckRoute(
            progress: dispatched ? 0.62 : 0.08,
            moving: dispatched,
            originLabel: OnboardingCopy.origin,
            destinationLabel: OnboardingCopy.remaining,
            semanticLabel: OnboardingCopy.deliveryScene,
          ),
          const SizedBox(height: 18),
          StepTimeline(
            dense: true,
            steps: [
              const TimelineStep(
                title: OnboardingCopy.stepPlanned,
                time: '09:10',
                state: TimelineState.done,
              ),
              TimelineStep(
                title: OnboardingCopy.stepDispatched,
                time: dispatched ? '09:58' : null,
                state: dispatched ? TimelineState.done : TimelineState.current,
              ),
              TimelineStep(
                title: OnboardingCopy.stepDelivered,
                time: OnboardingCopy.etaShort,
                state: dispatched
                    ? TimelineState.current
                    : TimelineState.upcoming,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
