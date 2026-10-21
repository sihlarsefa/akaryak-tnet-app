import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../ui/ui.dart';
import '../utils/tr_time.dart';

/// Ana sayfa yer tutucusu (aşama 0): lacivert karşılama + bu ana sayfada neler olacağı. Özellik
/// ajanları kendi ana sayfalarıyla değiştirir (`CustomerHome`, `BayiHome`, `FieldHome`, `DriverHome`).
class HomePlaceholder extends ConsumerWidget {
  const HomePlaceholder({
    super.key,
    required this.roleLabel,
    this.upcoming = const [],
  });

  /// "Müşteri", "Bayi", "Saha satış", "Şoför", "Merkez".
  final String roleLabel;

  /// Bu ana sayfada gösterilecek bölümler (ikon, başlık, açıklama).
  final List<(IconData, String, String)> upcoming;

  static String greeting([DateTime? now]) {
    final h = TrTime.wall(now ?? TrTime.now()).hour;
    if (h < 5) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(sessionControllerProvider).access;
    final t = context.aknText;
    final c = context.akn;
    final firstName = (access?.displayName ?? '').split(' ').first;
    final roles = access?.bayiRoleNames.isNotEmpty ?? false
        ? access!.bayiRoleNames
        : [roleLabel];
    return AppScaffold(
      navy: true,
      title: 'AkaryakıtNet',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AknHeroPanel(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
                  style: t.title,
                ),
                const SizedBox(height: 4),
                Text(
                  access?.organizationTitle ?? roleLabel,
                  style: t.body.copyWith(color: c.onNavyDim),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in roles)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.onNavy.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          r,
                          style: t.label.copyWith(color: c.onNavy),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader(
            title: 'Yakında burada',
            subtitle: 'Bu ana sayfa hazırlanıyor',
          ),
          for (final (icon, title, text) in upcoming)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AknCard(
                child: AknListTile(
                  title: title,
                  subtitle: text,
                  leadingIcon: icon,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
