import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/splash/splash_screen.dart';
import '../../models/enums.dart';
import '../../utils/format.dart';
import '../../utils/tr_time.dart';
import '../../utils/turkish_text.dart';
import '../ui.dart';

/// Living style guide for design language v3 "Akış" (`/dev/gallery`, dev
/// environment only).
///
/// Every token, component, drawing and motion piece of the v3 spec (§1–§6):
/// Archivo with tabular figures, the slate + orange palette (the web panel's),
/// floating white cards, Phosphor icons and the lively motion vocabulary
/// (cascades, springs, ambient life, draw-ins, bursts) — in light and dark,
/// at 100 / 130 / 200 % text and with reduce motion; the toggles in the app
/// bar apply to the gallery only. Copy is real Turkish product copy
/// (sentence case, no "A · B" strings), so the pages double as a copy
/// reference for the screen teams.
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
    'Yazı',
    'Plaka',
    'Satırlar',
    'Durumlar',
    'Butonlar',
    'Formlar',
    'Geri bildirim',
    'Gezinme',
    'Hareket',
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
              title: 'Galeri',
              subtitle: 'Akış, yalnızca geliştirme ortamı',
              showBell: false,
              actions: [
                AknIconButton(
                  icon: brightness == Brightness.dark
                      ? PhosphorIconsRegular.sun
                      : PhosphorIconsRegular.moon,
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
                  icon: PhosphorIconsRegular.textAa,
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
                      ? PhosphorIconsRegular.pauseCircle
                      : PhosphorIconsRegular.playCircle,
                  semanticLabel: _reduce ? 'Hareketi aç' : 'Hareketi azalt',
                  onPressed: () => setState(() => _reduce = !_reduce),
                ),
              ],
              bottom: AknTabBar(tabs: [for (final t in _tabs) Tab(text: t)]),
              body: const TabBarView(
                children: [
                  _ColorsTab(),
                  _TypeTab(),
                  _PlateTab(),
                  _RowsTab(),
                  _StatusTab(),
                  _ButtonsTab(),
                  _FormsTab(),
                  _FeedbackTab(),
                  _NavTab(),
                  _MotionTab(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Shared ─────────────────────────

/// A gallery page: content on the 20 px edge; [bleed] children (rows,
/// bars) run edge to edge.
class _Page extends StatelessWidget {
  const _Page({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        for (final w in children)
          w is _Bleed || w is _H || w is SectionHeader
              ? w
              : Padding(padding: AknSpace.pagePadding, child: w),
      ],
    );
  }
}

/// Full-width content inside a [_Page].
class _Bleed extends StatelessWidget {
  const _Bleed(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Section title (`SectionHeader`) with an optional note under it.
class _H extends StatelessWidget {
  const _H(this.text, [this.note]);

  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) =>
      SectionHeader(title: text, subtitle: note);
}

Widget _gap([double h = 12]) => SizedBox(height: h);

DateTime _in(Duration d) => TrTime.now().add(d);

const _months = ['May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki'];

// ───────────────────────── Renkler ─────────────────────────

class _ColorsTab extends StatelessWidget {
  const _ColorsTab();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final named = <(String, String, Color)>[
      ('Logo turuncusu', 'brand', c.brand),
      ('Turuncu metin', 'brandInk', c.brandInk),
      ('Yumuşak turuncu', 'brandSoft', c.brandSoft),
      ('Bant ışığı', 'heroGlow', c.heroGlow),
      ('Mürekkep', 'ink', c.ink),
      ('İkincil metin', 'dim', c.dim),
      ('Sayfa', 'bg', c.bg),
      ('Kart', 'surface', c.surface),
      ('Kuyu', 'surfaceAlt', c.surfaceAlt),
      ('Kontrol çizgisi', 'lineStrong', c.lineStrong),
      ('Kıl çizgi', 'line', c.line),
      ('Ters', 'inverse', c.inverse),
      ('Plaka kartı', 'plate', c.plate),
      ('Silme onayı', 'dangerFill', c.dangerFill),
      ('İskelet', 'skeleton', c.skeleton),
      ('İskelet ışığı', 'skeletonHighlight', c.skeletonHighlight),
    ];
    String hex(Color col) =>
        '#${(col.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').asciiUpper}';

    Widget label(String name, String token, [String? value]) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: t.captionStrong.copyWith(color: c.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (value != null)
            Text(
              value,
              style: t.caption.copyWith(fontFeatures: AknNumerals.tabular),
            ),
          Text(
            token,
            style: t.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    Widget swatch(String name, String token, Color col) => SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: col,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              border: Border.all(color: c.line),
              boxShadow: AknShadows.card(c),
            ),
          ),
          label(name, token, hex(col)),
        ],
      ),
    );

    Widget blend(String name, String token, Gradient g) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 72,
          decoration: BoxDecoration(
            gradient: g,
            borderRadius: AknRadius.card,
            boxShadow: AknShadows.card(c),
          ),
        ),
        label(name, token),
      ],
    );

    return _Page(
      children: [
        const _H(
          'Adlandırılmış palet',
          'Grafit taban, sayfada yüzen beyaz kartlar; turuncu yalnızca marka '
              'anlarında: bant, birincil düğme, seçili olan ve ilerleme.',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [for (final (n, k, col) in named) swatch(n, k, col)],
        ),
        const _H(
          'Geçişler',
          'Bant 135° üç duraklı ve ışıklı; birincil düğme beyaz etiketli.',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: blend('Üst bant', 'bandGradient', c.bandGradient)),
            const SizedBox(width: 12),
            Expanded(
              child: blend(
                'Birincil düğme',
                'buttonGradient',
                c.buttonGradient,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: blend('Plaka kartı', 'plateGradient', c.plateGradient),
            ),
          ],
        ),
        const _H(
          'Ton kuyuları',
          'Durumlar yumuşak tonlu kuyularda; mavi yok, bilgi mürekkeptir.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (text, tone) in const [
              ('Kararınızı bekliyor', AknTone.brand),
              ('Teslim alındı', AknTone.ok),
              ('Müdür onayı', AknTone.warn),
              ('İtirazlı', AknTone.danger),
              ('Yolda', AknTone.info),
              ('İptal', AknTone.neutral),
            ])
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.tone(tone).bg,
                  borderRadius: AknRadius.pillAll,
                  border: Border.all(color: c.tone(tone).line),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: c.tone(tone).solid,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        text,
                        style: t.captionStrong.copyWith(color: c.tone(tone).fg),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const _H('Durum lambaları', 'Durum her zaman nokta ve sözcüktür.'),
        const Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            AknLamp(label: 'Kararınızı bekliyor', tone: AknTone.brand),
            AknLamp(label: 'Yolda', tone: AknTone.info),
            AknLamp(label: 'Teslim alındı', tone: AknTone.ok),
            AknLamp(label: 'Müdür onayı', tone: AknTone.warn),
            AknLamp(label: 'İtirazlı', tone: AknTone.danger),
            AknLamp(label: 'İptal', tone: AknTone.neutral),
          ],
        ),
        const _H(
          'Grafik',
          'Tek seri vurgu: bu ay turuncu, gerisi gri; ilerleme turuncudur.',
        ),
        SizedBox(
          height: 84,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, h) in [36.0, 44, 52, 40, 60, 30].indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Container(
                  width: 18,
                  height: h.toDouble(),
                  decoration: BoxDecoration(
                    color: i == 5 ? null : c.chartContext,
                    gradient: i == 5
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [c.heroStart, c.brandFill],
                          )
                        : null,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    boxShadow: i == 5 ? AknShadows.glow(c.brand) : null,
                  ),
                ),
              ],
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ProgressRing(
                      value: 0.62,
                      size: 52,
                      strokeWidth: 6,
                      animateFromZero: true,
                      child: Text(
                        '%62',
                        style: t.captionStrong.copyWith(
                          color: c.ink,
                          fontFeatures: AknNumerals.tabular,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.chartTrack,
                        borderRadius: AknRadius.pillAll,
                      ),
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: 0.62,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [c.brandFillStart, c.brand],
                            ),
                            borderRadius: AknRadius.pillAll,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _H(
          'Plaka paleti',
          'Beyaz kart, üstte yumuşak turuncu ton; rakamlar mürekkep, turuncu yalnızca vurgu.',
        ),
        AknPlate(
          head: const PlateHead(
            icon: PhosphorIconsRegular.palette,
            title: 'plateInk()',
            period: 'mürekkep, 15,99:1',
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (n, col) in [
                ('onPlate', c.onPlate),
                ('plateAccent', c.plateAccent),
                ('plateIconFill', c.plateIconFill),
                ('deltaFill', c.deltaFill),
                ('plateContext', Color.alphaBlend(c.plateContext, c.plate)),
                ('plateLine', c.plateLine),
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: col,
                    borderRadius: AknRadius.tag,
                  ),
                  child: Text(
                    n,
                    style: t.captionStrong.copyWith(
                      color: col == c.onPlate || col == c.plateAccent
                          ? c.plate
                          : c.onPlate,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Yazı ─────────────────────────

class _TypeTab extends StatelessWidget {
  const _TypeTab();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    // A specimen line: the sample, then its style name and metrics.
    Widget spec(String name, String metrics, Widget sample) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sample,
          const SizedBox(height: 2),
          Text(
            '$name, $metrics',
            style: t.caption.copyWith(fontFeatures: AknNumerals.tabular),
          ),
        ],
      ),
    );
    return _Page(
      children: [
        const _H(
          'Sözcükler',
          'Archivo (web paneliyle aynı), tek aile (400–800); hiyerarşi boyut ve '
              'kalınlıktan gelir, renkten değil.',
        ),
        spec('display', '28/34 800', Text('Siparişler', style: t.display)),
        spec('title', '20/26 700', Text('Kararınızı bekliyor', style: t.title)),
        spec(
          'headline',
          '17/22 700',
          Text('Demir Petrol teklifi', style: t.headline),
        ),
        spec(
          'body',
          '15/22 400',
          Text(
            'Teklif onaylandı. Bayi sevkiyatı planlayacak. İĞDIR ığdır Şş Çç '
            'Öö Üü Ğğ İi Iı',
            style: t.body,
          ),
        ),
        spec(
          'bodyStrong',
          '15/22 600',
          Text('Motorin, 8.000 L', style: t.bodyStrong),
        ),
        spec(
          'bodySmall',
          '14/20 400',
          Text('Tuzla Şantiye, 22 Ekim Perşembe teslim', style: t.bodySmall),
        ),
        spec(
          'label',
          '13/18 600',
          Text('E-posta ya da kullanıcı adı', style: t.label),
        ),
        spec(
          'caption',
          '12/16 500',
          Text('güncellendi 10:41', style: t.caption),
        ),
        const _H(
          'Rakamlar',
          'Her rakam sabit genişlikli (tnum): sütunlar hizalanır, sayarken '
              'genişlik değişmez; uzun rakamlar küçülerek sığar.',
        ),
        spec(
          'plateFigure + plateUnit',
          '46/52 800',
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '1.524.380', style: t.plateFigure),
                TextSpan(text: ' ₺', style: t.plateUnit),
              ],
            ),
          ),
        ),
        spec(
          'plateFigure + figureWord',
          '46/52 800, 20/24 700',
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '%72', style: t.plateFigure),
                TextSpan(text: '  dönüşüm', style: t.figureWord),
              ],
            ),
          ),
        ),
        spec(
          'numberLarge',
          '32/38 800',
          Text('12,4 mn ₺', style: t.numberLarge),
        ),
        spec(
          'amountLarge',
          '28/34 800',
          Text('338.800,00 ₺', style: t.amountLarge),
        ),
        spec(
          'number + readoutUnit',
          '24/30 800',
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '42,35', style: t.number),
                TextSpan(text: ' ₺/L', style: t.readoutUnit),
              ],
            ),
          ),
        ),
        spec('amount', '17/22 700', Text('338.800,00 ₺', style: t.amount)),
        AknCard(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            children: [
              for (final (label, value) in const [
                ('Motorin, 30.000 L', '1.263.000,00 ₺'),
                ('Kurşunsuz 95, 2.000 L', '89.700,00 ₺'),
                ('Kalorifer yakıtı, 800 L', '30.280,00 ₺'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: t.bodySmall)),
                      Text(value, style: t.amount),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const _H(
          'Logo',
          'Logo değişmez; turuncu bantta beyaz karo, beyaz kartta turuncu.',
        ),
        const Row(
          children: [
            Flexible(child: AknLogo(markSize: 40)),
            SizedBox(width: 20),
            LogoMark(size: 32),
          ],
        ),
        _gap(16),
        ClipRRect(
          borderRadius: AknRadius.card,
          child: AknBand(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Row(
              children: [
                const Flexible(child: AknLogo(markSize: 40)),
                const SizedBox(width: 12),
                Icon(PhosphorIconsRegular.sparkle, color: c.onHero, size: 20),
              ],
            ),
          ),
        ),
        _gap(16),
        const AknPlate(
          head: PlateHead(title: 'Kart üstünde kilit'),
          child: Row(
            children: [
              LogoMark(size: 40),
              SizedBox(width: 16),
              Flexible(child: AknWordmark(fontSize: 22)),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Plaka ─────────────────────────

class _PlateTab extends StatefulWidget {
  const _PlateTab();

  @override
  State<_PlateTab> createState() => _PlateTabState();
}

class _PlateTabState extends State<_PlateTab> {
  int _replay = 0;
  int _lane = 0;

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const _H(
          'Satış',
          'Ekranın tek anahtar sayısı; kural, sayaç okumaları.',
        ),
        _Deck(
          plate: AknPlate(
            key: ValueKey('sales$_replay'),
            head: PlateHead(
              icon: PhosphorIconsRegular.chartBar,
              title: 'Satış',
              period: '1–21 Ekim',
              onMore: () {},
            ),
            figure: PlateFigure(
              value: '8.426.350',
              unit: '₺',
              animate: _replay > 0,
            ),
            delta: const PlateDelta(
              change: '%9,4',
              direction: AknDeltaDirection.up,
              sentence: 'geçen ayın aynı günlerine göre',
            ),
            chart: PlateBars(
              values: const [7.1, 7.4, 8.2, 7.6, 8.4, 8.43],
              labels: _months,
              projection: 12.4,
              valueLabels: const [
                '7,1 mn ₺',
                '7,4 mn ₺',
                '8,2 mn ₺',
                '7,6 mn ₺',
                '8,4 mn ₺',
                '8,43 mn ₺',
              ],
              animate: _replay > 0,
              delay: AknMotion.plateRoll - AknMotion.barsRise,
            ),
            below: const PlateReadouts(
              items: [
                PlateReadout(
                  label: 'Satılan yakıt',
                  value: '198.400',
                  unit: 'L',
                ),
                PlateReadout(label: 'Ortalama', value: '42,47', unit: '₺/L'),
                PlateReadout(
                  label: 'Ay sonu tahmini',
                  value: '12,4',
                  unit: 'mn ₺',
                  dashed: true,
                ),
              ],
            ),
          ),
        ),
        _Bleed(
          LanePager(
            count: 8,
            index: _lane,
            onSelect: (i) => setState(() => _lane = i),
            onPositionTap: () => setState(() => _lane = (_lane + 1) % 8),
            actionLabel: 'İstatistikler',
            onAction: () {},
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AknButton.secondary(
            label: 'Sayacı yeniden döndür',
            icon: PhosphorIconsRegular.arrowCounterClockwise,
            size: AknButtonSize.small,
            onPressed: () => setState(() => _replay++),
          ),
        ),
        const _H('Teklif'),
        const AknPlate(
          head: PlateHead(
            icon: PhosphorIconsRegular.invoice,
            title: 'Demir Petrol teklifi',
            period: 'bugün 10:05',
          ),
          figure: PlateFigure(value: '338.800', decimals: ',00', unit: '₺'),
          below: PlateReadouts(
            items: [
              PlateReadout(label: 'Birim fiyat', value: '42,35', unit: '₺/L'),
              PlateReadout(label: 'Miktar', value: '8.000', unit: 'L'),
              PlateReadout(label: 'Teslim', value: '22 Ekim'),
            ],
          ),
        ),
        const _H('Sürücü durağı'),
        const AknPlate(
          head: PlateHead(
            leading: AdrPlate(hazard: '30', un: '1202'),
            title: 'Motorin, bu durakta',
          ),
          figure: PlateFigure(value: '10.000', unit: 'L'),
          below: PlateReadouts(
            items: [
              PlateReadout(label: 'Varış', value: '11:20'),
              PlateReadout(label: 'Kalan yol', value: '18', unit: 'km'),
              PlateReadout(label: 'Teslim saati', value: '08:00–18:00'),
            ],
          ),
        ),
        const _H('Tahsilat'),
        const AknPlate(
          head: PlateHead(
            icon: PhosphorIconsRegular.wallet,
            title: 'Tahsilat',
            period: '1–21 Ekim',
          ),
          figure: PlateFigure(value: '6.120.000', unit: '₺'),
          delta: PlateDelta(sentence: '31 ödeme tahsil edildi'),
          below: PlateLedger(
            lines: [
              PlateLedgerLine(
                label: 'Vadesi geçen 2 ödeme',
                value: '184.000 ₺',
                problem: true,
              ),
              PlateLedgerLine(label: '7 gün içinde', value: '460.000 ₺'),
              PlateLedgerLine(label: 'Belge kontrolü', value: '3'),
            ],
          ),
        ),
        const _H('Sevkiyat'),
        const AknPlate(
          head: PlateHead(
            icon: PhosphorIconsRegular.truck,
            title: 'Sevkiyat',
            period: '1–21 Ekim',
          ),
          figure: PlateFigure(value: '38', word: 'teslimat'),
          chart: PlateMeter(value: 0.94, threshold: 0.9),
          delta: PlateDelta(sentence: '%94 zamanında, hedef %90'),
          below: PlateReadouts(
            items: [
              PlateReadout(label: 'Yolda', value: '1'),
              PlateReadout(label: 'Planlı', value: '5'),
              PlateReadout(label: 'İtirazlı', value: '1'),
            ],
          ),
        ),
        const _H('Sipariş hunisi'),
        const AknPlate(
          head: PlateHead(
            icon: PhosphorIconsRegular.funnel,
            title: 'Sipariş hunisi',
            period: '1–21 Ekim',
          ),
          figure: PlateFigure(value: '%72', word: 'dönüşüm'),
          delta: PlateDelta(
            change: '4 puan',
            direction: AknDeltaDirection.up,
            sentence: 'geçen aya göre',
          ),
          chart: PlateFunnel(
            steps: [
              PlateFunnelStep(label: 'Talep', value: '64', fraction: 1),
              PlateFunnelStep(label: 'Teklif', value: '58', fraction: 0.9),
              PlateFunnelStep(
                label: 'Onay',
                value: '46',
                fraction: 0.72,
                highlight: true,
              ),
            ],
          ),
          below: Text('İlk teklif süresi, ortalama 18 dk'),
        ),
        const _H('Limit riski'),
        const AknPlate(
          head: PlateHead(icon: PhosphorIconsFill.gauge, title: 'Limit riski'),
          figure: PlateFigure(value: '1', word: 'cari limitine yakın'),
          chart: PlateMeter(value: 0.94, threshold: 0.8),
          below: PlateLedger(
            lines: [
              PlateLedgerLine(
                label: 'Körfez Nakliyat',
                value: '940.000 / 1.000.000 ₺',
                problem: true,
              ),
              PlateLedgerLine(label: 'Uyarı sınırı', value: '%80'),
            ],
          ),
        ),
        const _H('En çok alan cariler'),
        const AknPlate(
          head: PlateHead(
            icon: PhosphorIconsRegular.usersThree,
            title: 'En çok alan cariler',
            period: '1–21 Ekim',
          ),
          figure: PlateFigure(value: '%51', word: 'ilk 4 cari'),
          below: PlateRankedBars(
            rows: [
              PlateRankedBar(
                label: 'Anadolu Lojistik',
                value: '1,52 mn ₺',
                fraction: 1,
              ),
              PlateRankedBar(
                label: 'Körfez Nakliyat',
                value: '1,10 mn ₺',
                fraction: 0.72,
              ),
              PlateRankedBar(
                label: 'Tuzla İnşaat',
                value: '0,84 mn ₺',
                fraction: 0.55,
              ),
            ],
          ),
        ),
        const _H('Ortalama birim fiyat'),
        const AknPlate(
          head: PlateHead(
            icon: PhosphorIconsRegular.tag,
            title: 'Ortalama birim fiyat',
            period: '1–21 Ekim',
          ),
          figure: PlateFigure(value: '42,34', unit: '₺/L'),
          delta: PlateDelta(
            change: '%1,2',
            direction: AknDeltaDirection.down,
            sentence: 'geçen aya göre',
          ),
          chart: PlateLine(
            values: [41.2, 41.6, 42.1, 42.9, 42.85, 42.34],
            labels: _months,
            endLabel: '42,34',
          ),
        ),
        const _H('Büyük yazı', '1,6× ve üstünde kısa düzen.'),
        const AknPlate(
          compact: true,
          head: PlateHead(
            icon: PhosphorIconsRegular.money,
            title: 'Bu ay harcama',
            period: '1–21 Ekim',
          ),
          figure: PlateFigure(value: '1.524.380', unit: '₺'),
          delta: PlateDelta(
            change: '%12,8',
            direction: AknDeltaDirection.up,
            sentence: 'geçen ayın aynı günlerine göre',
          ),
          chart: SizedBox(height: 40),
        ),
        const _H('Beyaz üstünde değişim'),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AknDeltaChip(
              label: '%1,2',
              direction: AknDeltaDirection.down,
              goodForViewer: true,
            ),
            AknDeltaChip(
              label: '%4,5',
              direction: AknDeltaDirection.up,
              goodForViewer: false,
            ),
            AknDeltaChip(label: '%9,4', direction: AknDeltaDirection.up),
            AknDeltaChip(label: 'aynı', direction: AknDeltaDirection.flat),
          ],
        ),
      ],
    );
  }
}

/// The deck look: the hero card on top of two cards behind it (the
/// statistics deck itself lives in `features/stats`).
class _Deck extends StatelessWidget {
  const _Deck({required this.plate});

  final Widget plate;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    Widget slip(double inset, double drop, Color fill) => Positioned(
      left: inset,
      right: inset,
      bottom: -drop,
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: AknRadius.plate,
          border: Border.all(color: c.plateBorder),
          boxShadow: AknShadows.plateBehind(c),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Stack(
        clipBehavior: Clip.none,
        children: [slip(26, 26, c.plate), slip(13, 13, c.plate), plate],
      ),
    );
  }
}

// ───────────────────────── Satırlar ─────────────────────────

class _RowsTab extends StatefulWidget {
  const _RowsTab();

  @override
  State<_RowsTab> createState() => _RowsTabState();
}

class _RowsTabState extends State<_RowsTab> {
  bool _push = true;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return _Page(
      children: [
        const SectionHeader(title: 'Karar bekleyen teklifler', count: 1),
        _Bleed(
          AknListTile(
            title: 'Demir Petrol teklifi',
            subtitle: 'Motorin, 8.000 L, Tuzla Şantiye',
            amount: '338.800,00 ₺',
            amountMeta: '42,35 ₺/L',
            status: AknStatusLine(
              lamp: Text('Çek ile, 30 gün vade', style: t.bodySmall),
              trailing: CountdownBadge(
                deadline: _in(
                  const Duration(hours: 2, minutes: 57, seconds: 30),
                ),
                yourMove: true,
                subject: 'Teklif',
              ),
            ),
            onTap: () {},
          ),
        ),
        SectionHeader(
          title: 'Yolda',
          actionLabel: 'Haritada izle',
          onAction: () {},
        ),
        _Bleed(
          AknListTile(
            title: 'Pendik Lojistik Merkezi',
            subtitle: '10.000 L motorin, 41 DMR 101',
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('11:20', style: t.number),
                Text('tahmini varış', style: t.bodySmall),
              ],
            ),
            footer: const TruckRoute(
              progress: 0.62,
              moving: true,
              semanticLabel:
                  'Yolda. Dilovası deposundan Pendik Lojistik Merkezine, '
                  'tahmini varış 11:20.',
            ),
            onTap: () {},
          ),
        ),
        const SectionHeader(title: 'Siparişler', caption: 'bugün, 10:42'),
        _Bleed(
          AknLedger(
            children: [
              AknListTile(
                title: 'Körfez Nakliyat ve Ticaret',
                subtitle: 'SIP-20261020-12009, Motorin, 10.000 L',
                amount: '421.000 ₺',
                amountMeta: 'önerilen',
                status: AknStatusLine(
                  lamp: const AknLamp(
                    label: 'Teklif verin',
                    tone: AknTone.brand,
                  ),
                  trailing: CountdownBadge(
                    deadline: _in(const Duration(minutes: 41, seconds: 30)),
                    yourMove: true,
                  ),
                ),
                onTap: () {},
              ),
              AknListTile(
                title: 'Motorin, 30.000 L',
                subtitle: 'Pendik Lojistik Merkezi, 24 Ekim',
                amount: '1.263.000 ₺',
                amountMeta: 'tahmini',
                status: AknStatusLine(
                  lamp: const AknLamp(
                    label: 'Onayınızı bekliyor',
                    tone: AknTone.brand,
                  ),
                  trailing: Text('Burak Yılmaz’ın talebi', style: t.bodySmall),
                ),
                onTap: () {},
              ),
              AknListTile(
                title: 'Vadesi geçen 2 ödeme',
                subtitle: 'En eskisi 6 gün gecikmede',
                amount: '184.000 ₺',
                status: const AknLamp(label: 'Gecikmede', tone: AknTone.danger),
                onTap: () {},
              ),
              AknListTile(
                title: 'Kurşunsuz 95, 2.000 L',
                subtitle: 'Pendik Lojistik Merkezi, 23 Ekim',
                amount: '89.700 ₺',
                amountMeta: 'tahmini',
                status: const AknLamp(
                  label: 'Teslim alındı',
                  tone: AknTone.ok,
                  solid: true,
                ),
                onTap: () {},
              ),
            ],
          ),
        ),
        const _H('Tüpraş fiyatları'),
        const KpiRow(
          children: [
            KpiTile(
              label: 'Motorin',
              value: 41.92,
              format: _price,
              trend: 0.38,
              trendFormat: _price,
            ),
            KpiTile(
              label: 'Kurşunsuz 95',
              value: 44.10,
              format: _price,
              trend: 0,
            ),
            KpiTile(
              label: 'Kalorifer yakıtı',
              value: 37.85,
              format: _price,
              trend: -0.12,
              trendFormat: _price,
            ),
          ],
        ),
        const _H('Bilgi satırları'),
        const FactRow(label: 'Limit', value: '2.500.000,00 ₺'),
        const FactRow(label: 'Kullanım', value: '%92', tone: AknTone.warn),
        const FactRow(
          label: 'Risk sınıfı',
          value: 'D, yüksek risk',
          tone: AknTone.danger,
        ),
        const FactRow(
          icon: PhosphorIconsRegular.door,
          label: 'Kapı notu',
          value: 'Ana kapıda güvenliğe plakayı bildirin; tank arka avluda.',
        ),
        const _H(
          'Kuyular',
          'Yumuşak tonlu zemin, tonlu simge, mürekkep metin.',
        ),
        const AknBanner(
          tone: AknTone.info,
          message:
              '2 sipariş finans onayında; finans onaylayınca masaya düşer.',
        ),
        _gap(8),
        AknBanner(
          tone: AknTone.warn,
          message: 'Onaylamak için çek görselini yükleyin.',
          actionLabel: 'Belge yükle',
          onAction: () {},
        ),
        _gap(8),
        const AknBanner(
          tone: AknTone.danger,
          title: 'Teklif onaylanamadı',
          message: 'Çek görseli eksik. Görseli yükleyip tekrar deneyin.',
        ),
        const _H('Grup kutusu', 'Ayarlar ve form grupları; liste değil.'),
        AknCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              AknListTile(
                leadingIcon: PhosphorIconsRegular.user,
                title: 'Profil',
                showChevron: true,
                onTap: () {},
              ),
              const AknLedgerDivider(),
              AknListTile(
                leadingIcon: PhosphorIconsRegular.bell,
                title: 'Bildirim ayarları',
                showChevron: true,
                onTap: () {},
              ),
              const AknLedgerDivider(),
              AknListTile(
                leadingIcon: PhosphorIconsRegular.megaphone,
                title: 'Anlık bildirimler',
                subtitle: 'Teklif, onay ve teslimat',
                trailing: Switch(
                  value: _push,
                  onChanged: (v) => setState(() => _push = v),
                ),
              ),
            ],
          ),
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
        _gap(8),
        AttachmentTile(
          fileName: 'vergi-levhasi.pdf',
          kindLabel: 'Vergi levhası',
          sizeBytes: 220000,
          state: AttachmentTileState.failed,
          onRetry: () {},
        ),
        _gap(8),
        AttachmentTile(
          fileName: 'irsaliye-5521.pdf',
          kindLabel: 'İrsaliye',
          subtitle: '21 Ekim 14:20',
          onTap: () {},
        ),
        const _H('Araç plakaları'),
        Row(
          children: [
            const PlateBadge(plate: '41 DMR 101'),
            const SizedBox(width: 16),
            const AdrPlate(hazard: '30', un: '1202'),
            const SizedBox(width: 12),
            const AdrPlate(hazard: '33', un: '1203', height: 28),
            const Spacer(),
            Text('Motorin, Kurşunsuz', style: t.caption.copyWith(color: c.dim)),
          ],
        ),
        const _H('Rota çizgisi'),
        const TruckRoute(
          progress: 0.4,
          moving: true,
          originLabel: 'Dilovası deposu, 09:58 çıktı',
          destinationLabel: '18 km kaldı',
        ),
      ],
    );
  }

  static String _price(num v) => Fmt.number(v, minFraction: 2, maxFraction: 2);
}

