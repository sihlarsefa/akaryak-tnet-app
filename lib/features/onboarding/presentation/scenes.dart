import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../copy.dart';

/// Sahne zaman çizelgesi: sayfa öne gelince bir kez oynar (≈1,8 sn, sakin eğriler, sıçrama yok).
/// [animate] kapalıyken (azaltılmış hareket ya da ekran okuyucu) son kare durağan gösterilir.
/// Sayfa görünümden çıkınca PageView sahneyi kaldırır; dönen sahne yeniden oynar.
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

/// Uygulama ekranı gibi görünen çizim kartı (lacivert zemin üstünde açık yüzey). Yazı ölçeği
/// uygulanmaz: çizimdir, anlamını sahne açıklaması taşır.
class SceneCard extends StatelessWidget {
  const SceneCard({super.key, required this.child});

  final Widget child;

  static const size = Size(300, 268);

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AknRadius.xl - 4),
          border: Border.all(color: c.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      ),
    );
  }
}

/// Sahne 1 — Sipariş: ürün, litre (sayarak artar), teslimat; "Sipariş ver" basılır, gönderildi.
class OrderScene extends StatelessWidget {
  const OrderScene({super.key, required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final x = context.aknText;
    final liters = (12500 * _seg(t, 0.12, 0.6) / 100).round() * 100;
    final sent = t >= 0.84;
    final press = t > 0.7 && t < 0.84 ? 0.96 : 1.0;
    return SceneCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Reveal(
            v: _seg(t, 0, 0.25),
            child: Row(
              children: [
                const AknIconBox(
                  icon: Icons.local_gas_station_rounded,
                  tone: AknTone.brand,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(OnboardingCopy.product, style: x.bodyStrong),
                      Text(OnboardingCopy.productCaption, style: x.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: c.lineSoft),
          _SceneRow(
            v: _seg(t, 0.08, 0.32),
            label: OnboardingCopy.quantity,
            value: Fmt.liters(liters),
            strong: true,
          ),
          _SceneRow(
            v: _seg(t, 0.18, 0.42),
            label: OnboardingCopy.delivery,
            value: OnboardingCopy.deliveryValue,
          ),
          _SceneRow(
            v: _seg(t, 0.28, 0.52),
            label: OnboardingCopy.point,
            value: OnboardingCopy.pointValue,
          ),
          const Spacer(),
          _Reveal(
            v: _seg(t, 0.4, 0.62),
            child: AnimatedScale(
              scale: press,
              duration: AknMotion.of(context, AknMotion.fast),
              child: _Pill(
                filled: true,
                tone: sent ? AknTone.ok : null,
                icon: sent ? Icons.check_rounded : null,
                label: sent ? OnboardingCopy.sent : OnboardingCopy.placeOrder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sahne 2 — Teklif: hazır rozeti, geçerlilik halkası, litre fiyatı ve toplam; "Onayla".
class QuoteScene extends StatelessWidget {
  const QuoteScene({super.key, required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final x = context.aknText;
    final approved = t >= 0.84;
    return SceneCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Reveal(
            v: _seg(t, 0, 0.22),
            child: Row(
              children: [
                const Flexible(
                  child: StatusChip(
                    label: OnboardingCopy.quoteReady,
                    tone: AknTone.ok,
                    icon: Icons.request_quote_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                const Spacer(),
                ProgressRing(
                  value: 0.72 * _seg(t, 0.1, 0.62),
                  size: 44,
                  strokeWidth: 4,
                  child: Center(
                    child: Text(OnboardingCopy.validFor, style: x.caption),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Reveal(
            v: _seg(t, 0.16, 0.42),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.unitPrice(41.85),
                  style: x.amountLarge.copyWith(color: c.ink),
                ),
                Text(OnboardingCopy.unitPriceCaption, style: x.caption),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Reveal(
            v: _seg(t, 0.3, 0.56),
            child: Row(
              children: [
                Expanded(
                  child: _Mini(
                    label: OnboardingCopy.total,
                    value: Fmt.money(523125),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: _Mini(
                    label: OnboardingCopy.deliveryDate,
                    value: OnboardingCopy.tomorrow,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _Reveal(
            v: _seg(t, 0.46, 0.68),
            child: Row(
              children: [
                const Expanded(
                  child: _Pill(filled: false, label: OnboardingCopy.revise),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Pill(
                    filled: true,
                    tone: approved ? AknTone.ok : null,
                    icon: approved ? Icons.check_rounded : null,
                    label: approved
                        ? OnboardingCopy.approved
                        : OnboardingCopy.approve,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sahne 3 — Teslimat: araç yolda (plaka, rota), adımlar, teslim alınan litre damlası.
class DeliveryScene extends StatelessWidget {
  const DeliveryScene({super.key, required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final x = context.aknText;
    final fill = _seg(t, 0.6, 1);
    return SceneCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Reveal(
            v: _seg(t, 0, 0.22),
            child: const Row(
              children: [
                Flexible(
                  child: StatusChip(
                    label: OnboardingCopy.inTransit,
                    tone: AknTone.brand,
                    icon: Icons.local_shipping_rounded,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: PlateBadge(
                      plate: OnboardingCopy.plate,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TruckRoute(
            progress: _seg(t, 0.08, 0.72, AknMotion.emphasizedCurve),
            height: 40,
            originLabel: OnboardingCopy.origin,
            destinationLabel: OnboardingCopy.destination,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: _Step(label: OnboardingCopy.stepPlanned, done: true),
              ),
              Expanded(
                child: _Step(
                  label: OnboardingCopy.stepDispatched,
                  done: t >= 0.3,
                ),
              ),
              Expanded(
                child: _Step(
                  label: OnboardingCopy.stepDelivered,
                  done: t >= 0.92,
                ),
              ),
            ],
          ),
          const Spacer(),
          _Reveal(
            v: _seg(t, 0.5, 0.7),
            child: Row(
              children: [
                FuelDrop(fill: fill, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(OnboardingCopy.received, style: x.caption),
                      Text(
                        Fmt.liters((12500 * fill / 100).round() * 100),
                        style: x.amount,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yukarı kayarak beliren parça.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.v, required this.child});

  final double v;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (v >= 1) return child;
    return Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child),
    );
  }
}

class _SceneRow extends StatelessWidget {
  const _SceneRow({
    required this.v,
    required this.label,
    required this.value,
    this.strong = false,
  });

  final double v;
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final x = context.aknText;
    final c = context.akn;
    return _Reveal(
      v: v,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: x.bodySmall)),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text(
                value,
                style: (strong ? x.amount : x.bodyStrong).copyWith(
                  color: c.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final x = context.aknText;
    final c = context.akn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.chip,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: x.caption.copyWith(color: c.text)),
          Text(
            value,
            style: x.bodyStrong.copyWith(color: c.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Düğme çizimi (dokunulmaz).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.filled,
    required this.label,
    this.tone,
    this.icon,
  });

  final bool filled;
  final String label;
  final AknTone? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final x = context.aknText;
    final tc = tone == null ? null : c.tone(tone!);
    final bg = filled ? (tc?.solid ?? c.brandFill) : c.surface;
    final fg = filled ? (tc?.onSolid ?? c.onBrandFill) : c.ink;
    return AnimatedContainer(
      duration: AknMotion.of(context, AknMotion.base),
      curve: AknMotion.standard,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AknRadius.md),
        border: filled ? null : Border.all(color: c.lineStrong),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: x.button.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final x = context.aknText;
    return Column(
      children: [
        AnimatedContainer(
          duration: AknMotion.of(context, AknMotion.base),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: done ? c.ok.solid : c.surfaceAlt,
            shape: BoxShape.circle,
            border: done ? null : Border.all(color: c.lineStrong),
          ),
          child: done
              ? Icon(Icons.check_rounded, size: 14, color: c.ok.onSolid)
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: x.caption.copyWith(color: done ? c.ink : c.text),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
