// Core widget specimens (design v2 §5, §6): the board screens rebuilt from core widgets only (home
// header, plate, lane pager, section headers, ledger rows, lamps, countdowns, route line, stage strip,
// dock, bottom bar, driver mode) plus every design-gallery tab, light and dark, as PNGs at 390 × 844
// (2×) for a visual check against `work/design-v2/screen-*.png`. Not a golden test; skipped unless
//
//   flutter test test/core/ui/core_capture_test.dart --dart-define=AKN_SCREENS_DIR=/abs/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/core/ui/gallery/design_gallery.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Widget _app(Widget home, {required bool dark, double scale = 1}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AknTheme.light(),
  darkTheme: AknTheme.dark(),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  locale: const Locale('tr', 'TR'),
  supportedLocales: const [Locale('tr', 'TR')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: AppChrome(unreadCount: 2, onOpenNotifications: () {}, child: child!),
  ),
  home: home,
);

// ── Shared pieces ───────────────────────────────────────────────────────────

const _months = ['May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki'];

Widget _salesPlate({
  required String icon,
  required String title,
  required String figure,
  required String change,
  required List<PlateReadout> readouts,
  bool compact = false,
}) => AknPlate(
  compact: compact,
  head: PlateHead(
    icon: icon == 'sales' ? Icons.bar_chart_rounded : Icons.payments_outlined,
    title: title,
    period: '1–21 Ekim',
    onMore: () {},
  ),
  figure: PlateFigure(value: figure, unit: '₺'),
  delta: PlateDelta(
    change: change,
    direction: AknDeltaDirection.up,
    sentence: 'geçen ayın aynı günlerine göre',
  ),
  chart: const PlateBars(
    values: [7.1, 7.4, 8.2, 7.6, 8.4, 8.43],
    labels: _months,
    projection: 12.4,
  ),
  below: PlateReadouts(items: readouts),
);

/// The deck look-alike: the plate on top of two paper slips.
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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
      child: Stack(
        clipBehavior: Clip.none,
        children: [slip(26, 26, c.plate), slip(13, 13, c.plate), plate],
      ),
    );
  }
}

Widget _pager(int count) => LanePager(
  count: count,
  index: 0,
  onSelect: (_) {},
  onPositionTap: () {},
  actionLabel: 'İstatistikler',
  onAction: () {},
);

Widget _ownerBar() => AnimatedBottomBar(
  currentIndex: 0,
  onSelected: (_) {},
  items: const [
    AknNavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Ana sayfa',
    ),
    AknNavItem(
      icon: Icons.task_alt_outlined,
      selectedIcon: Icons.task_alt_rounded,
      label: 'Onaylarım',
      badgeCount: 2,
    ),
    AknNavItem(
      icon: Icons.request_quote_outlined,
      selectedIcon: Icons.request_quote_rounded,
      label: 'Teklif masası',
      badgeCount: 6,
    ),
    AknNavItem(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Siparişler',
    ),
    AknNavItem(icon: Icons.menu_rounded, label: 'Diğer'),
  ],
);

Widget _customerBar(int index) => AnimatedBottomBar(
  currentIndex: index,
  onSelected: (_) {},
  centerAction: AknCenterAction(
    icon: Icons.add_rounded,
    label: 'Sipariş ver',
    onPressed: () {},
  ),
  items: const [
    AknNavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Ana sayfa',
    ),
    AknNavItem(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Siparişlerim',
    ),
    AknNavItem(
      icon: Icons.task_alt_outlined,
      selectedIcon: Icons.task_alt_rounded,
      label: 'Onaylarım',
      badgeCount: 1,
    ),
    AknNavItem(icon: Icons.menu_rounded, label: 'Diğer'),
  ],
);

DateTime _in(Duration d) => DateTime.now().toUtc().add(d);

// ── Screens ─────────────────────────────────────────────────────────────────

