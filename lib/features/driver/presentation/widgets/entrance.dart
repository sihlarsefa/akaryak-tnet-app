import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Şoför ekranlarının giriş hareketi (tasarım v3 §5): çekirdek [StaggerItem] / [FadeUp] ile aynı
/// görünüm — solarak, yükselerek ve hafifçe büyüyerek gelir; [StaggerScope] içinde sırayla,
/// kaydırınca hemen — ama çocuk durumunu korur. Çekirdek sarmalayıcılar hareket bitince çocuğu
/// çıplak döndürür (öğe yeniden kurulur: sayaç rakamları yeniden döner, yazı alanı odağını
/// yitirebilir); burada çocuk bir [GlobalKey] altında durur ve yeniden kurulmak yerine taşınır.
class DriverStaggerItem extends StatefulWidget {
  const DriverStaggerItem({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<DriverStaggerItem> createState() => _DriverStaggerItemState();
}

class _DriverStaggerItemState extends State<DriverStaggerItem> {
  final GlobalKey _keep = GlobalKey();

  @override
  Widget build(BuildContext context) => StaggerItem(
    index: widget.index,
    child: KeyedSubtree(key: _keep, child: widget.child),
  );
}

/// [children]'ı (ör. bir sütunun ya da listenin öğeleri) durumunu koruyan [DriverStaggerItem]'lara
/// sarar.
List<Widget> driverStaggered(List<Widget> children) => [
  for (var i = 0; i < children.length; i++)
    DriverStaggerItem(index: i, child: children[i]),
];

/// Durumunu koruyan [FadeUp]: kahraman kartın yükselişi (24 px, 0,94 → 1, `heroRise`) gibi tek
/// seferlik girişler; çocuk hareket bitince yeniden kurulmaz.
class DriverFadeUp extends StatefulWidget {
  const DriverFadeUp({
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
  State<DriverFadeUp> createState() => _DriverFadeUpState();
}

class _DriverFadeUpState extends State<DriverFadeUp> {
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
