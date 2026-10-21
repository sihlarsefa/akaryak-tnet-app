import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Ayar grubu (tasarım v2 §4.5, §7.17): beyaz grup kutusu (1 px çizgi, r12, gölgesiz), içinde ince
/// çizgiyle ayrılmış satırlar; kenarlardan 20 px.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children, this.margin});

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final c in children)
        if (c is! SizedBox || c.width != 0 || c.height != 0) c,
    ];
    return AknCard(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: AknSpace.page),
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Ayar satırı (§6.8): 24 px soluk ikon (kutusuz; durum taşıyorsa tonun rengi), başlık / açıklama,
/// isteğe bağlı sağ öğe (lamba, değer), dokununca ok.
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
                    ? Icons.open_in_new_rounded
                    : Icons.chevron_right_rounded,
                color: c.dim,
                size: external ? 18 : 22,
              ));
    final tn = destructive ? AknTone.danger : tone;
    final iconColor = tn == null || tn == AknTone.neutral || tn == AknTone.info
        ? c.dim
        : c.tone(tn).fg;
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.surfaceAlt,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Icon(icon, size: 24, color: iconColor),
                const SizedBox(width: 16),
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
    );
  }
}

/// Anahtarlı ayar satırı: satırın tamamı dokunulabilir; ekran okuyucu tek düğüm olarak okur.
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
        onTap: enabled ? () => onChanged!(!value) : null,
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Icon(icon, size: 24, color: c.dim),
              const SizedBox(width: 16),
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

/// Bölüm başlığı (profilde sıkı boşluklarla).
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SectionHeader(
    title: title,
    subtitle: subtitle,
    padding: const EdgeInsets.fromLTRB(AknSpace.page, 24, 16, 8),
  );
}

/// Alt eylem çubuğunun içeriği: düğmeyi yüksekliğine sığdırır (genişletilmiş `AknButton` aksi hâlde
/// tüm yüksekliği kaplar).
Widget barOf(Widget child) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [child],
);