class _OwnerHome extends StatelessWidget {
  const _OwnerHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _ownerBar(),
      body: AppScaffold(
        homeHeader: AknHomeHeader(
          company: 'Demir Petrol Akaryakıt Ltd. Şti.',
          person: 'Mehmet Demir, bayi sahibi',
          onOpenProfile: () {},
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            AknBandOverlap(
              padding: EdgeInsets.zero,
              child: _Deck(
                plate: _salesPlate(
                  icon: 'sales',
                  title: 'Satış',
                  figure: '8.426.350',
                  change: '%9,4',
                  readouts: const [
                    PlateReadout(
                      label: 'Satılan yakıt',
                      value: '198.400',
                      unit: 'L',
                    ),
                    PlateReadout(
                      label: 'Ortalama',
                      value: '42,47',
                      unit: '₺/L',
                    ),
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
            _pager(8),
            const SizedBox(height: 16),
            const SectionHeader(
              title: 'Sipariş hattı',
              caption: 'şu an, 10:42',
            ),
            const SizedBox(height: 90),
            const SectionHeader(
              title: 'Tüpraş fiyatları',
              caption: 'bugün 06:00, ₺/L',
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: KpiRow(
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
            ),
            const SectionHeader(
              title: 'Tahsilat',
              actionLabel: 'Tümü',
              onAction: _noop,
            ),
            AknListTile(
              title: 'Vadesi geçen 2 ödeme',
              subtitle: 'En eskisi 6 gün gecikmede',
              amount: '184.000 ₺',
              status: const AknLamp(label: 'Gecikmede', tone: AknTone.danger),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}

String _price(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

class _CustomerHome extends StatelessWidget {
  const _CustomerHome({this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _customerBar(0),
      body: AppScaffold(
        homeHeader: AknHomeHeader(
          company: 'Anadolu Lojistik A.Ş.',
          person: 'Selin Aydın, yönetici',
          onOpenProfile: () {},
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            AknBandOverlap(
              padding: EdgeInsets.zero,
              child: _Deck(
                plate: _salesPlate(
                  icon: 'spend',
                  title: 'Bu ay harcama',
                  figure: '1.524.380',
                  change: '%12,8',
                  compact: large,
                  readouts: const [
                    PlateReadout(
                      label: 'Alınan yakıt',
                      value: '36.000',
                      unit: 'L',
                    ),
                    PlateReadout(
                      label: 'Ortalama',
                      value: '42,34',
                      unit: '₺/L',
                    ),
                    PlateReadout(
                      label: 'Ay sonu tahmini',
                      value: '2,25',
                      unit: 'mn ₺',
                      dashed: true,
                    ),
                  ],
                ),
              ),
            ),
            _pager(6),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Karar bekleyen teklifler', count: 1),
            AknListTile(
              title: 'Demir Petrol teklifi',
              subtitle: 'Motorin, 8.000 L, Tuzla Şantiye',
              amount: '338.800,00 ₺',
              amountMeta: '42,35 ₺/L',
              status: AknStatusLine(
                lamp: Text(
                  'Çek ile, 30 gün vade',
                  style: context.aknText.bodySmall,
                ),
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
            SectionHeader(
              title: 'Yolda',
              actionLabel: 'Haritada izle',
              onAction: () {},
            ),
            AknListTile(
              title: 'Pendik Lojistik Merkezi',
              subtitle: '10.000 L motorin, 41 DMR 101',
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('11:20', style: context.aknText.number),
                  Text('tahmini varış', style: context.aknText.bodySmall),
                ],
              ),
              footer: const TruckRoute(progress: 0.62, moving: true),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _Orders extends StatelessWidget {
  const _Orders();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        bottomNavigationBar: _customerBar(1),
        body: AppScaffold(
          title: 'Siparişlerim',
          largeTitle: true,
          showBell: false,
          actions: [
            AknIconButton(
              icon: Icons.tune_rounded,
              semanticLabel: 'Filtrele',
              onPressed: () {},
            ),
          ],
          bottom: const AknTabBar(
            tabs: [
              AknTab(label: 'Aktif', count: 4),
              AknTab(label: 'Geçmiş', count: 28),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: SearchField(hint: 'Sipariş no, ürün, nokta ya da bayi'),
              ),
              const SizedBox(height: 4),
              AknLedger(
                children: [
                  AknListTile(
                    title: 'Motorin, 8.000 L',
                    subtitle: 'Tuzla Şantiye, 22 Ekim',
                    amount: '338.800,00 ₺',
                    amountMeta: '42,35 ₺/L',
                    status: AknStatusLine(
                      lamp: const AknLamp(
                        label: 'Kararınızı bekliyor',
                        tone: AknTone.brand,
                      ),
                      trailing: CountdownBadge(
                        deadline: _in(
                          const Duration(hours: 2, minutes: 57, seconds: 30),
                        ),
                        yourMove: true,
                      ),
                    ),
                    onTap: () {},
                  ),
                  AknListTile(
                    title: 'Motorin, 10.000 L',
                    subtitle: 'Pendik Lojistik Merkezi, bugün',
                    amount: '419.000,00 ₺',
                    amountMeta: '41,90 ₺/L',
                    status: AknStatusLine(
                      lamp: const AknLamp(label: 'Yolda', tone: AknTone.info),
                      trailing: Text(
                        'varış 11:20',
                        style: t.bodySmall.copyWith(
                          color: context.akn.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    footer: const TruckRoute(progress: 0.62, moving: true),
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
                      trailing: Text(
                        'Burak Yılmaz’ın talebi',
                        style: t.bodySmall,
                      ),
                    ),
                    onTap: () {},
                  ),
                  AknListTile(
                    title: 'Kurşunsuz 95, 2.000 L',
                    subtitle: 'Pendik Lojistik Merkezi, 23 Ekim',
                    amount: '89.700 ₺',
                    amountMeta: 'tahmini',
                    status: AknStatusLine(
                      lamp: const AknLamp(
                        label: 'Teklif bekleniyor',
                        tone: AknTone.info,
                      ),
                      trailing: Text('2 bayiye gönderildi', style: t.bodySmall),
                    ),
                    onTap: () {},
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  'Teslim edilen ve iptal olan siparişler Geçmiş sekmesinde.',
                  style: t.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return AppScaffold(
      title: 'SIP-20261021-12002',
      largeTitle: false,
      showBell: false,
      leading: const BackButton(),
      actions: [
        AknIconButton(
          icon: Icons.more_horiz_rounded,
          semanticLabel: 'Diğer seçenekler',
          onPressed: () {},
        ),
      ],
      actionBar: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknButton(label: 'Teklifi onayla', expand: true, onPressed: () {}),
          const SizedBox(height: 10),
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
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Motorin, 8.000 L', style: t.display),
          const SizedBox(height: 4),
          Text('Tuzla Şantiye, 22 Ekim Perşembe teslim', style: t.bodySmall),
          const SizedBox(height: 18),
          const StageStrip(
            stages: [
              'Talep',
              'Onay',
              'Teklif',
              'Karar',
              'Plan',
              'Yolda',
              'Teslim',
            ],
            current: 3,
            yourMove: true,
          ),
          const SizedBox(height: 18),
          AknStatusLine(
            lamp: const AknLamp(
              label: 'Kararınızı bekliyor',
              tone: AknTone.brand,
            ),
            trailing: CountdownBadge(
              deadline: _in(const Duration(hours: 2, minutes: 57, seconds: 30)),
              yourMove: true,
            ),
          ),
          const SizedBox(height: 12),
          const AknPlate(
            head: PlateHead(
              icon: Icons.request_quote_outlined,
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
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: c.ok.fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Çek ile, 30 gün vade. Çek görseli yüklendi.',
                  style: t.body,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const SectionHeader(
            title: 'Sipariş akışı',
            padding: EdgeInsets.fromLTRB(0, 24, 0, 8),
          ),
          const StepTimeline(
            steps: [
              TimelineStep(
                title: 'Sipariş oluşturuldu',
                subtitle: 'Selin Aydın',
                time: '20 Eki 09:12',
                state: TimelineState.done,
              ),
              TimelineStep(
                title: 'Teklif geldi',
                time: 'bugün 10:05',
                state: TimelineState.done,
              ),
              TimelineStep(title: 'Kararınız', state: TimelineState.current),
              TimelineStep(title: 'Sevkiyat', state: TimelineState.upcoming),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverToday extends StatelessWidget {
  const _DriverToday();

  @override
  Widget build(BuildContext context) {
    return AknDriverScope(
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          return Scaffold(
            bottomNavigationBar: AnimatedBottomBar(
              currentIndex: 0,
              onSelected: (_) {},
              items: const [
                AknNavItem(
                  icon: Icons.local_shipping_outlined,
                  selectedIcon: Icons.local_shipping_rounded,
                  label: 'Teslimatlarım',
                ),
                AknNavItem(
                  icon: Icons.notifications_none_rounded,
                  selectedIcon: Icons.notifications_rounded,
                  label: 'Bildirimler',
                  badgeCount: 1,
                ),
                AknNavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  selectedIcon: Icons.chat_bubble_rounded,
                  label: 'Asistan',
                ),
                AknNavItem(
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                  label: 'Profil',
                ),
              ],
            ),
            body: AppScaffold(
              title: 'Teslimatlarım',
              largeTitle: true,
              showBell: false,
              actionBar: Row(
                children: [
                  Expanded(
                    child: AknButton(
                      label: 'Yol tarifi',
                      icon: Icons.directions_outlined,
                      expand: true,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AknButton.secondary(
                      label: 'Teslim et',
                      icon: Icons.task_alt_rounded,
                      expand: true,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Bugün, 21 Ekim Çarşamba',
                          style: t.bodySmall,
                        ),
                      ),
                      const PlateBadge(plate: '41 DMR 101'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const OfflineBanner(offline: true),
                  const SizedBox(height: 12),
                  Text('Sıradaki teslimat, 1 / 3', style: t.bodySmall),
                  const SizedBox(height: 6),
                  Text(
                    'Anadolu Lojistik A.Ş.',
                    style: AknDriverMode.stopName(t),
                  ),
                  Text(
                    'Pendik Lojistik Merkezi, Kurtköy Mah. Ankara Cad. No:12, Pendik',
                    style: t.body,
                  ),
                  const SizedBox(height: 14),
                  const AknPlate(
                    head: PlateHead(
                      leading: AdrPlate(hazard: '30', un: '1202'),
                      title: 'Motorin, bu durakta',
                    ),
                    figure: PlateFigure(value: '10.000', unit: 'L'),
                    below: PlateReadouts(
                      items: [
                        PlateReadout(label: 'Varış', value: '11:20'),
                        PlateReadout(
                          label: 'Kalan yol',
                          value: '18',
                          unit: 'km',
                        ),
                        PlateReadout(
                          label: 'Teslim saati',
                          value: '08:00–18:00',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const FactRow(
                    icon: Icons.door_front_door_outlined,
                    label: 'Kapı notu',
                    value:
                        'Ana kapıda güvenliğe plakayı bildirin; tank arka avluda.',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await loadRealFonts();
  });

  final screens = <String, (Widget, double)>{
    'owner_home': (const _OwnerHome(), 1),
    'customer_home': (const _CustomerHome(), 1),
    'customer_home_2x': (const _CustomerHome(large: true), 2),
    'orders': (const _Orders(), 1),
    'order_detail': (const _OrderDetail(), 1),
    'driver_today': (const _DriverToday(), 1),
  };

  for (final entry in screens.entries) {
    for (final dark in [false, true]) {
      final name = '${entry.key}_${dark ? 'koyu' : 'acik'}';
      testWidgets(name, (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = const Size(390 * 2, 844 * 2);
        tester.view.padding = const FakeViewPadding(
          top: 47 * 2,
          bottom: 34 * 2,
        );
        tester.view.viewPadding = const FakeViewPadding(
          top: 47 * 2,
          bottom: 34 * 2,
        );
        addTearDown(tester.view.reset);
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        final key = GlobalKey();
        final (screen, scale) = entry.value;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: _app(screen, dark: dark, scale: scale),
          ),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _capture(tester, key, 'core/$name');
        await tester.pumpWidget(const SizedBox());
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }
  }

  testWidgets('counter roll frames', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390 * 2, 200 * 2);
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: _app(
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: AknPlate(
                head: PlateHead(
                  icon: Icons.payments_outlined,
                  title: 'Bu ay harcama',
                  period: '1–21 Ekim',
                ),
                figure: PlateFigure(
                  value: '1.524.380',
                  unit: '₺',
                  animate: true,
                ),
              ),
            ),
          ),
          dark: false,
        ),
      ),
    );
    var elapsed = 0;
    for (final ms in [50, 300, 600, 900]) {
      await tester.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
      await _capture(tester, key, 'core/roll_$ms');
    }
    await tester.pumpWidget(const SizedBox());
  }, skip: _outDir.isEmpty);

  const tabs = [
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
  for (final dark in [false, true]) {
    testWidgets('gallery ${dark ? 'koyu' : 'acik'}', (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(390 * 2, 3400 * 2);
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _app(const DesignGalleryPage(), dark: dark),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < tabs.length; i++) {
        final tab = find.widgetWithText(Tab, tabs[i]);
        if (tab.evaluate().isEmpty) continue;
        await tester.ensureVisible(tab);
        await tester.pump();
        await tester.tap(tab);
        for (var k = 0; k < 12; k++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final error = tester.takeException();
        expect(error, isNull, reason: '${tabs[i]}: $error');
        await _capture(
          tester,
          key,
          'gallery/${dark ? 'koyu' : 'acik'}_${i + 1}_${tabs[i]}',
        );
      }
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    }, skip: _outDir.isEmpty);
  }
}
