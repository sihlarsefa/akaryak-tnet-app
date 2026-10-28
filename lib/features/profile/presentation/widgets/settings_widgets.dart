import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Ayar grubu (tasarım v3 §4): sayfanın üstünde yüzen beyaz kart (r20, kart gölgesi; koyu temada ince
/// çizgi), içinde simge karosundan sonra başlayan ince çizgilerle ayrılmış satırlar; kenarlardan 20 px.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children, this.margin});

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final rows = [
      for (final c in children)
        if (c is! SizedBox || c.width != 0 || c.height != 0) c,
    ];
    return AknCard(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: AknSpace.page),
      padding: EdgeInsets.zero,
      radius: 20,
      child: ClipRRect(
        borderRadius: AknRadius.card,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 66),
                  child: Divider(height: 1, thickness: 1, color: c.lineSoft),
                ),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Satırın simge karosu (tasarım v3 §4): 36 px, r11; dinlenirken kuyu (`surfaceAlt`) ve ink simge, durum
/// taşıyorsa tonun yumuşak kuyusu ve rengi.
class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile({super.key, required this.icon, this.tone});

  final IconData icon;
  final AknTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tn = tone;
    final quiet = tn == null || tn == AknTone.neutral || tn == AknTone.info;
    final tc = quiet ? null : c.tone(tn);
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.base),
        curve: AknMotion.standard,
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: tc?.bg ?? c.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: tc?.fg ?? c.ink),
      ),
    );
  }
}

/// Ayar satırı (tasarım v3): 36 px simge karosu, başlık (`bodyStrong`) / açıklama (`bodySmall` dim),
/// isteğe bağlı sağ öğe (lamba, değer), dokununca ok. Basınca kuyu rengine döner ve hafifçe içe çöker.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tone,
    this.external = false,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final AknTone? tone;

  /// Uygulama dışında / tarayıcıda açılır (↗ ikonu).
  final bool external;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tail =
        trailing ??
        (onTap == null
            ? null
            : Icon(
                external
                    ? PhosphorIconsRegular.arrowSquareOut
                    : PhosphorIconsRegular.caretRight,
                color: c.dim,
                size: 18,
              ));
    final tn = destructive ? AknTone.danger : tone;
    return Semantics(
      button: onTap != null,
      child: PressScale(
        enabled: onTap != null,
        scale: 0.985,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  AknHaptics.selection();
                  onTap!();
                },
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceAlt,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              child: Row(
                children: [
                  SettingsIconTile(icon: icon, tone: tn),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: t.bodyStrong.copyWith(
                            color: destructive ? c.danger.fg : c.ink,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (tail != null) ...[const SizedBox(width: 8), tail],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anahtarlı ayar satırı: satırın tamamı dokunulabilir (turuncu anahtar); ekran okuyucu tek düğüm olarak
/// okur. Açıkken simge karosu yumuşak turuncuya döner.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;

  /// null: kapalı (cihaz desteklemiyor, kaydediliyor).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final enabled = onChanged != null;
    return MergeSemantics(
      child: InkWell(
        onTap: enabled
            ? () {
                AknHaptics.selection();
                onChanged!(!value);
              }
            : null,
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              SettingsIconTile(
                icon: icon,
                tone: value && enabled ? AknTone.brand : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: t.bodyStrong.copyWith(color: c.ink)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: t.bodySmall.copyWith(color: c.dim),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Olgu satırı (tasarım v3): 34 px simge karosu, üstte etiket (`caption`), altında değer (`bodyStrong`,
/// eş genişlikte rakamlar). [warm] kahraman kartın sıcak karosu (profil başı: `plateIconFill` +
/// `plateAccent`), değilse kuyu (`surfaceAlt`) ve ink simge. Ekran okuyucu "etiket, değer" diye tek düğüm
/// okur.
class SettingsFactLine extends StatelessWidget {
  const SettingsFactLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.warm = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: warm ? c.plateIconFill : c.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: warm ? c.plateAccent : c.ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: t.caption.copyWith(color: c.dim)),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: t.bodyStrong.copyWith(
                      color: c.ink,
                      fontFeatures: AknNumerals.tabular,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bölüm başlığı (profilde: üstte 28, altta 10).
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SectionHeader(
    title: title,
    subtitle: subtitle,
    padding: const EdgeInsets.fromLTRB(AknSpace.page, 28, 16, 10),
  );
}

/// Bir bölümün tek seferlik girişi (tasarım v3 §5 sıralı giriş): [index] × 45 ms sonra 18 px aşağıdan
/// kayarak gelir; opaklık hızla, kayma uzun ve yumuşak tamamlanır. Ölçek yok (dokunma hedefleri hep
/// tam boy), yapısı hiç değişmez (içindeki durum korunur). Azaltılmış harekette doğrudan çizilir.
class SettingsReveal extends StatefulWidget {
  const SettingsReveal({super.key, required this.index, required this.child});

  /// Sıra (0 = ilk); 7'den sonrakiler yedinciyle birlikte gelir.
  final int index;
  final Widget child;

  @override
  State<SettingsReveal> createState() => _SettingsRevealState();
}

class _SettingsRevealState extends State<SettingsReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  static final _move = CurveTween(curve: AknMotion.emphasizedCurve);
  static final _fade = CurveTween(
    curve: const Interval(0, 0.4, curve: Curves.easeOut),
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
    final delay = Duration(milliseconds: 45 * widget.index.clamp(0, 7));
    if (delay == Duration.zero) {
      unawaited(_c.forward());
    } else {
      _timer = Timer(delay, () {
        if (mounted) unawaited(_c.forward());
      });
    }
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
        offset: Offset(0, 18 * (1 - _move.evaluate(_c))),
        child: child,
      ),
    ),
  );
}

/// Alt eylem çubuğunun içeriği: düğmeyi yüksekliğine sığdırır (genişletilmiş `AknButton` aksi hâlde
/// tüm yüksekliği kaplar).
Widget barOf(Widget child) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [child],
);
