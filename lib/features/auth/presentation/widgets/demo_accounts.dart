import 'dart:async';
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

/// Persona avatarının rol tonu (tasarım v3 jetonlarından; mavi ve mor yok): müşteri yumuşak turuncu,
/// yönetim grafit kuyu, finans yeşil, satış koyu sarı, operasyon (`blue`, adı API için korunur) koyu
/// grafit, diğer gri, merkez (`ink`) marka turuncusu. Harfler zeminde en az 4,5:1.
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

/// Kart satırının üst / alt payı: gölge kaydırma alanının kırpma kenarına değmez.
const EdgeInsets _rowPadding = EdgeInsets.fromLTRB(
  AknSpace.page,
  6,
  AknSpace.page,
  18,
);

/// (zemin, harf) — v3 jetonlarından; açık ve koyu temada harfler zeminde en az 4,5:1.
(Color, Color) _toneColors(DemoTone tone, AknColors c) => switch (tone) {
  DemoTone.orange => (c.brandSoft, c.brandInk),
  DemoTone.slate => (c.surfaceAlt, c.ink),
  DemoTone.green => (c.ok.bg, c.ok.fg),
  DemoTone.amber => (c.warn.bg, c.warn.fg),
  DemoTone.blue => (c.inverse, c.onInverse),
  DemoTone.grey => (c.neutral.bg, c.neutral.fg),
  DemoTone.ink => (c.brandFillPressed, c.onBrandFill),
};

/// Rol tonunda baş harfli yuvarlak avatar (yazı ölçeğiyle büyümez): yumuşak tonlu dairede kalın (800)
/// baş harfler; koyu zeminlerde (operasyon, merkez) beyaz harfler.
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
    final c = context.akn;
    final (bg, fg) = _toneColors(account.tone, c);
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
          style: context.aknText.label.copyWith(
            fontSize: size * 0.38,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// Giriş ekranındaki demo bölümü (sahip kararı 2026-10-21 20:22): "Demo hesaplarıyla girin",
/// "Tümünü gör", tek satır ipucu (şifre `demo`, kod `123456`) ve yatay kaydırılan persona kartları. Bir
/// karta dokunmak o hesapla giriş yapar ([onSelected]). Kartlar açılışta sağdan sırayla "dağıtılır".
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

  /// Giriş yapılan hesabın anahtarı: kartında ilerleme halkası.
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
    final seeAll = onSeeAll == null ? null : _SeeAllLink(onTap: onSeeAll!);
    final strong = t.bodySmall.copyWith(
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    // "Tek dokunuşla giriş. Şifre demo, kod 123456." (değerler kalın, rakamlar eş genişlikte).
    final hint = Text.rich(
      TextSpan(
        style: t.bodySmall.copyWith(color: c.dim),
        children: [
          const TextSpan(text: '${AuthCopy.demoTapHint} Şifre '),
          TextSpan(text: FakeAuth.password, style: strong),
          const TextSpan(text: ', kod '),
          TextSpan(
            text: FakeAuth.code,
            style: strong.copyWith(fontFeatures: AknNumerals.tabular),
          ),
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
            // Önceki kart satırının altında gölge payı (20) var: sonraki başlık yakın durur.
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

/// "Tümünü gör ›" (v3 bölüm bağlantısı): ink 14/20 600, altı çizili, küçük ok; 48 dp hedef.
class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      link: true,
      button: true,
      label: AuthCopy.demoSeeAll,
      excludeSemantics: true,
      onTap: onTap,
      child: PressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AknSpace.minTap,
              minWidth: AknSpace.minTap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AuthCopy.demoSeeAll,
                  style: t.label.copyWith(
                    fontSize: 14,
                    height: 20 / 14,
                    color: c.link,
                    decoration: TextDecoration.underline,
                    decorationColor: c.link,
                    decorationThickness: 1.4,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(PhosphorIconsBold.caretRight, size: 14, color: c.ink),
              ],
            ),
          ),
        ),
      ),
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

/// Grup başlığı ("Müşteri"): 12/16 700 soluk.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.group);

  final DemoGroup group;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        group.label,
        style: context.aknText.captionStrong.copyWith(color: context.akn.dim),
      ),
    );
  }
}

