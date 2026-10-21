import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/ui.dart';
import '../destinations.dart';
import 'shell_badges.dart';

/// "Diğer" sayfası (spec A.2; tasarım v2 §7.17): alt menüye sığmayan hedefler + Bildirimler, Asistan,
/// Profil — ince çizgiyle ayrılmış defter satırları (24 px soluk simge, ok; rozet Asfalt). Rozeti olan
/// öğe sayısını gösterir; ekran okuyucu "Onaylarım, 3 bekleyen" der.
Future<void> showMoreSheet(BuildContext context, List<AppDestination> items) =>
    showAppSheet<void>(
      context: context,
      title: NavLayout.moreLabel,
      padding: const EdgeInsets.only(bottom: 16),
      builder: (_) => MoreSheetBody(items: items, rootContext: context),
    );

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
    return AknLedger(
      children: [
        for (final d in items)
          Semantics(
            button: true,
            label: destinationSemantics(d, badges[d.id] ?? 0),
            excludeSemantics: true,
            onTap: () => _open(context, d),
            child: AknListTile(
              title: d.label,
              leadingIcon: d.icon,
              trailing: (badges[d.id] ?? 0) > 0
                  ? AknCountBadge(count: badges[d.id]!)
                  : null,
              showChevron: true,
              onTap: () => _open(context, d),
            ),
          ),
      ],
    );
  }

  void _open(BuildContext sheetContext, AppDestination d) {
    Navigator.of(sheetContext).pop();
    GoRouter.of(rootContext).push(d.path);
  }
}
