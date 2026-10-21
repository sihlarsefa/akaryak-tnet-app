import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// Sıradaki durağın eylem rafı (tahta ekran 6; ekranın altına yapışık): iki 64 px düğme. Birincil
/// olan tırı izler (§7.11): noktaya uzaktayken "Yol tarifi", 300 m içinde (ya da konum
/// bilinmiyorsa) "Teslim et". Yerler sabittir — solda "Yol tarifi", sağda iş düğmesi ("Teslim et",
/// planlıysa "Yola çık") — yalnızca vurgu yer değiştirir; parmak hep aynı yere gider.
/// Yazı büyüyüp iki düğme yan yana sığmazsa alt alta dizilir (iş düğmesi altta, başparmağa yakın).
class DriverStopDock extends StatelessWidget {
  const DriverStopDock({
    super.key,
    required this.onNavigate,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.actionIsPrimary,
    this.actionSemanticLabel,
    this.navigateSemanticLabel,
  });

  final VoidCallback? onNavigate;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  /// İş düğmesi birincil mi (değilse "Yol tarifi" birincildir).
  final bool actionIsPrimary;
  final String? actionSemanticLabel;
  final String? navigateSemanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget navigate(bool expand) => actionIsPrimary
        ? AknButton.secondary(
            label: DriverCopy.actionNavigate,
            icon: Icons.directions_outlined,
            expand: expand,
            semanticLabel: navigateSemanticLabel,
            onPressed: onNavigate,
          )
        : AknButton(
            label: DriverCopy.actionNavigate,
            icon: Icons.directions_outlined,
            expand: expand,
            semanticLabel: navigateSemanticLabel,
            onPressed: onNavigate,
          );
    Widget action(bool expand) => actionIsPrimary
        ? AknButton(
            label: actionLabel,
            icon: actionIcon,
            expand: expand,
            semanticLabel: actionSemanticLabel,
            onPressed: onAction,
          )
        : AknButton.secondary(
            label: actionLabel,
            icon: actionIcon,
            expand: expand,
            semanticLabel: actionSemanticLabel,
            onPressed: onAction,
          );
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final primaryW = (box.maxWidth - gap) * 23 / 43;
        final secondaryW = box.maxWidth - gap - primaryW;
        final navW = actionIsPrimary ? secondaryW : primaryW;
        final actW = actionIsPrimary ? primaryW : secondaryW;
        final side =
            AknButton.fitsOneLine(
              context,
              DriverCopy.actionNavigate,
              navW,
              // Sığmazsa düğme önce kenar boşluğunu daraltır, sonra simgeyi bırakır.
              icon: false,
              bordered: actionIsPrimary,
              size: AknButtonSize.large,
            ) &&
            AknButton.fitsOneLine(
              context,
              actionLabel,
              actW,
              // Sığmazsa düğme önce kenar boşluğunu daraltır, sonra simgeyi bırakır.
              icon: false,
              bordered: !actionIsPrimary,
              size: AknButtonSize.large,
            );
        if (!side) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              navigate(true),
              const SizedBox(height: gap),
              action(true),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: actionIsPrimary ? 20 : 23, child: navigate(true)),
            const SizedBox(width: gap),
            Expanded(flex: actionIsPrimary ? 23 : 20, child: action(true)),
          ],
        );
      },
    );
  }
}
