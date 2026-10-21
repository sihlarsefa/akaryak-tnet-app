import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/models/me_access.dart';
import '../../../../core/network/fake/fake_auth.dart';
import '../../../../core/network/fake/fake_personas.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';

/// Giriş ekranında demo hesapları gösterilir mi: yalnızca sahte API'nin derlendiği ve sahte kipte
/// açılan derlemelerde. Çağıran ayrıca `kFakeApiCompiled && …` ile korur; canlı derlemede bölüm ve
/// demo personaları derlemeye hiç girmez (ağaç sallama). Testler canlı kipi taklit etmek için ezer.
final demoLoginsEnabledProvider = Provider<bool>(
  (ref) => kFakeApiCompiled && ref.watch(appEnvProvider).isFake,
);

/// Demo hesabının tarafı (sahip kararı 2026-10-21: Müşteri / Bayi / Merkez).
enum DemoGroup {
  customer(AuthCopy.demoGroupCustomer),
  bayi(AuthCopy.demoGroupBayi),
  center(AuthCopy.demoGroupCenter);

  const DemoGroup(this.label);

  /// Grup başlığı ("Müşteri").
  final String label;
}

/// Persona avatarının rol tonu (mor yok): müşteri turuncu, yönetim asfalt, finans yeşil, satış
/// kehribar, operasyon mavi, diğer gri, merkez koyu.
enum DemoTone { orange, slate, green, amber, blue, grey, ink }

/// Bir demo hesabı: persona, grubu, kısa rol adı ve avatar tonu.
@immutable
class DemoAccount {
  const DemoAccount({
    required this.persona,
    required this.group,
    required this.role,
    required this.tone,
  });

  final FakePersona persona;
  final DemoGroup group;

  /// Kartta adın altındaki kısa rol ("Bayi sahibi").
  final String role;
  final DemoTone tone;

  String get key => persona.key;
  String get name => persona.displayName;

  /// "Tümünü gör" sayfasındaki açıklama: personanın özeti, grup öneki ve " · " olmadan.
  String get detail {
    var s = persona.summary.trim();
    final prefix = '${group.label} · ';
    if (s.startsWith(prefix)) s = s.substring(prefix.length);
    s = s.replaceAll(' · ', ', ');
    return _capitalize(s);
  }

  /// Ekran okuyucu: "Selin Aydın, Müşteri, Şirket yöneticisi".
  String get spoken => '$name, ${group.label}, $role';
}

/// Sıra ve roller (sahip kararındaki sırayla). Listede olmayan yeni bir persona türünden gruba girer
/// ve özetinden kısa bir rol adı alır.
const Map<String, (DemoGroup, String, DemoTone)> _known = {
  'musteri': (DemoGroup.customer, 'Şirket yöneticisi', DemoTone.orange),
  'onay': (DemoGroup.customer, 'Onaylayan', DemoTone.orange),
  'talep': (DemoGroup.customer, 'Talep eden', DemoTone.orange),
  'sahip': (DemoGroup.bayi, 'Bayi sahibi', DemoTone.slate),
  'mudur': (DemoGroup.bayi, 'Bayi müdürü', DemoTone.slate),
  'finans': (DemoGroup.bayi, 'Finans müdürü', DemoTone.green),
  'finansuzman': (DemoGroup.bayi, 'Finans uzmanı', DemoTone.green),
  'muhasebe': (DemoGroup.bayi, 'Muhasebe', DemoTone.green),
  'satis': (DemoGroup.bayi, 'Satış müdürü', DemoTone.amber),
  'saha': (DemoGroup.bayi, 'Saha satış', DemoTone.amber),
  'siparis': (DemoGroup.bayi, 'Sipariş masası', DemoTone.blue),
  'sevkiyat': (DemoGroup.bayi, 'Sevkiyat', DemoTone.blue),
  'sofor': (DemoGroup.bayi, 'Şoför', DemoTone.blue),
  'depo': (DemoGroup.bayi, 'Depo', DemoTone.blue),
  'izleyici': (DemoGroup.bayi, 'Görüntüleyici', DemoTone.grey),
  'ozelrol': (DemoGroup.bayi, 'Özel rol', DemoTone.grey),
  'merkez': (DemoGroup.center, 'Genel merkez', DemoTone.ink),
};

String _capitalize(String s) =>
    s.isEmpty ? s : '${TurkishText.upper(s.substring(0, 1))}${s.substring(1)}';

