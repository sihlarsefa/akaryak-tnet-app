import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/splash/splash_screen.dart';
import '../../models/enums.dart';
import '../../utils/format.dart';
import '../../utils/tr_time.dart';
import '../ui.dart';

/// Living style guide (`/dev/gallery`, dev environment only).
///
/// Every component in light/dark, at 100 / 130 / 200 % text and with reduce
/// motion — the toggles in the app bar apply to the gallery only. Used for
/// the A-INT dark-mode and text-scale pass.
class DesignGalleryPage extends StatefulWidget {
  const DesignGalleryPage({super.key});

  @override
  State<DesignGalleryPage> createState() => _DesignGalleryPageState();
}

class _DesignGalleryPageState extends State<DesignGalleryPage> {
  Brightness? _brightness;
  double _scale = 1;
  bool _reduce = false;

  static const _tabs = [
    'Renkler',
    'Kahraman',
    'Yazı',
    'Butonlar',
    'Kartlar',
    'Durumlar',
    'Formlar',
    'Akış',
    'Geri bildirim',
    'Hareket',
    'Gezinme',
  ];

  @override
  Widget build(BuildContext context) {
    final appBrightness = Theme.of(context).brightness;
    final brightness = _brightness ?? appBrightness;
    final mq = MediaQuery.of(context);
    return Theme(
      data: AknTheme.of(brightness),
      child: MediaQuery(
        data: mq.copyWith(
          textScaler: TextScaler.linear(_scale),
          disableAnimations: _reduce || mq.disableAnimations,
        ),
        child: DefaultTabController(
          length: _tabs.length,
          child: Builder(
            builder: (context) => AppScaffold(
              title: 'Tasarım galerisi',
              subtitle: 'Yalnızca geliştirme ortamı',
              showBell: false,
              actions: [
                AknIconButton(
                  icon: brightness == Brightness.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  semanticLabel: brightness == Brightness.dark
                      ? 'Açık temaya geç'
                      : 'Koyu temaya geç',
                  onPressed: () => setState(
                    () => _brightness = brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                  ),
                ),
                AknIconButton(
                  icon: Icons.format_size_rounded,
                  semanticLabel: 'Yazı boyutu ${(_scale * 100).round()}',
                  onPressed: () => setState(
                    () => _scale = _scale == 1
                        ? 1.3
                        : _scale == 1.3
                        ? 2
                        : 1,
                  ),
                ),
                AknIconButton(
                  icon: _reduce
                      ? Icons.motion_photos_off_rounded
                      : Icons.motion_photos_on_rounded,
                  semanticLabel: _reduce ? 'Hareketi aç' : 'Hareketi azalt',
                  onPressed: () => setState(() => _reduce = !_reduce),
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final t in _tabs) Tab(text: t)],
              ),
              body: const TabBarView(
                children: [
                  _ColorsTab(),
                  _HeroTab(),
                  _TypeTab(),
                  _ButtonsTab(),
                  _CardsTab(),
                  _StatusTab(),
                  _FormsTab(),
                  _FlowTab(),
                  _FeedbackTab(),
                  _MotionTab(),
                  _NavTab(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      children: children,
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SectionHeader(
    title: text,
    padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
  );
}

// ───────────────────────── Renkler ─────────────────────────

class _ColorsTab extends StatelessWidget {
  const _ColorsTab();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final swatches = <(String, Color, Color)>[
      ('brandBright', c.brandBright, const Color(0xFFFFFFFF)),
      ('brand', c.brand, c.onBrandFill),
      ('brandFill', c.brandFill, c.onBrandFill),
      ('brandInk', c.brandInk, c.surface),
      ('brandSoft', c.brandSoft, c.brandInk),
      ('brandLine', c.brandLine, c.brandInk),
      ('heroStart', c.heroStart, c.onHero),
      ('heroEnd', c.heroEnd, c.onHero),
      ('bg', c.bg, c.ink),
      ('surface', c.surface, c.ink),
      ('surfaceAlt', c.surfaceAlt, c.ink),
      ('ink', c.ink, c.surface),
      ('text', c.text, c.surface),
      ('dim', c.dim, c.surface),
      ('faint', c.faint, c.surface),
      ('line', c.line, c.ink),
      ('lineStrong', c.lineStrong, c.ink),
    ];
    return _Page(
      children: [
        const _H('Belirteçler'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (name, bg, fg) in swatches)
              Container(
                width: 104,
                height: 64,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: AknRadius.chip,
                  border: Border.all(color: c.line),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const _H('Tonlar'),
        for (final tone in AknTone.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 72, child: Text(tone.name)),
                StatusChip(
                  label: 'Yumuşak',
                  tone: tone,
                  icon: AknStatus.toneIcon(tone),
                ),
                const SizedBox(width: 8),
                StatusChip(
                  label: 'Dolu',
                  tone: tone,
                  icon: AknStatus.toneIcon(tone),
                  solid: true,
                ),
              ],
            ),
          ),
        const _H('Kahraman gradyanı'),
        for (final style in AknHeroStyle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: AknRadius.card,
              child: SizedBox(
                height: 64,
                child: AknHeroBackground(
                  style: style,
                  child: Center(
                    child: Text(
                      style == AknHeroStyle.panel
                          ? 'Panel (sağ üstten ışık)'
                          : 'Şerit (sağdan ışık)',
                      style: context.aknText.bodyStrong.copyWith(
                        color: c.onHero,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ───────────────────────── Kahraman ─────────────────────────

class _HeroTab extends StatefulWidget {
  const _HeroTab();

  @override
  State<_HeroTab> createState() => _HeroTabState();
}

class _HeroTabState extends State<_HeroTab> {
  int _replay = 0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        // The header block as it sits under `AppScaffold(hero: true)`.
        AknHeroHeader(
          key: ValueKey('header$_replay'),
          title: 'Günaydın, Ayşe',
          subtitle: 'Demo Petrol · Kartal',
          trailing: const AknAvatar(name: 'Ayşe Demir', size: 44),
          chips: const [
            AknHeroChip(label: 'Sahip', icon: Icons.verified_user_rounded),
            AknHeroChip(label: 'Finans'),
            AknHeroChip(label: '3 teklif bekliyor'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _H('Kahraman paneli (durum kartı)'),
              AknHeroPanel(
                key: ValueKey('panel$_replay'),
                child: Builder(
                  builder: (context) {
                    final t = context.aknText;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('SP-2026-0142', style: t.title),
                            StatusChip.style(
                              OrderStatus.awaitingApproval.statusStyle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Motorin · 12.500 L', style: t.headline),
                        const SizedBox(height: 4),
                        Text(
                          'Demo Petrol · Verildi 21.10.2026 09:12',
                          style: t.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        AnimatedNumber(
                          value: 538120.5,
                          format: Fmt.money,
                          style: t.numberLarge,
                          fit: true,
                        ),
                        const SizedBox(height: 14),
                        const KpiRow(
                          children: [
                            KpiTile(
                              label: 'Karar bekleyen',
                              value: 3,
                              icon: Icons.request_quote_rounded,
                              tone: AknTone.warn,
                            ),
                            KpiTile(
                              label: 'Bu ay',
                              value: 512000,
                              format: Fmt.liters,
                              icon: Icons.local_gas_station_rounded,
                              tone: AknTone.info,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        AknButton(
                          label: 'Sipariş ver',
                          icon: Icons.add_shopping_cart_rounded,
                          size: AknButtonSize.large,
                          expand: true,
                          onPressed: () {},
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: AknButton.secondary(
                                label: 'Yol tarifi',
                                icon: Icons.directions_rounded,
                                expand: true,
                                onPressed: () {},
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AknButton.ghost(
                                label: 'Ayrıntı',
                                expand: true,
                                onPressed: () {},
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const UsageBar(
                          value: 0.73,
                          label: 'Limit kullanımı',
                          valueLabel: '%73',
                        ),
                      ],
                    );
                  },
                ),
              ),
              const _H('Kahraman başlıklı sayfa'),
              AknButton.secondary(
                label: 'Kahraman sayfasını aç',
                icon: Icons.open_in_new_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const _HeroPage()),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: AknButton.outline(
                  label: 'Yeniden oynat',
                  icon: Icons.replay_rounded,
                  size: AknButtonSize.small,
                  onPressed: () => setState(() => _replay++),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `AppScaffold(hero: true)` + `AknHeroHeader` + white cards (home layout).
class _HeroPage extends StatelessWidget {
  const _HeroPage();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return AppScaffold(
      hero: true,
      showBell: false,
      titleWidget: const AknLogo(markSize: 28, onDark: true),
      actions: [
        AknIconButton(
          icon: Icons.notifications_none_rounded,
          semanticLabel: 'Bildirimler',
          badgeCount: 2,
          onPressed: () {},
        ),
      ],
      body: PullToRefresh(
        onRefresh: () =>
            Future<void>.delayed(const Duration(milliseconds: 900)),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const AknHeroHeader(
              title: 'Günaydın, Ayşe',
              subtitle: 'Demo Petrol · Kartal',
              chips: [
                AknHeroChip(label: 'Sahip'),
                AknHeroChip(label: 'Satış müdürü'),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: AknSpace.pagePadding,
              child: KpiRow(
                children: [
                  KpiTile(
                    label: 'Bu ay satış',
                    value: 21500000,
                    format: Fmt.moneyCompact,
                    icon: Icons.trending_up_rounded,
                    tone: AknTone.brand,
                    trend: 8.6,
                    caption: 'geçen aya göre',
                    onTap: () {},
                  ),
                  const KpiTile(
                    label: 'Satılan yakıt',
                    value: 512000,
                    format: Fmt.liters,
                    icon: Icons.local_gas_station_rounded,
                    tone: AknTone.info,
                  ),
                ],
              ),
            ),
            SectionHeader(
              title: 'Hızlı işlemler',
              actionLabel: 'Tümü',
              onAction: () {},
            ),
            Padding(
              padding: AknSpace.pagePadding,
              child: Row(
                children: [
                  for (final (icon, label) in const [
                    (Icons.request_quote_rounded, 'Teklif'),
                    (Icons.task_alt_rounded, 'Onaylar'),
                    (Icons.local_shipping_rounded, 'Sevkiyat'),
                    (Icons.groups_rounded, 'Cariler'),
                  ])
                    Expanded(
                      child: Column(
                        children: [
                          AknIconBox(icon: icon, tone: AknTone.brand, size: 52),
                          const SizedBox(height: 6),
                          Text(label, style: t.label),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < 6; i++)
              AknCard(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                onTap: () {},
                child: Text('Kart ${i + 1}', style: t.bodyStrong),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Yazı ─────────────────────────

class _TypeTab extends StatelessWidget {
  const _TypeTab();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return _Page(
      children: [
        const _H('Ölçek'),
        Text('Display 32/40', style: t.display),
        Text('Title 22/28 · Şişli İğdır', style: t.title),
        Text('Headline 18/24 · Teslimat', style: t.headline),
        Text('Body 15/22 · Siparişiniz finans onayına düştü.', style: t.body),
        Text('Body strong 15/22', style: t.bodyStrong),
        Text('Body small 13/18 · İkincil bilgi', style: t.bodySmall),
        Text('Label 13/18 w600', style: t.label),
        Text('Caption 12/16 · 21.10.2026 14:20', style: t.caption),
        Text('ÜST BAŞLIK · BUGÜN', style: t.overline),
        const _H('Sayılar (sayarak artar)'),
        const AnimatedNumber(value: 21500000, format: Fmt.moneyCompact),
        AnimatedNumber(value: 512000, format: Fmt.liters, style: t.numberLarge),
        const _H('Tutarlar (tabular)'),
        AmountText(Fmt.money(1234567.5), large: true),
        AmountText(Fmt.money(1111.11)),
        AmountText(Fmt.liters(12500)),
        AmountText(Fmt.unitPrice(42.1255)),
        const _H('Logo'),
        const AknLogo(markSize: 44),
        const SizedBox(height: 12),
        const AknHeroPanel(child: AknLogo(markSize: 44, onDark: true)),
        const SizedBox(height: 12),
        const Row(
          children: [
            LogoMark(size: 56),
            SizedBox(width: 16),
            OnHero(child: LogoMark(size: 56)),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────── Butonlar ─────────────────────────

class _ButtonsTab extends StatefulWidget {
  const _ButtonsTab();

  @override
  State<_ButtonsTab> createState() => _ButtonsTabState();
}

class _ButtonsTabState extends State<_ButtonsTab> {
  bool _loading = false;
  int _badge = 3;

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const _H('Türler'),
        AknButton(
          label: 'Sipariş ver',
          icon: Icons.add_rounded,
          onPressed: () {},
        ),
        const SizedBox(height: 8),
        AknButton.secondary(label: 'Revize iste', onPressed: () {}),
        const SizedBox(height: 8),
        AknButton.outline(label: 'Vazgeç', onPressed: () {}),
        const SizedBox(height: 8),
        AknButton.ghost(label: 'Tümünü gör', onPressed: () {}),
        const SizedBox(height: 8),
        AknButton.danger(label: 'Reddet', onPressed: () {}),
        const SizedBox(height: 8),
        const AknButton(label: 'Pasif', onPressed: null),
        const _H('Boyutlar'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AknButton(
              label: 'Küçük',
              size: AknButtonSize.small,
              onPressed: () {},
            ),
            AknButton(label: 'Orta', onPressed: () {}),
            AknButton(
              label: 'Büyük',
              size: AknButtonSize.large,
              onPressed: () {},
            ),
          ],
        ),
        const _H('Gönder, döner, onaylar'),
        AknButton(
          label: 'Teklifi gönder',
          expand: true,
          trailingIcon: Icons.send_rounded,
          onPressedAsync: () =>
              Future<void>.delayed(const Duration(milliseconds: 1400)),
        ),
        const SizedBox(height: 8),
        AknButton.secondary(
          label: _loading ? 'Yükleniyor' : 'Elle yükleme durumu',
          loading: _loading,
          onPressed: () async {
            setState(() => _loading = true);
            await Future<void>.delayed(const Duration(seconds: 2));
            if (mounted) setState(() => _loading = false);
          },
        ),
        const _H('İkon butonları ve rozetler'),
        Row(
          children: [
            AknIconButton(
              icon: Icons.notifications_none_rounded,
              semanticLabel: 'Bildirimler',
              badgeCount: _badge,
              onPressed: () => setState(() => _badge++),
            ),
            AknIconButton(
              icon: Icons.more_horiz_rounded,
              semanticLabel: 'Diğer',
              showDot: true,
              onPressed: () {},
            ),
            AknIconButton(
              icon: Icons.refresh_rounded,
              semanticLabel: 'Sıfırla',
              onPressed: () => setState(() => _badge = 0),
            ),
            const SizedBox(width: 16),
            const AknAvatar(name: 'Ahmet Yılmaz'),
            const SizedBox(width: 8),
            const AknAvatar(name: 'İpek Şahin'),
            const SizedBox(width: 8),
            const AknAvatar(name: 'Can Öz', size: 32),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────── Kartlar ─────────────────────────

class _CardsTab extends StatelessWidget {
  const _CardsTab();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return _Page(
      children: [
        const _H('KPI'),
        KpiRow(
          children: [
            KpiTile(
              label: 'Bekleyen teklif',
              value: 12,
              icon: Icons.request_quote_rounded,
              tone: AknTone.brand,
              trend: 8,
              caption: 'geçen haftaya göre',
              onTap: () {},
            ),
            const KpiTile(
              label: 'Bu ay harcama',
              value: 1845230.4,
              format: Fmt.moneyCompact,
              icon: Icons.insights_rounded,
              tone: AknTone.info,
              trend: -4.5,
              positiveIsGood: false,
            ),
          ],
        ),
        const _H('Kart'),
        AknCard(
          onTap: () {},
          semanticLabel: 'Sipariş SP-2026-0142',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('SP-2026-0142', style: t.bodyStrong)),
                  StatusChip.style(OrderStatus.awaitingApproval.statusStyle),
                ],
              ),
              const SizedBox(height: 6),
              Text('Motorin · 12.500 L · Kartal depo', style: t.bodySmall),
              const SizedBox(height: 10),
              // Wrap, not Row: the badge drops below the amount when the
              // text is large or the screen narrow.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  AmountText(Fmt.money(538120.5)),
                  CountdownBadge(
                    deadline: TrTime.now().add(const Duration(minutes: 95)),
                    start: TrTime.now().subtract(const Duration(hours: 2)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AknCard(
          accent: AknTone.danger,
          child: Text('Vadesi geçmiş tahsilat: 3 sipariş', style: t.bodyStrong),
        ),
        const _H('Liste satırı'),
        AknCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              AknListTile(
                leadingIcon: Icons.local_shipping_rounded,
                leadingTone: AknTone.brand,
                title: 'Yolda · 34 ABC 123',
                subtitle: 'Kartal depo – Tuzla şantiye',
                meta: '14:20',
                onTap: () {},
              ),
              const Divider(indent: 68),
              AknListTile(
                leading: const AknAvatar(name: 'Deniz Kaya'),
                title: 'Deniz Kaya',
                subtitle: 'Şoför · 2 aktif teslimat',
                onTap: () {},
              ),
            ],
          ),
        ),
        const _H('Bilgi satırları'),
        const AknCard(
          child: Column(
            children: [
              FactRow(label: 'Limit', value: '2.500.000,00 ₺'),
              FactRow(label: 'Kullanım', value: '%92', tone: AknTone.warn),
              FactRow(
                label: 'Risk sınıfı',
                value: 'D (yüksek risk)',
                tone: AknTone.danger,
              ),
              SizedBox(height: 8),
              UsageBar(
                value: 0.92,
                label: 'Limit kullanımı',
                valueLabel: '%92',
              ),
            ],
          ),
        ),
        const _H('Uyarılar'),
        const AknBanner(
          tone: AknTone.warn,
          title: 'Finans onayında',
          message: 'Siparişiniz finans ekibinin onayını bekliyor.',
        ),
        const SizedBox(height: 8),
        AknBanner(
          tone: AknTone.info,
          message: 'Çek görselini yükleyin; tahsilat hızlansın.',
          actionLabel: 'Fotoğraf çek',
          onAction: () {},
          onClose: () {},
        ),
        const SizedBox(height: 8),
        const AknBanner(
          tone: AknTone.danger,
          message: 'Bugünün Tüpraş fiyatı girilmedi.',
        ),
      ],
    );
  }
}

// ───────────────────────── Durumlar ─────────────────────────

class _StatusTab extends StatelessWidget {
  const _StatusTab();

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        for (final values in allCodedEnums) ...[
          _H(values.first.runtimeType.toString()),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in values) StatusChip.style(AknStatus.of(v)),
            ],
          ),
        ],
        const _H('Barem bandı'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in [
              'auto',
              'manager',
              'senior',
              'exception',
              'reject',
              'unknown',
            ])
              StatusChip.style(AknStatus.band(k)),
          ],
        ),
        const _H('Geri sayım'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CountdownBadge(
              deadline: TrTime.now().add(const Duration(hours: 26)),
            ),
            CountdownBadge(
              deadline: TrTime.now().add(const Duration(minutes: 80)),
              start: TrTime.now().subtract(const Duration(hours: 1)),
            ),
            CountdownBadge(
              deadline: TrTime.now().add(const Duration(minutes: 12)),
              start: TrTime.now().subtract(const Duration(hours: 1)),
            ),
            CountdownBadge(
              deadline: TrTime.now().subtract(const Duration(minutes: 1)),
            ),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────── Formlar ─────────────────────────

class _FormsTab extends StatefulWidget {
  const _FormsTab();

  @override
  State<_FormsTab> createState() => _FormsTabState();
}

class _FormsTabState extends State<_FormsTab> {
  DateTime? _date = TrTime.addDays(TrTime.todayStart(), 1);
  Set<String> _filters = {'pending'};
  String _segment = 'decision';
  String _method = 'cash';
  double? _liters;

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const _H('Arama'),
        SearchField(
          hint: 'Sipariş no, cari, ürün',
          trailing: AknIconButton(
            icon: Icons.tune_rounded,
            semanticLabel: 'Filtreler',
            onPressed: () {},
          ),
        ),
        const _H('Sekmeler ve filtreler'),
        AknSegmented<String>(
          margin: EdgeInsets.zero,
          value: _segment,
          onChanged: (v) => setState(() => _segment = v),
          segments: const [
            FilterOption(value: 'decision', label: 'Karar bekleyen', count: 3),
            FilterOption(value: 'active', label: 'Aktif'),
            FilterOption(value: 'history', label: 'Geçmiş'),
          ],
        ),
        const SizedBox(height: 12),
        FilterChips<String>(
          padding: EdgeInsets.zero,
          selected: _filters,
          multi: true,
          onChanged: (s) => setState(() => _filters = s),
          options: const [
            FilterOption(value: 'pending', label: 'Bekliyor', count: 4),
            FilterOption(value: 'overdue', label: 'Vadesi geçen', count: 1),
            FilterOption(
              value: 'cheque',
              label: 'Çek',
              icon: Icons.money_rounded,
            ),
            FilterOption(value: 'note', label: 'Senet'),
          ],
        ),
        const SizedBox(height: 8),
        FilterChips<String>(
          padding: EdgeInsets.zero,
          tonal: true,
          selected: _filters,
          multi: true,
          onChanged: (s) => setState(() => _filters = s),
          options: const [
            FilterOption(value: 'pending', label: 'İkincil filtre'),
            FilterOption(value: 'overdue', label: 'Vadesi geçen'),
          ],
        ),
        const _H('Alanlar'),
        const AknTextField(
          label: 'Teslim alan',
          hint: 'Ad Soyad',
          requiredMark: true,
          prefixIcon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 12),
        const MoneyField(label: 'Tutar', initialValue: 1234.56),
        const SizedBox(height: 12),
        const MoneyField.unitPrice(label: 'Teklif ₺/L'),
        const SizedBox(height: 12),
        LitersField(
          max: 12500,
          requiredValue: true,
          onChanged: (v) => setState(() => _liters = v),
        ),
        if (_liters != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Okunan: ${Fmt.liters(_liters)}',
              style: context.aknText.caption,
            ),
          ),
        const SizedBox(height: 12),
        DateField(
          label: 'Teslim tarihi',
          value: _date,
          onChanged: (d) => setState(() => _date = d),
        ),
        const SizedBox(height: 12),
        const PlateField(initialValue: '34abc123'),
        const _H('Seçim kartları'),
        for (final (code, title, sub, icon, tag) in [
          (
            'cash',
            'Havale / EFT',
            'Peşin, vade yok',
            Icons.account_balance_rounded,
            'Son kullanılan',
          ),
          ('cheque', 'Çek', '30–90 gün vade', Icons.money_rounded, null),
          ('dbs', 'DBS', 'Banka limitiyle', Icons.handshake_rounded, null),
        ])
          ChoiceCard(
            margin: const EdgeInsets.only(bottom: 8),
            title: title,
            subtitle: sub,
            leadingIcon: icon,
            tag: tag,
            selected: _method == code,
            onTap: () => setState(() => _method = code),
          ),
        const ChoiceCard(
          title: 'Kredi kartı',
          subtitle: 'Bu bayide kapalı',
          leadingIcon: Icons.credit_card_rounded,
          selected: false,
          onTap: null,
        ),
      ],
    );
  }
}

// ───────────────────────── Akış ─────────────────────────

class _FlowTab extends StatefulWidget {
  const _FlowTab();

  @override
  State<_FlowTab> createState() => _FlowTabState();
}

class _FlowTabState extends State<_FlowTab> {
  int _step = 1;
  double _progress = 0.35;

  @override
  Widget build(BuildContext context) {
    const steps = ['Ürün ve litre', 'Teslimat', 'Ödeme', 'Özet'];
    return _Page(
      children: [
        const _H('Sihirbaz başlığı'),
        StepperHeader(
          padding: EdgeInsets.zero,
          steps: steps,
          current: _step,
          onStepTap: (i) => setState(() => _step = i),
        ),
        const SizedBox(height: 8),
        SharedAxisSwitcher(
          child: AknCard(
            key: ValueKey(_step),
            child: Text('Adım içeriği: ${steps[_step]}'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            AknButton.secondary(
              label: 'Geri',
              onPressed: _step == 0 ? null : () => setState(() => _step--),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AknButton(
                label: 'Devam',
                expand: true,
                onPressed: _step == steps.length - 1
                    ? null
                    : () => setState(() => _step++),
              ),
            ),
          ],
        ),
        const _H('Zaman çizelgesi'),
        const StepTimeline(
          steps: [
            TimelineStep(
              title: 'Sipariş oluşturuldu',
              time: '20.10 09:12',
              state: TimelineState.done,
            ),
            TimelineStep(
              title: 'Teklif onaylandı',
              subtitle: '42,1250 ₺/L',
              time: '20.10 11:40',
              state: TimelineState.done,
            ),
            TimelineStep(
              title: 'Sevkiyat planlandı',
              time: '21.10 08:00',
              state: TimelineState.current,
              content: PlateBadge(plate: '34ABC123', fontSize: 12),
            ),
            TimelineStep(title: 'Yola çıktı'),
            TimelineStep(title: 'Teslim edildi'),
          ],
        ),
        const _H('Belgeler'),
        const AttachmentTile(
          fileName: 'cek-0142.jpg',
          kindLabel: 'Çek görseli',
          sizeBytes: 812000,
          contentType: 'image/jpeg',
          state: AttachmentTileState.uploading,
          progress: 0.62,
        ),
        const SizedBox(height: 8),
        AttachmentTile(
          fileName: 'vergi-levhasi.pdf',
          kindLabel: 'Vergi levhası',
          sizeBytes: 220000,
          state: AttachmentTileState.failed,
          onRetry: () {},
        ),
        const SizedBox(height: 8),
        AttachmentTile(
          fileName: 'irsaliye-5521.pdf',
          kindLabel: 'İrsaliye',
          subtitle: '21.10.2026 14:20',
          onTap: () {},
        ),
        const _H('Kaydırarak onayla'),
        SlideToConfirm(
          label: 'Kaydırarak yola çık',
          resetAfterDone: true,
          onConfirmed: () =>
              Future<void>.delayed(const Duration(milliseconds: 1200)),
        ),
        const SizedBox(height: 12),
        const SlideToConfirm(
          label: 'Önce litreyi girin',
          enabled: false,
          onConfirmed: _noop,
        ),
        const _H('Rota ve yakıt'),
        const TruckRoute(
          moving: true,
          originLabel: 'Kartal depo',
          destinationLabel: 'Tuzla şantiye',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FuelDrop(fill: _progress, size: 56, flowing: true),
            const SizedBox(width: 16),
            Expanded(
              child: Slider(
                value: _progress,
                onChanged: (v) => setState(() => _progress = v),
              ),
            ),
          ],
        ),
        TruckRoute(progress: _progress),
      ],
    );
  }

  static void _noop() {}
}

// ───────────────────────── Geri bildirim ─────────────────────────

class _FeedbackTab extends StatefulWidget {
  const _FeedbackTab();

  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  bool _offline = true;
  int _pending = 2;

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const _H('Bildirim (toast)'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AknButton.secondary(
              label: 'Başarılı',
              size: AknButtonSize.small,
              onPressed: () =>
                  AppToast.success('Teklif gönderildi', context: context),
            ),
            AknButton.secondary(
              label: 'Hata',
              size: AknButtonSize.small,
              onPressed: () => AppToast.forbidden(context: context),
            ),
            AknButton.secondary(
              label: 'Uyarı',
              size: AknButtonSize.small,
              onPressed: () => AppToast.warning(
                'Bağlantı yavaş; işlem sıraya alındı.',
                title: 'Çevrimdışı',
                context: context,
              ),
            ),
            AknButton.secondary(
              label: 'Bilgi',
              size: AknButtonSize.small,
              onPressed: () =>
                  AppToast.info('Yeni sürüm hazır.', context: context),
            ),
          ],
        ),
        const _H('Alt sayfa ve onay'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AknButton.secondary(
              label: 'Alt sayfa',
              size: AknButtonSize.small,
              onPressed: () => showAppSheet<void>(
                context: context,
                title: 'Sevkiyat planla',
                subtitle: 'Kalan 4.500 L',
                builder: (ctx) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const LitersField(max: 4500, requiredValue: true),
                    const SizedBox(height: 12),
                    const PlateField(),
                    const SizedBox(height: 16),
                    AknButton(
                      label: 'Planla',
                      expand: true,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
            ),
            AknButton.secondary(
              label: 'Onay sorusu',
              size: AknButtonSize.small,
              onPressed: () async {
                final ok = await showConfirmSheet(
                  context,
                  title: 'Sevkiyat iptal edilsin mi?',
                  message: 'Şoför bilgilendirilir. Bu işlem geri alınamaz.',
                  confirmLabel: 'İptal et',
                  destructive: true,
                );
                if (ok && context.mounted) {
                  AppToast.success('Sevkiyat iptal edildi', context: context);
                }
              },
            ),
            AknButton.secondary(
              label: 'Diyalog',
              size: AknButtonSize.small,
              onPressed: () => showAknDialog(
                context,
                title: 'Değişiklikler kaydedilmedi',
                message: 'Çıkarsanız girdiğiniz bilgiler silinir.',
                confirmLabel: 'Çık',
                destructive: true,
              ),
            ),
          ],
        ),
        const _H('Çevrimdışı şeridi'),
        OfflineBanner(offline: _offline, pendingCount: _pending, onTap: () {}),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => setState(() => _offline = !_offline),
              child: Text(_offline ? 'Çevrimiçi yap' : 'Çevrimdışı yap'),
            ),
            TextButton(
              onPressed: () => setState(() => _pending = _pending == 0 ? 2 : 0),
              child: const Text('Bekleyen işlemler'),
            ),
          ],
        ),
        const _H('Boş durum'),
        EmptyState(
          title: 'Karar bekleyen teklif yok',
          message: 'Yeni teklif gelince bildirim alırsınız.',
          illustration: AknIllustration.orders,
          actionLabel: 'Sipariş ver',
          onAction: () {},
        ),
        const _H('Sonuç'),
        AknCard(
          padding: EdgeInsets.zero,
          child: ResultView(
            title: 'Siparişiniz alındı',
            message: 'Teklif hazır olunca bildirim göndereceğiz.',
            details: const Column(
              children: [
                FactRow(label: 'Sipariş no', value: 'SP-2026-0142'),
                FactRow(label: 'Tahmini tutar', value: '538.120,50 ₺'),
              ],
            ),
            primaryLabel: 'Çek fotoğrafını yükle',
            onPrimary: () {},
            secondaryLabel: 'Siparişe git',
            onSecondary: () {},
          ),
        ),
        const SizedBox(height: 12),
        const AknCard(
          padding: EdgeInsets.zero,
          child: ResultView(
            tone: AknTone.danger,
            title: 'Sipariş gönderilemedi',
            message: 'Limitiniz bu tutar için yetersiz.',
          ),
        ),
        const _H('Hata durumu'),
        ErrorState(onRetry: () {}, traceId: '00-4bf92f3577b34da6'),
        ErrorState(offline: true, compact: true, onRetry: () {}),
        const _H('İskelet (ilk yükleme)'),
        const SizedBox(height: 260, child: SkeletonList(itemCount: 3)),
        const _H('Yükleniyor'),
        const SizedBox(
          height: 120,
          child: LoadingView(message: 'Siparişler getiriliyor'),
        ),
      ],
    );
  }
}

// ───────────────────────── Hareket ─────────────────────────

class _MotionTab extends StatefulWidget {
  const _MotionTab();

  @override
  State<_MotionTab> createState() => _MotionTabState();
}

class _MotionTabState extends State<_MotionTab> {
  int _replay = 0;
  double _ring = 0.66;

  Future<void> _refresh() =>
      Future<void>.delayed(const Duration(milliseconds: 1400));

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return _Page(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: AknButton.secondary(
            label: 'Yeniden oynat',
            icon: Icons.replay_rounded,
            size: AknButtonSize.small,
            onPressed: () => setState(() => _replay++),
          ),
        ),
        const _H('Logo çizimi ve başarı'),
        Row(
          key: ValueKey('marks$_replay'),
          children: [
            const LogoMark(size: 72, animate: true),
            const SizedBox(width: 24),
            const SuccessCheck(size: 72, haptic: false),
            const SizedBox(width: 24),
            ProgressRing(
              value: _ring,
              size: 64,
              strokeWidth: 6,
              animateFromZero: true,
              child: Text('%${(_ring * 100).round()}', style: t.captionStrong),
            ),
          ],
        ),
        Slider(value: _ring, onChanged: (v) => setState(() => _ring = v)),
        const _H('Yükleyici'),
        const Row(
          children: [
            ChevronSpinner(),
            SizedBox(width: 24),
            ChevronSpinner(size: 18, count: 2),
          ],
        ),
        const _H('Sayarak artan sayı'),
        Row(
          key: ValueKey('numbers$_replay'),
          children: [
            const Expanded(
              child: AnimatedNumber(
                value: 21500000,
                format: Fmt.moneyCompact,
                fit: true,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: AnimatedNumber(value: 42, format: (v) => '%$v')),
          ],
        ),
        const _H('Eğilim çizgisi'),
        Sparkline(
          key: ValueKey('spark$_replay'),
          values: const [42, 48, 45, 60, 58, 71, 69, 80],
          semanticLabel: 'Son 8 hafta harcama, artışta',
        ),
        const _H('Kademeli liste'),
        StaggerScope(
          key: ValueKey('stagger$_replay'),
          child: Column(
            children: staggered([
              for (var i = 0; i < 6; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AknCard(child: Text('Satır ${i + 1}')),
                ),
            ]),
          ),
        ),
        const _H('Kart → ayrıntı (container transform)'),
        AknOpenContainer<void>(
          closedBuilder: (context, open) => AknListTile(
            leadingIcon: Icons.receipt_long_rounded,
            leadingTone: AknTone.brand,
            title: 'SP-2026-0142',
            subtitle: 'Motorin · 12.500 L · Onay bekleniyor',
            onTap: open,
          ),
          openBuilder: (context, close) => AppScaffold(
            title: 'SP-2026-0142',
            showBell: false,
            leading: BackButton(onPressed: close),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                StatusChip.style(OrderStatus.awaitingApproval.statusStyle),
                const SizedBox(height: 12),
                const FactRow(label: 'Ürün', value: 'Motorin'),
                const FactRow(label: 'Litre', value: '12.500 L'),
              ],
            ),
          ),
        ),
        const _H('Aşağı çekip yenile'),
        SizedBox(
          height: 220,
          child: AknCard(
            padding: EdgeInsets.zero,
            child: PullToRefresh(
              onRefresh: _refresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 8,
                itemBuilder: (context, i) => AknListTile(
                  dense: true,
                  title: 'Teslimat ${i + 1}',
                  subtitle: 'Aşağı çekin',
                ),
              ),
            ),
          ),
        ),
        const _H('Açılış ekranı'),
        AknButton.secondary(
          label: 'Açılışı göster',
          onPressed: () => Navigator.of(context).push(
            PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              pageBuilder: (ctx, _, _) => _SplashPreview(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: SplashScreen(
        onFinished: () => Timer(const Duration(milliseconds: 1500), () {
          if (context.mounted) unawaited(Navigator.of(context).maybePop());
        }),
      ),
    );
  }
}

// ───────────────────────── Gezinme ─────────────────────────

class _NavTab extends StatefulWidget {
  const _NavTab();

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  int _a = 0;
  int _b = 1;
  int _approvals = 4;

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const _H('4 sekme + Diğer'),
        _NoInset(
          child: AnimatedBottomBar(
            currentIndex: _a,
            onSelected: (i) => setState(() => _a = i),
            items: [
              const AknNavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Ana sayfa',
              ),
              AknNavItem(
                icon: Icons.task_alt_rounded,
                label: 'Onaylarım',
                badgeCount: _approvals,
              ),
              const AknNavItem(
                icon: Icons.request_quote_outlined,
                label: 'Teklif masası',
              ),
              const AknNavItem(
                icon: Icons.receipt_long_outlined,
                label: 'Siparişler',
              ),
              const AknNavItem(
                icon: Icons.more_horiz_rounded,
                label: 'Diğer',
                showDot: true,
              ),
            ],
          ),
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => setState(() => _approvals++),
              child: const Text('Rozet +1'),
            ),
            TextButton(
              onPressed: () => setState(() => _approvals = 0),
              child: const Text('Rozeti sıfırla'),
            ),
          ],
        ),
        const _H('Orta eylem (çentik)'),
        const SizedBox(height: 8),
        _NoInset(
          child: AnimatedBottomBar(
            currentIndex: _b,
            onSelected: (i) => setState(() => _b = i),
            centerAction: AknCenterAction(
              icon: Icons.add_rounded,
              label: 'Sipariş ver',
              onPressed: () =>
                  AppToast.info('Sipariş sihirbazı açılır', context: context),
            ),
            items: const [
              AknNavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Ana sayfa',
              ),
              AknNavItem(
                icon: Icons.receipt_long_outlined,
                label: 'Siparişlerim',
              ),
              AknNavItem(
                icon: Icons.local_shipping_outlined,
                label: 'Teslimatlar',
              ),
              AknNavItem(icon: Icons.more_horiz_rounded, label: 'Diğer'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bar demos sit mid-page: drop the device's bottom inset.
class _NoInset extends StatelessWidget {
  const _NoInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.removePadding(
    context: context,
    removeBottom: true,
    child: child,
  );
}
