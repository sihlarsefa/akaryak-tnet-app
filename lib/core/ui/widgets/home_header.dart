import 'package:flutter/material.dart';

import '../motion.dart';
import '../painters/logo_mark.dart';
import '../theme.dart';
import 'app_scaffold.dart' show NotificationBell;

/// The home header of every role (design v2 §6.2): the 32 px logo tile, the
/// company (`headline` 17/22 600, one line) over the person and role
/// (`bodySmall` 14/18 dim), and the bell on the right.
///
/// ```
/// [»]  Demir Petrol Akaryakıt Ltd. Şti.               [🔔 2]
///      Mehmet Demir, bayi sahibi
/// ```
///
/// Company first, then "Ad Soyad, rol". At text scale ≥ 1.6 the company
/// wraps to two lines and the person line hides. Tapping the names opens the
/// profile ([onOpenProfile]). The bell is [NotificationBell] (shown when the
/// shell's `AppChrome` provides notifications).
///
/// Put it in `AppScaffold(homeHeader: AknHomeHeader(...))`: the scaffold
/// pins it as a 62 px white bar with a hairline once content scrolls under
/// it.
class AknHomeHeader extends StatelessWidget {
  const AknHomeHeader({
    super.key,
    required this.company,
    this.person,
    this.onOpenProfile,
    this.actions = const [],
    this.showBell = true,
    this.profileHint = 'Profili açar',
  });

  /// "Demir Petrol Akaryakıt Ltd. Şti."
  final String company;

  /// "Mehmet Demir, bayi sahibi"
  final String? person;
  final VoidCallback? onOpenProfile;

  /// Extra 44 px icon buttons before the bell.
  final List<Widget> actions;
  final bool showBell;

  /// Screen-reader hint of the names when [onOpenProfile] is set.
  final String profileHint;

  /// The bar height at 1.0× text.
  static const double height = 62;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
    final who = person;
    final names = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          company,
          style: t.headline.copyWith(color: c.ink),
          maxLines: large ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (!large && who != null && who.isNotEmpty)
          Text(
            who,
            style: t.bodySmall.copyWith(height: 18 / 14, color: c.dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    final spoken = [company, if (who != null && who.isNotEmpty) who].join(', ');
    Widget text = Semantics(
      label: spoken,
      button: onOpenProfile != null,
      hint: onOpenProfile == null ? null : profileHint,
      header: true,
      excludeSemantics: true,
      onTap: onOpenProfile,
      child: names,
    );
    if (onOpenProfile != null) {
      text = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AknHaptics.selection();
          onOpenProfile!();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: text,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          20,
          large ? 8 : 0,
          10,
          large ? 6 : 0,
        ),
        child: Row(
          crossAxisAlignment: large
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(top: large ? 6 : 0),
              child: const LogoMark(size: 32, semanticLabel: null),
            ),
            const SizedBox(width: 12),
            Expanded(child: text),
            ...actions,
            if (showBell) const NotificationBell(),
          ],
        ),
      ),
    );
  }
}