DemoAccount _accountFor(FakePersona p) {
  final known = _known[p.key];
  if (known != null) {
    final (group, role, tone) = known;
    return DemoAccount(persona: p, group: group, role: role, tone: tone);
  }
  final group = switch (p.persona) {
    Persona.customer => DemoGroup.customer,
    Persona.platform => DemoGroup.center,
    _ => DemoGroup.bayi,
  };
  // "Müşteri · talep eden (…)" → "Talep eden".
  final role = _capitalize(
    p.summary.split(' (').first.split(' · ').last.trim(),
  );
  return DemoAccount(
    persona: p,
    group: group,
    role: role.isEmpty ? group.label : role,
    tone: switch (group) {
      DemoGroup.customer => DemoTone.orange,
      DemoGroup.center => DemoTone.ink,
      DemoGroup.bayi => DemoTone.grey,
    },
  );
}

/// Demo hesapları grup ve rol sırasıyla (Müşteri, Bayi, Merkez). [personas] verilmezse sahte
/// sunucunun tüm personaları.
List<DemoAccount> demoAccounts([List<FakePersona>? personas]) {
  final source = personas ?? fakePersonas;
  final order = _known.keys.toList();
  final indexed = [
    for (var i = 0; i < source.length; i++) (i, _accountFor(source[i])),
  ];
  int rank(DemoAccount a) {
    final i = order.indexOf(a.key);
    return i < 0 ? order.length : i;
  }

  indexed.sort((a, b) {
    final g = a.$2.group.index.compareTo(b.$2.group.index);
    if (g != 0) return g;
    final r = rank(a.$2).compareTo(rank(b.$2));
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// G kart dili: beyaz kart, 1 px #F1E3D8 kenar, r16, yumuşak gölge (koyu temada yüzey + ince
/// turuncumsu kenar, gölge yok).
abstract final class _DemoStyle {
  static const radius = BorderRadius.all(Radius.circular(16));
  static const borderLight = Color(0xFFF1E3D8);
  static const borderDark = Color(0xFF3A2D24);
  static const shadow = [
    BoxShadow(color: Color(0x12101828), blurRadius: 12, offset: Offset(0, 3)),
  ];

  /// Kart satırının üst / alt payı: gölge kaydırma alanının kırpma kenarına değmez.
  static const rowPadding = EdgeInsets.fromLTRB(
    AknSpace.page,
    6,
    AknSpace.page,
    18,
  );

  /// (zemin, yazı) — açık / koyu; harfler zeminde en az 4,5:1.
  static (Color, Color) tone(DemoTone tone, {required bool dark}) => switch ((
    tone,
    dark,
  )) {
    (DemoTone.orange, false) => (
      const Color(0xFFFFE6D6),
      const Color(0xFF9A3412),
    ),
    (DemoTone.orange, true) => (
      const Color(0xFF3A2116),
      const Color(0xFFFFB088),
    ),
    (DemoTone.slate, false) => (
      const Color(0xFFE4E7EB),
      const Color(0xFF1E2227),
    ),
    (DemoTone.slate, true) => (
      const Color(0xFF2E333A),
      const Color(0xFFE6E8EB),
    ),
    (DemoTone.green, false) => (
      const Color(0xFFDDF3E6),
      const Color(0xFF146C43),
    ),
    (DemoTone.green, true) => (
      const Color(0xFF15301F),
      const Color(0xFF7FD6A4),
    ),
    (DemoTone.amber, false) => (
      const Color(0xFFFCEFD2),
      const Color(0xFF8A4B00),
    ),
    (DemoTone.amber, true) => (
      const Color(0xFF3A2C10),
      const Color(0xFFF5C46B),
    ),
    (DemoTone.blue, false) => (
      const Color(0xFFE1EAFB),
      const Color(0xFF1D4AB4),
    ),
    (DemoTone.blue, true) => (const Color(0xFF172540), const Color(0xFF9DBBF5)),
    (DemoTone.grey, false) => (
      const Color(0xFFF0F1F3),
      const Color(0xFF4A5159),
    ),
    (DemoTone.grey, true) => (const Color(0xFF262A30), const Color(0xFFB4BAC2)),
    (DemoTone.ink, false) => (const Color(0xFF1E2227), const Color(0xFFFFFFFF)),
    (DemoTone.ink, true) => (const Color(0xFFF1F2F4), const Color(0xFF16191D)),
  };
}

/// Rol tonunda baş harfli yuvarlak avatar (yazı ölçeğiyle büyümez).
class DemoAvatar extends StatelessWidget {
  const DemoAvatar({super.key, required this.account, this.size = 36});

  final DemoAccount account;
  final double size;

  /// Kartta yazı büyüdükçe avatar da biraz büyür (1,0× 36 → 2,0× 50).
  static double scaled(BuildContext context, [double base = 36]) {
    final s = MediaQuery.textScalerOf(context).scale(15) / 15;
    return (base + (s - 1) * 14).clamp(base, base + 14);
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _DemoStyle.tone(account.tone, dark: context.akn.isDark);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          TurkishText.initials(account.name),
          textScaler: TextScaler.noScaling,
          maxLines: 1,
          style: TextStyle(
            fontFamily: AknFonts.sans,
            fontSize: size * 0.4,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: fg,
            locale: AknFonts.locale,
          ),
        ),
      ),
    );
  }
}

