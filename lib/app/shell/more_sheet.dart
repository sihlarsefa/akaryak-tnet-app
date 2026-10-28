import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/ui.dart';
import '../destinations.dart';
import 'shell_badges.dart';

/// "Diğer" sayfası (spec A.2; tasarım v3 §4): alt menüye sığmayan hedefler + Bildirimler, Asistan,
/// Profil. Sayfa açık gri (`bg`; koyu temada `surface`); hedefler beyaz, gölgeli gruplu kartlarda (koyu
/// temada `surfaceRaised` + 1 px çizgi; önce iş hedefleri, sonra hesap: Bildirimler, Asistan, Profil).
/// Her satır: 40 px yuvarlatılmış kare simge kutusu (`surfaceAlt`, mürekkep simge), ad, rozet (koyu
/// turuncu sayı hapı) ve ok. Satırlar sırayla kayarak gelir; basınca hafifçe küçülür. Ekran okuyucu
/// "Onaylarım, 3 bekleyen" der.
Future<void> showMoreSheet(BuildContext context, List<AppDestination> items) {
  final c = context.akn;
  return showAppSheet<void>(
    context: context,
    title: NavLayout.moreLabel,
    padding: const EdgeInsets.fromLTRB(AknSpace.page, 2, AknSpace.page, 16),
    backgroundColor: c.isDark ? c.surface : c.bg,
    builder: (_) => MoreSheetBody(items: items, rootContext: context),
  );
}

class MoreSheetBody extends ConsumerWidget {
  const MoreSheetBody({
    super.key,
    required this.items,
    required this.rootContext,
  });

  final List<AppDestination> items;

  /// Sayfa kapandıktan sonra gezinme bu bağlamla yapılır.
  final BuildContext rootContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(destinationBadgesProvider);
    // İş hedefleri bir kartta, hesap hedefleri (Bildirimler, Asistan, Profil) ayrı kartta.
    final groups = [
      [
        for (final d in items)
          if (!d.isExtra) d,
      ],
      [
        for (final d in items)
          if (d.isExtra) d,
      ],
    ].where((g) => g.isNotEmpty).toList();
    var index = 0;
    return StaggerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var g = 0; g < groups.length; g++) ...[
            if (g > 0) const SizedBox(height: 14),
            _Group(
              children: [
                for (final d in groups[g])
                  StaggerItem(
                    index: index++,
                    child: Semantics(
                      button: true,
                      label: destinationSemantics(d, badges[d.id] ?? 0),
                      excludeSemantics: true,
                      onTap: () => _open(context, d),
                      child: _MoreRow(
                        destination: d,
                        badge: badges[d.id] ?? 0,
                        onTap: () => _open(context, d),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _open(BuildContext sheetContext, AppDestination d) {
    AknHaptics.selection();
    Navigator.of(sheetContext).pop();
    GoRouter.of(rootContext).push(d.path);
  }
}

/// Beyaz grup kartı: r20 yuvarlatılmış kare, kart gölgesi (koyu temada `surfaceRaised` + 1 px çizgi);
/// satırlar arasında simgeden sonra başlayan ince çizgi.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: c.isDark ? c.surfaceRaised : c.surface,
        shape: RoundedSuperellipseBorder(
          borderRadius: AknRadius.card,
          side: c.isDark ? BorderSide(color: c.line) : BorderSide.none,
        ),
        shadows: AknShadows.card(c),
      ),
      child: ClipRSuperellipse(
        borderRadius: AknRadius.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 70),
                  child: SizedBox(
                    height: 1,
                    width: double.infinity,
                    child: ColoredBox(color: c.isDark ? c.line : c.lineSoft),
                  ),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Bir hedef satırı: simge kutusu, ad, rozet, ok. Basılıyken `surfaceAlt` dolgu ve 0,97 ölçek.
class _MoreRow extends StatefulWidget {
  const _MoreRow({
    required this.destination,
    required this.badge,
    required this.onTap,
  });

  final AppDestination destination;
  final int badge;
  final VoidCallback onTap;

  @override
  State<_MoreRow> createState() => _MoreRowState();
}

class _MoreRowState extends State<_MoreRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final d = widget.destination;
    final badge = widget.badge;
    return InkWell(
      onTap: widget.onTap,
      onHighlightChanged: (v) {
        if (v != _pressed) setState(() => _pressed = v);
      },
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: AnimatedContainer(
        duration: AknMotion.of(
          context,
          _pressed ? AknMotion.press : AknMotion.pressOut,
        ),
        curve: AknMotion.standard,
        color: _pressed
            ? (c.isDark ? c.line : c.surfaceAlt)
            : Colors.transparent,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: AnimatedScale(
          scale: _pressed && !AknMotion.reduced(context)
              ? AknMotion.pressScale
              : 1,
          duration: _pressed ? AknMotion.press : AknMotion.pressOut,
          curve: _pressed ? AknMotion.standard : AknMotion.spring,
          child: Row(
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  // Koyu temada kart `surfaceRaised`: kutu bir ton açık çizgi rengi.
                  color: c.isDark ? c.line : c.surfaceAlt,
                  shape: const RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(AknRadius.sm),
                    ),
                  ),
                ),
                child: SizedBox.square(
                  dimension: 40,
                  child: Center(child: Icon(d.icon, size: 22, color: c.ink)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  d.label,
                  style: t.bodyStrong.copyWith(color: c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 8),
                _CountPill(count: badge),
              ],
              const SizedBox(width: 6),
              Icon(PhosphorIconsRegular.caretRight, size: 18, color: c.dim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rozet: koyu turuncu (`brandFillPressed`) hap, beyaz 12 w800 tablo rakamları (≥ 4,5:1). İlk
/// görünüşte ve sayı değişince hafifçe zıplar, sonra nefes alır.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final pill = Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.brandFillPressed,
        borderRadius: AknRadius.pillAll,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textScaler: TextScaler.noScaling,
        style: context.aknText.captionStrong.copyWith(
          color: c.onBrandFill,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w800,
          fontFeatures: AknNumerals.tabular,
        ),
      ),
    );
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        key: ValueKey<int>(count),
        tween: Tween<double>(begin: 0.6, end: 1),
        duration: AknMotion.of(context, AknMotion.slow),
        curve: AknMotion.pop,
        child: AknAmbient(
          period: AknMotion.breathe,
          reverse: true,
          builder: (context, v, child) => v == 0
              ? child!
              : Transform.scale(scale: 1 + 0.06 * v, child: child),
          child: pill,
        ),
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
      ),
    );
  }
}
