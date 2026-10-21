import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../ui/ui.dart';
import '../utils/tr_time.dart';
import '../utils/turkish_text.dart';

/// Ana sayfa yer tutucusu (aşama 0; tasarım v2 §7.6): plaka yok — ana sayfa başlığı (logo karosu,
/// çalıştığı yer, ad ve roller), `display` karşılama ve bu ana sayfada neler olacağı (defter satırları).
/// Özellik ajanları kendi ana sayfalarıyla değiştirir (`CustomerHome`, `BayiHome`, `FieldHome`,
/// `DriverHome`).
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
      homeHeader: AknHomeHeader(
        company: access?.organizationTitle ?? 'AkaryakıtNet',
        person: person,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AknSpace.page,
              16,
              AknSpace.page,
              0,
            ),
            child: Semantics(
              header: true,
              child: Text(
                '${greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
                style: t.display.copyWith(color: c.ink),
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.6),
              ),
            ),
          ),
          const SectionHeader(
            title: 'Yakında burada',
            subtitle: 'Bu ana sayfa hazırlanıyor.',
          ),
          AknLedger(
            children: [
              for (final (icon, title, text) in upcoming)
                AknListTile(title: title, subtitle: text, leadingIcon: icon),
            ],
          ),
        ],
      ),
    );
  }
}