/// Giriş ekranındaki demo bölümü (sahip kararı 2026-10-21 20:22): "Demo hesaplarıyla girin",
/// "Tümünü gör", tek satır ipucu (şifre `demo`, kod `123456`) ve Müşteri / Bayi / Merkez gruplarında
/// yatay kaydırılan persona kartları. Bir karta dokunmak o hesapla giriş yapar ([onSelected]).
class DemoAccountsSection extends StatelessWidget {
  const DemoAccountsSection({
    super.key,
    required this.onSelected,
    this.onSeeAll,
    this.busyKey,
    this.enabled = true,
    this.accounts,
    this.singleRow = false,
  });

  final ValueChanged<FakePersona> onSelected;

  /// Tüm hesaplar tek yatay satırda (Müşteri, Bayi, Merkez sırasıyla; grup başlığı yok — avatar
  /// tonu tarafı gösterir).
  final bool singleRow;

  /// "Tümünü gör": tüm hesaplar açıklamalarıyla bir sayfada; null ise bağlantı yok.
  final VoidCallback? onSeeAll;

  /// Giriş yapılan hesabın anahtarı: kartında ilerleme göstergesi.
  final String? busyKey;

  /// Bir giriş sürerken kartlar dokunmaya kapanır.
  final bool enabled;

  /// Testler için; null ise [demoAccounts].
  final List<DemoAccount>? accounts;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final all = accounts ?? demoAccounts();
    final large = MediaQuery.textScalerOf(context).scale(16) > 22;
    final title = Semantics(
      header: true,
      child: Text(
        AuthCopy.demoSectionTitle,
        style: t.headline.copyWith(color: c.ink),
      ),
    );
    final seeAll = onSeeAll == null
        ? null
        : AknInlineLink(
            label: AuthCopy.demoSeeAll,
            onTap: onSeeAll!,
            style: t.label.copyWith(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          );
    final strong = t.bodySmall.copyWith(
      fontWeight: FontWeight.w600,
      color: c.ink,
    );
    // "Tek dokunuşla giriş. Şifre demo, kod 123456." (değerler kalın).
    final hint = Text.rich(
      TextSpan(
        style: t.bodySmall.copyWith(color: c.dim),
        children: [
          const TextSpan(text: '${AuthCopy.demoTapHint} Şifre '),
          TextSpan(text: FakeAuth.password, style: strong),
          const TextSpan(text: ', kod '),
          TextSpan(text: FakeAuth.code, style: strong),
          const TextSpan(text: '.'),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AknSpace.page),
          child: large || seeAll == null
              ? title
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    seeAll,
                  ],
                ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AknSpace.page,
            large || seeAll == null ? 4 : 0,
            AknSpace.page,
            0,
          ),
          child: hint,
        ),
        if (large && seeAll != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AknSpace.page),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: seeAll,
            ),
          ),
        if (singleRow) ...[
          const SizedBox(height: 12),
          _CardRow(
            accounts: all,
            busyKey: busyKey,
            enabled: enabled,
            onSelected: onSelected,
          ),
        ] else
          for (final (i, (group, list)) in demoGroups(all).indexed) ...[
            // Önceki kart satırının altında gölge payı (18) var: sonraki başlık yakın durur.
            Padding(
              padding: EdgeInsets.fromLTRB(
                AknSpace.page,
                i == 0 ? 14 : 4,
                AknSpace.page,
                0,
              ),
              child: _GroupLabel(group),
            ),
            _CardRow(
              accounts: list,
              busyKey: busyKey,
              enabled: enabled,
              onSelected: onSelected,
            ),
          ],
      ],
    );
  }
}

/// Hesapları gruplarına ayırır (boş grup yok; sıra Müşteri, Bayi, Merkez).
List<(DemoGroup, List<DemoAccount>)> demoGroups(List<DemoAccount> accounts) => [
  for (final g in DemoGroup.values)
    if (accounts.where((a) => a.group == g).toList() case final list
        when list.isNotEmpty)
      (g, list),
];