// ───────────────────────── Durumlar ─────────────────────────

class _StatusTab extends StatelessWidget {
  const _StatusTab();

  @override
  Widget build(BuildContext context) {
    const stops = [
      'Talep',
      'Onay',
      'Teklif',
      'Karar',
      'Plan',
      'Yolda',
      'Teslim',
    ];
    return _Page(
      children: [
        const _H('Aşama şeridi', 'Sıra sizdeyken turuncu halka.'),
        const StageStrip(stages: stops, current: 3, yourMove: true),
        _gap(20),
        const StageStrip(stages: stops, current: 5),
        _gap(20),
        const StageStrip(
          stages: stops,
          current: 3,
          problem: StageProblem.rejected,
        ),
        const _H('Geri sayım'),
        Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            CountdownBadge(deadline: _in(const Duration(hours: 26))),
            CountdownBadge(
              deadline: _in(const Duration(hours: 2, minutes: 57)),
              yourMove: true,
            ),
            CountdownBadge(deadline: _in(const Duration(minutes: 12))),
            CountdownBadge(
              deadline: TrTime.now().subtract(const Duration(minutes: 1)),
            ),
          ],
        ),
        const _H('Sipariş akışı'),
        const StepTimeline(
          yourMove: true,
          steps: [
            TimelineStep(
              title: 'Sipariş oluşturuldu',
              subtitle: 'Selin Aydın',
              time: '20 Eki 09:12',
              state: TimelineState.done,
            ),
            TimelineStep(
              title: 'Teklif geldi',
              subtitle: '42,35 ₺/L',
              time: 'bugün 10:05',
              state: TimelineState.done,
            ),
            TimelineStep(
              title: 'Kararınız',
              subtitle: '2 sa 57 dk kaldı',
              state: TimelineState.current,
            ),
            TimelineStep(title: 'Sevkiyat'),
            TimelineStep(title: 'Teslim'),
          ],
        ),
        const _H('Sihirbaz başlığı'),
        StepperHeader(
          padding: EdgeInsets.zero,
          steps: const ['Ürün', 'Teslimat', 'Ödeme', 'Özet'],
          current: 2,
          onStepTap: (_) {},
        ),
        const _H('Kişiler ve sayaçlar'),
        const Row(
          children: [
            AknAvatar(name: 'Mehmet Demir'),
            SizedBox(width: 10),
            AknAvatar(name: 'İpek Şahin'),
            SizedBox(width: 10),
            AknAvatar(name: 'Can Öz', size: 32),
            SizedBox(width: 24),
            AknCountBadge(count: 3),
            SizedBox(width: 10),
            AknCountBadge(count: 128),
            SizedBox(width: 10),
            AknCountBadge(count: 0, dot: true),
          ],
        ),
        for (final values in allCodedEnums) ...[
          _H(values.first.runtimeType.toString()),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              for (final v in values) StatusChip.style(AknStatus.of(v)),
            ],
          ),
        ],
        const _H('Barem bandı'),
        Wrap(
          spacing: 20,
          runSpacing: 10,
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
        const _H('Türler', 'Ekran bölgesi başına tek birincil düğme.'),
        AknButton(label: 'Teklifi onayla', expand: true, onPressed: () {}),
        _gap(10),
        Row(
          children: [
            Expanded(
              child: AknButton.secondary(
                label: 'Revize iste',
                size: AknButtonSize.medium,
                expand: true,
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AknButton.danger(
                label: 'Reddet',
                size: AknButtonSize.medium,
                expand: true,
                onPressed: () {},
              ),
            ),
          ],
        ),
        _gap(10),
        AknButton.outline(
          label: 'Telefon numarasıyla giriş yap',
          icon: PhosphorIconsRegular.deviceMobile,
          expand: true,
          onPressed: () {},
        ),
        _gap(10),
        Row(
          children: [
            AknButton.ghost(label: 'Vazgeç', onPressed: () {}),
            const SizedBox(width: 10),
            const Expanded(
              child: AknButton(
                label: 'Siparişi gönder',
                expand: true,
                onPressed: null,
              ),
            ),
          ],
        ),
        _gap(10),
        DestructiveButton(label: 'Teklifi reddet', onPressed: () {}),
        const _H('Boyutlar'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AknButton.secondary(
              label: 'Teklif ver',
              size: AknButtonSize.small,
              onPressed: () {},
            ),
            AknButton(
              label: 'Planla',
              size: AknButtonSize.medium,
              onPressed: () {},
            ),
            AknButton(label: 'Giriş yap', onPressed: () {}),
          ],
        ),
        const _H('Sürücü', '64 px, r18, 18/22 etiket, 64 px dokunma alanı.'),
        AknDriverScope(
          child: Row(
            children: [
              Expanded(
                child: AknButton(
                  label: 'Yol tarifi',
                  icon: PhosphorIconsRegular.navigationArrow,
                  expand: true,
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AknButton.secondary(
                  label: 'Teslim et',
                  icon: PhosphorIconsFill.checkCircle,
                  expand: true,
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
        const _H('Gönderirken'),
        AknButton(
          label: 'Teklifleri gönder',
          expand: true,
          onPressedAsync: () =>
              Future<void>.delayed(const Duration(milliseconds: 1400)),
        ),
        _gap(10),
        AknButton.secondary(
          label: 'Belge yükle',
          icon: PhosphorIconsRegular.fileArrowUp,
          loading: _loading,
          expand: true,
          onPressed: () async {
            setState(() => _loading = true);
            await Future<void>.delayed(const Duration(seconds: 2));
            if (mounted) setState(() => _loading = false);
          },
        ),
        const _H('Bağlantılar'),
        Row(
          children: [
            AknInlineLink(label: 'Şifremi unuttum', onTap: () {}),
            const SizedBox(width: 20),
            AknInlineLink(label: 'Tablo olarak göster', onTap: () {}),
          ],
        ),
        const _H('İkon düğmeleri'),
        Row(
          children: [
            AknIconButton(
              icon: PhosphorIconsRegular.bell,
              semanticLabel: 'Bildirimler',
              badgeCount: _badge,
              onPressed: () => setState(() => _badge++),
            ),
            AknIconButton(
              icon: PhosphorIconsRegular.list,
              semanticLabel: 'Diğer',
              showDot: true,
              onPressed: () {},
            ),
            AknIconButton(
              icon: PhosphorIconsRegular.dotsThree,
              semanticLabel: 'Diğer seçenekler',
              onPressed: () => setState(() => _badge = 0),
            ),
            AknIconButton(
              icon: PhosphorIconsRegular.export,
              semanticLabel: 'Paylaş',
              onPressed: () {},
            ),
          ],
        ),
        const _H('Kaydırarak onayla'),
        SlideToConfirm(
          label: 'Teslimatı kaydetmek için kaydırın',
          resetAfterDone: true,
          confirmLabel: 'Teslimatı kaydet',
          onConfirmed: () =>
              Future<void>.delayed(const Duration(milliseconds: 1200)),
        ),
        _gap(),
        const SlideToConfirm(
          label: 'Önce sayaç okumasını girin',
          enabled: false,
          onConfirmed: _noop,
        ),
      ],
    );
  }

  static void _noop() {}
}

// ───────────────────────── Formlar ─────────────────────────

class _FormsTab extends StatefulWidget {
  const _FormsTab();

  @override
  State<_FormsTab> createState() => _FormsTabState();
}

class _FormsTabState extends State<_FormsTab> {
  DateTime? _date = TrTime.addDays(TrTime.todayStart(), 1);
  Set<String> _filters = {'all'};
  String _segment = 'month';
  String _method = 'cheque';
  bool _check = true;
  String _radio = 'a';
  final _password = TextEditingController(text: 'demo-sifre');

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const _H('Alanlar', 'Etiket üstte, 52 px, beyaz zemin.'),
        const AknTextField(
          label: 'E-posta ya da kullanıcı adı',
          initialValue: 'selin.aydin@anadolulojistik.com.tr',
        ),
        _gap(14),
        AknPasswordField(
          controller: _password,
          labelActionText: 'Şifremi unuttum',
          onLabelAction: () {},
        ),
        _gap(14),
        const AknTextField(
          label: 'Teslimat noktası',
          hint: 'Nokta seçin',
          errorText: 'Teslimat noktası seçmeden sipariş gönderilemez.',
        ),
        _gap(14),
        const AknTextField(
          label: 'Cari kodu',
          initialValue: 'C-10442',
          enabled: false,
        ),
        _gap(14),
        const LitersField(initialValue: 8000, requiredValue: true),
        _gap(14),
        const MoneyField.unitPrice(label: 'Birim fiyat', initialValue: 42.35),
        _gap(14),
        DateField(
          label: 'Teslim tarihi',
          value: _date,
          onChanged: (d) => setState(() => _date = d),
        ),
        _gap(14),
        const PlateField(initialValue: '41dmr101'),
        const _H('Arama'),
        const SearchField(hint: 'Sipariş no, ürün, nokta ya da bayi'),
        const _H('Sekmeler'),
        const _Bleed(
          DefaultTabController(
            length: 2,
            child: SizedBox(
              height: 48,
              child: AknTabBar(
                tabs: [
                  AknTab(label: 'Aktif', count: 4),
                  AknTab(label: 'Geçmiş', count: 28),
                ],
              ),
            ),
          ),
        ),
        const _H('Filtreler'),
        _Bleed(
          FilterChips<String>(
            selected: _filters,
            onChanged: (s) => setState(() => _filters = s),
            options: const [
              FilterOption(value: 'all', label: 'Tümü', count: 6),
              FilterOption(value: 'new', label: 'Yeni', count: 4),
              FilterOption(value: 'revise', label: 'Revize', count: 2),
              FilterOption(value: 'soon', label: 'Süresi yaklaşan'),
            ],
          ),
        ),
        _gap(),
        AknSegmented<String>(
          margin: EdgeInsets.zero,
          value: _segment,
          onChanged: (v) => setState(() => _segment = v),
          segments: const [
            FilterOption(value: 'month', label: 'Bu ay'),
            FilterOption(value: 'last', label: 'Geçen ay'),
            FilterOption(value: 'quarter', label: 'Son 3 ay'),
            FilterOption(value: 'year', label: 'Bu yıl'),
          ],
        ),
        const _H('Seçim kartları'),
        for (final (code, title, sub, icon) in [
          (
            'wire',
            'Havale / EFT',
            'Peşin, vade yok',
            PhosphorIconsRegular.bank,
          ),
          ('cheque', 'Çek', '30 gün vade', PhosphorIconsRegular.money),
          ('note', 'Senet', '60 gün vade', PhosphorIconsRegular.fileText),
        ])
          ChoiceCard(
            margin: const EdgeInsets.only(bottom: 8),
            title: title,
            subtitle: sub,
            leadingIcon: icon,
            selected: _method == code,
            onTap: () => setState(() => _method = code),
          ),
        const ChoiceCard(
          title: 'Kredi kartı',
          subtitle: 'Bu bayide kapalı',
          leadingIcon: PhosphorIconsRegular.creditCard,
          selected: false,
          onTap: null,
        ),
        const _H('Seçimler'),
        Row(
          children: [
            Checkbox(
              value: _check,
              onChanged: (v) => setState(() => _check = v ?? false),
            ),
            const Text('Şablon olarak kaydet'),
          ],
        ),
        RadioGroup<String>(
          groupValue: _radio,
          onChanged: (v) => setState(() => _radio = v ?? 'a'),
          child: const Column(
            children: [
              RadioListTile<String>(
                value: 'a',
                title: Text('Tuzla Şantiye'),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<String>(
                value: 'b',
                title: Text('Pendik Lojistik Merkezi'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Geri bildirim ─────────────────────────

class _FeedbackTab extends StatefulWidget {
  const _FeedbackTab();

  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  bool _offline = true;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return _Page(
      children: [
        const _H('Bildirim', 'Metin düğmenin fiilini tekrarlar.'),
        const AppToastCard(
          type: AppToastType.success,
          message: 'Teklif onaylandı. Bayi sevkiyatı planlayacak.',
        ),
        _gap(8),
        AppToastCard(
          type: AppToastType.error,
          message: 'Bağlantı yok. Değişiklikler telefona kaydedildi.',
          actionLabel: 'Tekrar dene',
          onAction: () {},
        ),
        _gap(8),
        const AppToastCard(
          type: AppToastType.warning,
          message: 'Bugünün Tüpraş fiyatı girilmedi.',
        ),
        _gap(10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AknButton.secondary(
              label: 'Başarı göster',
              size: AknButtonSize.small,
              onPressed: () => AppToast.success(
                'Teklif onaylandı. Bayi sevkiyatı planlayacak.',
                context: context,
              ),
            ),
            AknButton.secondary(
              label: 'Hata göster',
              size: AknButtonSize.small,
              onPressed: () => AppToast.error(
                'Sunucuya şu an ulaşılamıyor. Birkaç dakika sonra tekrar '
                'deneyin.',
                context: context,
                onAction: () {},
              ),
            ),
          ],
        ),
        const _H('Alt sayfa', 'Üst köşeler 28, yükselmiş gölge, 360 ms kayar.'),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AknRadius.dialog,
            boxShadow: AknShadows.raised(c),
          ),
          child: ClipRRect(
            borderRadius: AknRadius.dialog,
            child: ColoredBox(
              color: c.surfaceRaised,
              child: const AppSheet(
                showClose: false,
                scrollable: false,
                child: ConfirmSheet(
                  title: 'Teklifi reddet',
                  message:
                      'Bayi bilgilendirilir. Bu işlem geri alınamaz; yeni '
                      'teklif için yeni sipariş gerekir.',
                  confirmLabel: 'Teklifi reddet',
                  destructive: true,
                ),
              ),
            ),
          ),
        ),
        _gap(16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AknButton.secondary(
              label: 'Revize iste',
              size: AknButtonSize.small,
              onPressed: () => showAppSheet<void>(
                context: context,
                title: 'Revize iste',
                builder: (ctx) => const AknTextField(
                  label: 'Neyi değiştirmesini istiyorsunuz?',
                  hint: 'Örneğin birim fiyat ya da teslim tarihi',
                  maxLines: 3,
                ),
                actionsBuilder: (ctx) => AknButton(
                  label: 'Revize iste',
                  expand: true,
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
            AknButton.secondary(
              label: 'Onay sorusu',
              size: AknButtonSize.small,
              onPressed: () => showConfirmSheet(
                context,
                title: 'Teklifi reddet',
                message: 'Bayi bilgilendirilir. Bu işlem geri alınamaz.',
                confirmLabel: 'Teklifi reddet',
                destructive: true,
              ),
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
        const _H('Çevrimdışı'),
        _Bleed(OfflineBanner(offline: _offline, pendingCount: 3)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AknButton.ghost(
            label: _offline ? 'Çevrimiçi yap' : 'Çevrimdışı yap',
            size: AknButtonSize.small,
            onPressed: () => setState(() => _offline = !_offline),
          ),
        ),
        const _H(
          'İskelet',
          'Kartları taklit eder; yumuşak çapraz bir ışık süzülür (1,4 sn, '
              'yalnızca yüklenirken).',
        ),
        const _Bleed(SizedBox(height: 290, child: SkeletonList(itemCount: 3))),
        const _H(
          'Yükleniyor',
          '» yükleyici süzülen bir dairede; yenilerken üstte ince turuncu '
              'çubuk.',
        ),
        const SizedBox(
          height: 150,
          child: LoadingView(message: 'Siparişler getiriliyor'),
        ),
        const TopProgressBar(active: true),
        _gap(10),
        const TopProgressBar(active: true, value: 0.62),
        const _H(
          'Çizimler',
          '96 × 64: beyaz gövde, 2 px grafit çizgi, yuvarlak uçlar ve '
              'turuncu vurgu.',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final d in AknDrawing.values)
              Column(
                children: [
                  EmptyIllustration(drawing: d),
                  const SizedBox(height: 4),
                  Text(d.name, style: context.aknText.caption),
                ],
              ),
          ],
        ),
        const _H(
          'Boş durum',
          'Çizim yumuşak bir dairede süzülür; içerik basamaklı gelir.',
        ),
        EmptyState(
          title: 'Açık siparişiniz yok',
          message: 'Yeni sipariş için Sipariş ver’e dokunun.',
          illustration: AknIllustration.orders,
          actionLabel: 'Sipariş ver',
          onAction: () {},
        ),
        const _H('Hata', 'Çizim belirirken bir kez sallanır.'),
        ErrorState(onRetry: () {}, traceId: '00-4bf92f3577b34da6'),
        ErrorState(offline: true, compact: true, onRetry: () {}),
        const _H(
          'Sonuç',
          'Halka ve onay çizilir, işaret hafifçe zıplar, parçacıklar bir kez '
              'saçılır.',
        ),
        ResultView(
          title: 'Siparişiniz bayiye gönderildi',
          message: 'Teklif gelince bildirim göndereceğiz.',
          details: const AknCard(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              children: [
                FactRow(label: 'Sipariş no', value: 'SIP-20261021-12002'),
                FactRow(label: 'Tahmini tutar', value: '338.800 ₺'),
              ],
            ),
          ),
          primaryLabel: 'Siparişi aç',
          onPrimary: () {},
          secondaryLabel: 'Ana sayfaya dön',
          onSecondary: () {},
        ),
        ResultView(
          tone: AknTone.danger,
          title: 'Sipariş gönderilemedi',
          message: 'Bağlantı koptu. Siparişiniz telefonda duruyor.',
          primaryLabel: 'Tekrar gönder',
          onPrimary: () {},
        ),
      ],
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
  int _b = 0;
  int _d = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return _Page(
      children: [
        const _H('Ana sayfa başlığı'),
        _Bleed(
          AppChrome(
            unreadCount: 2,
            onOpenNotifications: () {},
            child: AknHomeHeader(
              company: 'Demir Petrol Akaryakıt Ltd. Şti.',
              person: 'Mehmet Demir, bayi sahibi',
              onOpenProfile: () {},
            ),
          ),
        ),
        const _H('Kök sayfa başlığı'),
        Row(
          children: [
            Expanded(child: Text('Siparişler', style: t.display)),
            AknIconButton(
              icon: PhosphorIconsRegular.slidersHorizontal,
              semanticLabel: 'Filtrele',
              onPressed: () {},
            ),
          ],
        ),
        const _H('Açılan sayfa başlığı'),
        Row(
          children: [
            Icon(PhosphorIconsRegular.arrowLeft, color: c.ink),
            const SizedBox(width: 20),
            Expanded(child: Text('SIP-20261021-12002', style: t.headline)),
            Icon(PhosphorIconsRegular.dotsThree, color: c.ink),
          ],
        ),
        const _H(
          'Alt çubuk',
          'Bayi sahibi: beş öğe; turuncu hap aktif öğeye yaylanarak kayar.',
        ),
        _Bleed(
          _NoInset(
            child: AnimatedBottomBar(
              currentIndex: _a,
              onSelected: (i) => setState(() => _a = i),
              items: const [
                AknNavItem(
                  icon: PhosphorIconsRegular.house,
                  selectedIcon: PhosphorIconsFill.house,
                  label: 'Ana sayfa',
                ),
                AknNavItem(
                  icon: PhosphorIconsRegular.checkCircle,
                  selectedIcon: PhosphorIconsFill.checkCircle,
                  label: 'Onaylar',
                  badgeCount: 2,
                ),
                AknNavItem(
                  icon: PhosphorIconsRegular.invoice,
                  selectedIcon: PhosphorIconsFill.invoice,
                  label: 'Teklifler',
                  badgeCount: 6,
                ),
                AknNavItem(
                  icon: PhosphorIconsRegular.receipt,
                  selectedIcon: PhosphorIconsFill.receipt,
                  label: 'Siparişler',
                ),
                AknNavItem(icon: PhosphorIconsRegular.list, label: 'Diğer'),
              ],
            ),
          ),
        ),
        const _H('Sipariş ver tuşu', 'Müşteri: tuş da bir öğedir.'),
        _Bleed(
          _NoInset(
            child: AnimatedBottomBar(
              currentIndex: _b,
              onSelected: (i) => setState(() => _b = i),
              centerAction: AknCenterAction(
                icon: PhosphorIconsRegular.plus,
                label: 'Sipariş ver',
                onPressed: () {},
              ),
              items: const [
                AknNavItem(
                  icon: PhosphorIconsRegular.house,
                  selectedIcon: PhosphorIconsFill.house,
                  label: 'Ana sayfa',
                ),
                AknNavItem(
                  icon: PhosphorIconsRegular.receipt,
                  selectedIcon: PhosphorIconsFill.receipt,
                  label: 'Siparişler',
                ),
                AknNavItem(
                  icon: PhosphorIconsRegular.checkCircle,
                  selectedIcon: PhosphorIconsFill.checkCircle,
                  label: 'Onaylar',
                  badgeCount: 1,
                ),
                AknNavItem(icon: PhosphorIconsRegular.list, label: 'Diğer'),
              ],
            ),
          ),
        ),
        const _H('Sürücü', 'Dört öğe, 64 px.'),
        _Bleed(
          AknDriverScope(
            child: _NoInset(
              child: AnimatedBottomBar(
                currentIndex: _d,
                onSelected: (i) => setState(() => _d = i),
                items: const [
                  AknNavItem(
                    icon: PhosphorIconsRegular.truck,
                    selectedIcon: PhosphorIconsFill.truck,
                    label: 'Teslimat',
                  ),
                  AknNavItem(
                    icon: PhosphorIconsRegular.bell,
                    selectedIcon: PhosphorIconsFill.bell,
                    label: 'Bildirimler',
                    badgeCount: 1,
                  ),
                  AknNavItem(
                    icon: PhosphorIconsRegular.chatCircle,
                    selectedIcon: PhosphorIconsFill.chatCircle,
                    label: 'Asistan',
                  ),
                  AknNavItem(
                    icon: PhosphorIconsRegular.user,
                    selectedIcon: PhosphorIconsFill.user,
                    label: 'Profil',
                  ),
                ],
              ),
            ),
          ),
        ),
        const _H('Yapışkan eylem çubuğu'),
        _Bleed(
          _NoInset(
            child: ActionBar(
              child: AknButton(
                label: 'Siparişi gönder',
                expand: true,
                onPressed: () {},
              ),
            ),
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

// ───────────────────────── Hareket ─────────────────────────

class _MotionTab extends StatefulWidget {
  const _MotionTab();

  @override
  State<_MotionTab> createState() => _MotionTabState();
}

class _MotionTabState extends State<_MotionTab> {
  int _replay = 0;
  int _stage = 3;
  double _route = 0.35;

  Future<void> _refresh() =>
      Future<void>.delayed(const Duration(milliseconds: 1400));

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return _Page(
      children: [
        const _H(
          'Sayaç dönüşü',
          'Oturumun ilk ana sayfasında bir kez; hareket azaltmada son kare.',
        ),
        AknPlate(
          key: ValueKey('roll$_replay'),
          head: const PlateHead(
            icon: PhosphorIconsRegular.money,
            title: 'Bu ay harcama',
            period: '1–21 Ekim',
          ),
          figure: const PlateFigure(
            value: '1.524.380',
            unit: '₺',
            animate: true,
          ),
          chart: PlateBars(
            values: const [1.1, 1.3, 1.25, 1.4, 1.6, 1.52],
            labels: _months,
            projection: 2.25,
            animate: true,
            delay: AknMotion.plateRoll - AknMotion.barsRise,
          ),
        ),
        _gap(),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AknButton.secondary(
            label: 'Yeniden oynat',
            icon: PhosphorIconsRegular.arrowCounterClockwise,
            size: AknButtonSize.small,
            onPressed: () => setState(() => _replay++),
          ),
        ),
        const _H(
          'Basamaklı giriş',
          'Liste öğeleri 55 ms arayla yükselerek gelir; kaydırınca yenileri '
              'de kayarak girer.',
        ),
        StaggerScope(
          key: ValueKey('stagger$_replay'),
          child: Column(
            children: [
              for (final (i, (title, amount)) in const [
                ('Motorin, 30.000 L', '1.263.000 ₺'),
                ('Kurşunsuz 95, 2.000 L', '89.700 ₺'),
                ('Kalorifer yakıtı, 800 L', '30.280 ₺'),
              ].indexed)
                StaggerItem(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AknCard(
                      onTap: () {},
                      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            child: Icon(
                              PhosphorIconsRegular.gasPump,
                              size: 22,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(title, style: t.bodyStrong)),
                          Text(amount, style: t.amount),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const _H(
          'Sayılar',
          'Değerler ilk görünüşte sıfırdan sayar, değişince yenisine akar.',
        ),
        AnimatedNumber(
          key: ValueKey('number$_replay'),
          value: 1524380,
          format: (v) => '${Fmt.number(v.round())} ₺',
          style: t.numberLarge,
        ),
        const _H(
          'Çizgiler ve halkalar',
          'Eğilim çizgisi soldan çizilir, halka dolar, damla dalgalanır.',
        ),
        Row(
          key: ValueKey('paint$_replay'),
          children: [
            const Expanded(
              child: Sparkline(
                values: [12, 14, 13, 17, 16, 21, 24],
                height: 56,
              ),
            ),
            const SizedBox(width: 16),
            ProgressRing(
              value: 0.72,
              size: 56,
              strokeWidth: 6,
              animateFromZero: true,
              child: Text(
                '%72',
                style: t.captionStrong.copyWith(
                  color: c.ink,
                  fontFeatures: AknNumerals.tabular,
                ),
              ),
            ),
            const SizedBox(width: 16),
            const FuelDrop(fill: 0.64, size: 52, flowing: true),
          ],
        ),
        const _H(
          'Ortam hareketi',
          'Sıra sizdeyken lamba nefes alır; boş durum çizimleri süzülür. '
              'Hareket azaltmada durur.',
        ),
        Row(
          children: [
            SizedBox.square(
              dimension: 28,
              child: AknAmbient(
                period: AknMotion.breathe,
                reverse: true,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c.brand,
                    shape: BoxShape.circle,
                  ),
                ),
                builder: (context, v, child) => Container(
                  width: 14 + 12 * v,
                  height: 14 + 12 * v,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.brand.withValues(alpha: 0.22 * (1 - v) + 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: child,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Kararınızı bekliyor',
                style: t.label.copyWith(color: c.brandInk),
              ),
            ),
          ],
        ),
        const _H('Aşama kayar', 'Onaydan sonra halka bir durak ilerler.'),
        StageStrip(
          stages: const ['Talep', 'Teklif', 'Karar', 'Plan', 'Yolda', 'Teslim'],
          current: _stage,
          yourMove: _stage == 2,
        ),
        _gap(),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AknButton.secondary(
            label: 'Sonraki aşama',
            size: AknButtonSize.small,
            onPressed: () => setState(() => _stage = (_stage + 1) % 7),
          ),
        ),
        const _H(
          'Araç kayar',
          'İlk açılışta yola çıkar, veri değişince süzülür; yoldayken çevresinde '
              'canlı bir halka nefes alır.',
        ),
        TruckRoute(
          key: ValueKey('route$_replay'),
          progress: _route,
          moving: true,
        ),
        Slider(value: _route, onChanged: (v) => setState(() => _route = v)),
        const _H(
          'Logo, başarı, yükleyici',
          'Logo çizilerek gelir; başarı işareti parçacıklarla patlar.',
        ),
        Row(
          key: ValueKey('marks$_replay'),
          children: const [
            LogoMark(size: 64, animate: true),
            SizedBox(width: 24),
            SuccessCheck(size: 64, haptic: false),
            SizedBox(width: 24),
            ChevronSpinner(),
          ],
        ),
        const _H('Aşağı çekip yenile'),
        SizedBox(
          height: 200,
          child: AknCard(
            padding: EdgeInsets.zero,
            child: PullToRefresh(
              onRefresh: _refresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 6,
                itemBuilder: (context, i) => AknListTile(
                  dense: true,
                  title: 'Teslimat ${i + 1}',
                  subtitle: 'Yenilemek için aşağı çekin',
                ),
              ),
            ),
          ),
        ),
        const _H('Açılış ekranı'),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AknButton.secondary(
            label: 'Açılışı göster',
            size: AknButtonSize.small,
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                pageBuilder: (ctx, _, _) => _SplashPreview(),
              ),
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
