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