/// Grup başlığı ("Müşteri"): 13/18 600 soluk.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.group);

  final DemoGroup group;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        group.label,
        style: context.aknText.label.copyWith(
          fontWeight: FontWeight.w600,
          color: context.akn.dim,
        ),
      ),
    );
  }
}

/// Bir grubun kartları: sayfa kenarına kadar yatay kayar (ilk ve son kart sayfa boşluğunda durur),
/// kartlar aynı yükseklikte; yanındaki kartın ucu görünür.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.accounts,
    required this.busyKey,
    required this.enabled,
    required this.onSelected,
  });

  final List<DemoAccount> accounts;
  final String? busyKey;
  final bool enabled;
  final ValueChanged<FakePersona> onSelected;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 1,0×'de 188 dp; yazı büyüdükçe genişler, ama yanındaki kartın ucu hep görünür.
        final room = constraints.maxWidth - 2 * AknSpace.page - 28;
        final width = math.max(188.0, math.min(188 + (scale - 1) * 120, room));
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: _DemoStyle.rowPadding,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < accounts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  SizedBox(
                    width: width,
                    child: DemoPersonaCard(
                      account: accounts[i],
                      busy: busyKey == accounts[i].key,
                      onTap: enabled
                          ? () => onSelected(accounts[i].persona)
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Persona kartı (G kart dili): rol tonunda baş harf avatarı, ad (600) ve rol (500, soluk). Dokunmak
/// giriş yapar; giriş sürerken sağda ilerleme göstergesi.
class DemoPersonaCard extends StatelessWidget {
  const DemoPersonaCard({
    super.key,
    required this.account,
    required this.onTap,
    this.busy = false,
  });

  final DemoAccount account;

  /// Null: dokunmaya kapalı (başka bir giriş sürüyor).
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final dark = c.isDark;
    final shape = RoundedRectangleBorder(
      borderRadius: _DemoStyle.radius,
      side: BorderSide(
        color: dark ? _DemoStyle.borderDark : _DemoStyle.borderLight,
      ),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: account.spoken,
      hint: busy ? AuthCopy.loggingIn : AuthCopy.demoCardHint,
      excludeSemantics: true,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _DemoStyle.radius,
          boxShadow: dark ? null : _DemoStyle.shadow,
        ),
        child: Material(
          color: dark ? c.surface : const Color(0xFFFFFFFF),
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AknSpace.minTap),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    DemoAvatar(
                      account: account,
                      size: DemoAvatar.scaled(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            account.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyStrong.copyWith(
                              height: 20 / 15,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            account.role,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.label.copyWith(
                              fontWeight: FontWeight.w500,
                              color: c.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (busy) ...[
                      const SizedBox(width: 8),
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.brand,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Kendi hesabınızla girin": demo kartları ile giriş formu arasındaki ayraç (iki yanda ince çizgi).
class OwnAccountDivider extends StatelessWidget {
  const OwnAccountDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    Widget line() => Expanded(
      child: SizedBox(height: 1, child: ColoredBox(color: c.line)),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          line(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(0, constraints.maxWidth - 2 * (12 + 24)),
              ),
              // Kısa ayraç: en çok 1,5× büyür, iki yanındaki çizgilerle tek satırda kalır.
              child: Semantics(
                header: true,
                child: Text(
                  AuthCopy.ownAccountDivider,
                  textAlign: TextAlign.center,
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.5),
                  style: t.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.dim,
                  ),
                ),
              ),
            ),
          ),
          line(),
        ],
      ),
    );
  }
}

/// "Tümünü gör" sayfası: tüm demo hesapları gruplarıyla, personanın açıklamasıyla defter satırları.
class DemoAccountsList extends StatelessWidget {
  const DemoAccountsList({super.key, required this.onSelected, this.accounts});

  final ValueChanged<FakePersona> onSelected;

  /// Testler için; null ise [demoAccounts].
  final List<DemoAccount>? accounts;

  @override
  Widget build(BuildContext context) {
    final groups = demoGroups(accounts ?? demoAccounts());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              AknSpace.page,
              i == 0 ? 4 : 16,
              AknSpace.page,
              4,
            ),
            child: _GroupLabel(groups[i].$1),
          ),
          AknLedger(
            children: [
              for (final a in groups[i].$2)
                AknListTile(
                  leading: DemoAvatar(account: a, size: 40),
                  title: a.name,
                  subtitle: a.detail,
                  titleMaxLines: 1,
                  showChevron: true,
                  semanticLabel: '${a.name}, ${a.detail}',
                  onTap: () => onSelected(a.persona),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