/// Kartlar: sayfa kenarına kadar yatay kayar (ilk ve son kart sayfa boşluğunda durur), hepsi aynı
/// yükseklikte; yanındaki kartın ucu görünür. Açılışta kartlar sağdan sırayla kayarak gelir.
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
          clipBehavior: Clip.none,
          padding: _rowPadding,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < accounts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  SizedBox(
                    width: width,
                    child: _DealIn(
                      index: i,
                      child: DemoPersonaCard(
                        account: accounts[i],
                        busy: busyKey == accounts[i].key,
                        onTap: enabled
                            ? () => onSelected(accounts[i].persona)
                            : null,
                      ),
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

/// Kartın açılış hareketi: [index] sırasıyla (45 ms arayla) sağdan 40 px kayarak ve hızla belirerek
/// gelir. Ölçek yok, yapı sabit; azaltılmış harekette doğrudan çizilir.
class _DealIn extends StatefulWidget {
  const _DealIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_DealIn> createState() => _DealInState();
}

class _DealInState extends State<_DealIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  static final _move = CurveTween(curve: AknMotion.emphasizedCurve);
  static final _fade = CurveTween(
    curve: const Interval(0, 0.35, curve: Curves.easeOut),
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
      return;
    }
    // Sayfa yükselirken başlar; ekran dışındaki kartlar da aynı sırayla gelir.
    final delay = Duration(milliseconds: 120 + 45 * widget.index.clamp(0, 7));
    _timer = Timer(delay, () {
      if (mounted) unawaited(_c.forward());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _fade.evaluate(_c),
      child: Transform.translate(
        offset: Offset(40 * (1 - _move.evaluate(_c)), 0),
        child: child,
      ),
    ),
  );
}

/// Persona kartı (tasarım v3): beyaz kart (r20, yumuşak kart gölgesi; koyu temada ince çizgi), rol
/// tonunda baş harf avatarı, ad (700) ve rol (500, soluk). Basınca %96'ya iner ve yaylanarak döner;
/// dokunmak giriş yapar. Giriş sürerken avatarın çevresinde turuncu bir halka döner ve kart turuncu
/// çizgi alır; başka bir giriş sürerken kart soluklaşır.
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
    final duration = AknMotion.of(context, AknMotion.base);
    final avatar = DemoAvatar.scaled(context, 40);
    final radius = AknRadius.card;
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: account.spoken,
      hint: busy ? AuthCopy.loggingIn : AuthCopy.demoCardHint,
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null && !busy ? 0.55 : 1,
        duration: duration,
        child: PressScale(
          enabled: onTap != null,
          scale: 0.96,
          child: AnimatedContainer(
            duration: duration,
            curve: AknMotion.standard,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: radius,
              border: busy
                  ? Border.all(color: c.brand, width: 1.5)
                  : c.isDark
                  ? Border.all(color: c.line)
                  : Border.all(color: c.surface.withValues(alpha: 0)),
              boxShadow: AknShadows.card(c),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                splashFactory: NoSplash.splashFactory,
                highlightColor: c.surfaceAlt.withValues(alpha: 0.7),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AknSpace.minTap),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: avatar,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              DemoAvatar(account: account, size: avatar),
                              if (busy)
                                Positioned(
                                  left: -4,
                                  top: -4,
                                  right: -4,
                                  bottom: -4,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    strokeCap: StrokeCap.round,
                                    color: c.brand,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
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
                                  fontWeight: FontWeight.w700,
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Kendi hesabınızla girin": demo kartları ile giriş formu arasındaki ayraç (iki yanda incelen çizgi).
class OwnAccountDivider extends StatelessWidget {
  const OwnAccountDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    Widget line({required bool fadeStart}) => Expanded(
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: fadeStart
                ? [c.line.withValues(alpha: 0), c.line]
                : [c.line, c.line.withValues(alpha: 0)],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          line(fadeStart: true),
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
                  style: t.label.copyWith(color: c.dim),
                ),
              ),
            ),
          ),
          line(fadeStart: false),
        ],
      ),
    );
  }
}

/// "Tümünü gör" sayfası: tüm demo hesapları gruplarıyla, personanın açıklamasıyla satırlar; gruplar
/// sırayla belirir.
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
              i == 0 ? 4 : 18,
              AknSpace.page,
              6,
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
