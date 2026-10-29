import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/routing/app_location.dart';
import '../../core/routing/app_routes.dart';
import '../../core/ui/ui.dart';
import '../destinations.dart';
import 'shell_badges.dart';

/// "Diğer" sayfası (v4 §3.1): en üstte kişi kartı (48 px avatar, ad 17/22 700, "Şirket · rol" 14/20
/// dim; Profil'i açar), altında gruplu defterler — müşteride Siparişler · Finans · Şirket · Hesap,
/// bayide İş · Yönetim · Hesap — 13/18 600 dim başlıklarla. Satırlar 56 dp, 40 dp nötr simge kutusu;
/// sayı hapı yalnızca sıra sizde olan satırlarda. Sayfa açık gri (`bg`; koyu temada `surface`), satırlar
/// sırayla gelir, basınca hafifçe küçülür. Ekran okuyucu "Onaylar, 3 bekleyen" der.
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

  /// Profil'i açan kişi kartının anahtarı (testler).
  static const profileKey = ValueKey('more-profile');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(destinationBadgesProvider);
    final policy = ref.watch(accessPolicyProvider);
    final access = ref.watch(sessionControllerProvider).access;
    final customer = policy.isCustomer;
    // Kişi kartı Profil'i açar; Profil satırı ayrıca listelenmez.
    final rows = [
      for (final d in items)
        if (d.id != DestinationId.profile) d,
    ];
    final groups = <MoreGroup, List<AppDestination>>{};
    for (final d in rows) {
      groups.putIfAbsent(moreGroupOf(d, customer: customer), () => []).add(d);
    }
    final ordered = [
      for (final g in MoreGroup.values)
        if (groups[g]?.isNotEmpty ?? false) g,
    ];
    final name = access?.displayName ?? '';
    final role = customer
        ? (access?.customerUserRoleLabel ??
              (policy.customerRole.isUnknown
                  ? null
                  : policy.customerRole.label))
        : (access?.bayiRoleNames.isNotEmpty ?? false)
        ? access!.bayiRoleNames.first
        : policy.isPlatform
        ? 'Merkez'
        : null;
    final org =
        access?.organizationTitle ??
        (policy.isPlatform ? 'AkaryakıtNet merkez' : null);
    var index = 0;
    return StaggerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          StaggerItem(
            index: index++,
            child: _PersonCard(
              key: MoreSheetBody.profileKey,
              name: name.isEmpty ? 'Profil' : name,
              line: [?org, ?role].join(' · '),
              onTap: () => _go(context, AppRoutes.profile),
            ),
          ),
          for (final g in ordered) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Semantics(
                header: true,
                child: Text(
                  g.label,
                  style: context.aknText.label.copyWith(color: context.akn.dim),
                ),
              ),
            ),
            _Group(
              children: [
                for (final d in groups[g]!)
                  StaggerItem(
                    index: index++,
                    child: Semantics(
                      button: true,
                      label: destinationSemantics(d, _badgeOf(d, badges)),
                      excludeSemantics: true,
                      onTap: () => _go(context, d.path),
                      child: _MoreRow(
                        destination: d,
                        badge: _badgeOf(d, badges),
                        onTap: () => _go(context, d.path),
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

  /// Sayı hapı yalnızca sıra sizde olan satırlarda (okunmamış bildirim sayısı burada gösterilmez).
  static int _badgeOf(AppDestination d, Map<DestinationId, int> badges) =>
      yourMoveDestinations.contains(d.id) ? (badges[d.id] ?? 0) : 0;

  void _go(BuildContext sheetContext, String path) {
    AknHaptics.selection();
    Navigator.of(sheetContext).pop();
    // Diğer'deki yerler bu rolün sekmesi değildir; yine de bir yol sekmeyse `go` ile açılır
    // (QA SC-01).
    openAppLocation(GoRouter.of(rootContext), path);
  }
}

/// Kişi kartı: 48 px avatar, ad 17/22 700, "Şirket · rol" 14/20 dim, sağda ok; Profil'i açar.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    super.key,
    required this.name,
    required this.line,
    required this.onTap,
  });

  final String name;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      button: true,
      label: line.isEmpty ? '$name, profili aç' : '$name, $line. Profili aç',
      excludeSemantics: true,
      onTap: onTap,
      child: _Group(
        children: [
          _Pressable(
            onTap: onTap,
            minHeight: 72,
            child: Row(
              children: [
                AknAvatar(name: name, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.headline.copyWith(color: c.ink),
                      ),
                      if (line.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(line, style: t.bodySmall.copyWith(color: c.dim)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(PhosphorIconsRegular.caretRight, size: 18, color: c.dim),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Beyaz grup defteri: r20, yalnızca ince çizgi (koyu temada `surfaceRaised` + 1 px çizgi); satırlar
/// arasında simgeden sonra başlayan ince çizgi.
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
        shadows: c.isDark ? null : [AknShadows.hairline(c)],
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

/// Basılabilir satır yüzeyi: basılıyken `surfaceAlt` dolgu ve 0,97 ölçek.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.onTap,
    required this.child,
    this.minHeight = 56,
  });

  final VoidCallback onTap;
  final Widget child;
  final double minHeight;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
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
        constraints: BoxConstraints(minHeight: widget.minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: AnimatedScale(
          scale: _pressed && !AknMotion.reduced(context)
              ? AknMotion.pressScale
              : 1,
          duration: _pressed ? AknMotion.press : AknMotion.pressOut,
          curve: _pressed ? AknMotion.standard : AknMotion.spring,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Bir hedef satırı (56 dp): 40 dp nötr simge kutusu, ad, sıra sizdeyse sayı hapı, ok.
class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.destination,
    required this.badge,
    required this.onTap,
  });

  final AppDestination destination;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final d = destination;
    return _Pressable(
      onTap: onTap,
      child: Row(
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              // Koyu temada kart `surfaceRaised`: kutu bir ton açık çizgi rengi.
              color: c.isDark ? c.line : c.surfaceAlt,
              shape: const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.all(Radius.circular(AknRadius.sm)),
              ),
            ),
            child: SizedBox.square(
              dimension: 40,
              child: Center(child: Icon(d.icon, size: 20, color: c.ink)),
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
    );
  }
}

/// Sıra sizde sayısı: `brandSoft` hap, Pas 12 w800 tablo rakamları; ilk görünüşte ve sayı değişince
/// hafifçe zıplar (listeler sakin durur: nefes almaz).
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
        color: c.brandSoft,
        borderRadius: AknRadius.pillAll,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textScaler: TextScaler.noScaling,
        style: context.aknText.captionStrong.copyWith(
          color: c.brandInk,
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
        child: pill,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
      ),
    );
  }
}
