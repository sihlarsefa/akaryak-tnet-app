import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';

/// Büyük yazı (1,3× ve üstü): yan yana sığmayan öğeler alt alta dizilir (spec C.7, %200'e kadar).
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13;

/// Zaman çizelgesi için kısa zaman damgası: bu yıl `21.10 14:20`, değilse `21.10.2025`.
String shortStamp(DateTime? at) {
  if (at == null) return Fmt.dash;
  final w = TrTime.wall(at);
  if (w.year != TrTime.wall(TrTime.now()).year) return Fmt.date(at);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(w.day)}.${two(w.month)} ${Fmt.time(at)}';
}

/// Büyük yazıda adımın zamanı başlığın yanına sığmaz (çekirdek `StepTimeline` zaman metnini
/// esnetmez): zaman alt satırın başına iner.
List<TimelineStep> adaptSteps(BuildContext context, List<TimelineStep> steps) {
  if (!isLargeText(context)) return steps;
  return [
    for (final s in steps)
      s.time == null
          ? s
          : TimelineStep(
              title: s.title,
              subtitle: [s.time!, ?s.subtitle].join('\n'),
              state: s.state,
              icon: s.icon,
              content: s.content,
            ),
  ];
}

/// Satır içinde (Wrap) doğal genişliği sığmayan rozet ya da çip: taşmak yerine küçülür.
class Shrinkable extends StatelessWidget {
  const Shrinkable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: child,
  );
}

/// A5 ekranlarının giriş hareketi (tasarım v3 §5): çekirdek [StaggerItem] ile aynı görünüm —
/// solarak, yükselerek ve hafifçe büyüyerek, [StaggerScope] içinde sırayla, kaydırınca hemen — ama
/// çocuk durumunu korur. Çekirdek sarmalayıcı hareket bitince çocuğu çıplak döndürür (öğe yeniden
/// kurulur: plakanın rakamları yeniden döner, yanıt alanı odağını yitirebilir); burada çocuk bir
/// [GlobalKey] altında durur ve yeniden kurulmak yerine taşınır.
class A5StaggerItem extends StatefulWidget {
  const A5StaggerItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<A5StaggerItem> createState() => _A5StaggerItemState();
}

class _A5StaggerItemState extends State<A5StaggerItem> {
  final GlobalKey _keep = GlobalKey();

  @override
  Widget build(BuildContext context) => StaggerItem(
    index: widget.index,
    child: KeyedSubtree(key: _keep, child: widget.child),
  );
}

/// [children]'ı durumunu koruyan [A5StaggerItem]'lara sarar.
List<Widget> a5Staggered(List<Widget> children) => [
  for (var i = 0; i < children.length; i++)
    A5StaggerItem(index: i, child: children[i]),
];

/// Durumunu koruyan [FadeUp] (kahraman kartın yükselişi, karar çubuğunun girişi): çocuk hareket
/// bitince yeniden kurulmaz.
class A5FadeUp extends StatefulWidget {
  const A5FadeUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
    this.offset = 12,
    this.curve = AknMotion.standard,
    this.scale = 1,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final Curve curve;
  final double scale;

  @override
  State<A5FadeUp> createState() => _A5FadeUpState();
}

class _A5FadeUpState extends State<A5FadeUp> {
  final GlobalKey _keep = GlobalKey();

  @override
  Widget build(BuildContext context) => FadeUp(
    delay: widget.delay,
    duration: widget.duration,
    offset: widget.offset,
    curve: widget.curve,
    scale: widget.scale,
    child: KeyedSubtree(key: _keep, child: widget.child),
  );
}

/// Hata sarsıntısı (tasarım v3 §5: üç hızlı ±6 px, sönerek, sonlu): [trigger] büyüyünce oynar;
/// hareket azaltılınca durgun. Ağaç hep aynı kalır (çocuk yeniden kurulmaz).
class A5Shake extends StatefulWidget {
  const A5Shake({super.key, required this.trigger, required this.child});

  /// Her artışta bir sarsıntı (ör. reddedilen gönderim sayısı); azalınca durgun.
  final int trigger;
  final Widget child;

  @override
  State<A5Shake> createState() => _A5ShakeState();
}

class _A5ShakeState extends State<A5Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(A5Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger > old.trigger && !AknMotion.reduced(context)) {
      AknHaptics.warning();
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
    child: widget.child,
    builder: (context, child) {
      final v = _c.value;
      final dx = v <= 0 || v >= 1
          ? 0.0
          : math.sin(v * math.pi * 6) * 6 * (1 - v);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
  );
}
