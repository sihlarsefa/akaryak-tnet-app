import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../ui/ui.dart';
import '../utils/tr_time.dart';
import '../utils/turkish_text.dart';

/// Ana sayfa yer tutucusu (aşama 0; tasarım v3): plaka yok — turuncu ana sayfa bandı (Türkiye saatine göre
/// karşılama, çalıştığı yer, ad ve roller) ve bu ana sayfada neler olacağı: sayfada yüzen beyaz bir bölüm
/// kartında satırlar. İçerik basamaklı gelir (`StaggerScope` + `StaggerItem`). Özellik ajanları kendi ana
/// sayfalarıyla değiştirir (`CustomerHome`, `BayiHome`, `FieldHome`, `DriverHome`).
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
    final c = context.akn;
    final name = access?.displayName ?? '';
    final firstName = name.split(' ').first;
    final roles = access?.bayiRoleNames.isNotEmpty ?? false
        ? access!.bayiRoleNames
        : [roleLabel];
    // "Selin Aydın, şoför": rol cümle içinde küçük harfle (§6.2).
    final person = [
      if (name.isNotEmpty) name,
      ...roles.map(TurkishText.lower),
    ].join(', ');
    return AppScaffold(
      // Karşılama bantta (Türkiye saatiyle); gövde doğrudan içerikle başlar.
      homeHeader: AknHomeHeader(
        company: access?.organizationTitle ?? 'AkaryakıtNet',
        person: person,
        greeting: '${greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
      ),
      body: StaggerScope(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: staggered([
            const SectionHeader(
              title: 'Yakında burada',
              subtitle: 'Bu ana sayfa hazırlanıyor.',
            ),
            if (upcoming.isNotEmpty)
              Padding(
                padding: AknSpace.pagePadding,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: AknRadius.section,
                    border: c.isDark ? Border.all(color: c.line) : null,
                    boxShadow: AknShadows.card(c),
                  ),
                  child: ClipRRect(
                    borderRadius: AknRadius.section,
                    // Satırlar kartta olduğunu bilir: simge kutuları gri kuyu olur.
                    child: AknCardScope(
                      child: AknLedger(
                        children: [
                          for (final (icon, title, text) in upcoming)
                            AknListTile(
                              title: title,
                              subtitle: text,
                              leadingIcon: icon,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
