import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../copy.dart';
import '../../data/approval_models.dart';

IconData decisionIcon(ApprovalDecision d) => switch (d) {
  ApprovalDecision.approve => Icons.check_rounded,
  ApprovalDecision.conditionalApprove => Icons.rule_rounded,
  ApprovalDecision.requestInfo => Icons.contact_support_rounded,
  ApprovalDecision.reject => Icons.close_rounded,
  ApprovalDecision.unknown => Icons.help_outline_rounded,
};

String decisionDescription(ApprovalDecision d) => switch (d) {
  ApprovalDecision.approve => 'Talebi olduğu gibi onaylayın.',
  ApprovalDecision.conditionalApprove =>
    'Ödeme ya da kredi koşullarını değiştirerek onaylayın.',
  ApprovalDecision.requestInfo =>
    'Talep edenden bilgi ya da belge isteyin; talep yanıt gelene kadar bekler.',
  ApprovalDecision.reject => 'Gerekçe yazarak reddedin.',
  ApprovalDecision.unknown => '',
};

/// Çubuktaki ikincil karar düğmesi.
typedef _Secondary = ({
  String label,
  IconData icon,
  String? semantic,
  VoidCallback? onTap,
});

/// Karar çubuğu (spec A.4): yalnızca sunucunun verdiği [ApprovalDetail.modes].
///
/// - Olumlu karar büyük turuncu düğme; "Reddet" yanında. Üçten fazla karar varsa "Ek bilgi iste" ve
///   "Koşullu onayla" "Diğer kararlar" sayfasında (çubuk tek satır kalır).
/// - Büyük yazıda düğmeler iki satıra dizilir.
/// - Çevrimdışıyken düğmeler kapalıdır (spec C.4a).
class DecisionBar extends ConsumerWidget {
  const DecisionBar({
    super.key,
    required this.detail,
    required this.onDecision,
    this.onForward,
  });

  final ApprovalDetail detail;
  final void Function(ApprovalDecision decision) onDecision;

  /// Ön kayıt "Merkeze ilet" (yetkinlik approve.finance.lead).
  final VoidCallback? onForward;

  Future<void> _more(BuildContext context, List<ApprovalDecision> modes) async {
    final picked = await showAppSheet<ApprovalDecision>(
      context: context,
      title: 'Diğer kararlar',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in modes)
            AknListTile(
              leadingIcon: decisionIcon(m),
              leadingTone: m == ApprovalDecision.reject
                  ? AknTone.danger
                  : AknTone.brand,
              title: detail.modeLabel(m),
              subtitle: decisionDescription(m),
              subtitleMaxLines: 3,
              onTap: () => Navigator.of(ctx).pop(m),
            ),
        ],
      ),
    );
    if (picked != null) onDecision(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    final t = context.aknText;
    final d = detail;
    final large = MediaQuery.textScalerOf(context).scale(10) > 13;
    final hasApprove = d.can(ApprovalDecision.approve);
    final secondary = [
      for (final m in const [
        ApprovalDecision.reject,
        ApprovalDecision.requestInfo,
        ApprovalDecision.conditionalApprove,
      ])
        if (d.can(m)) m,
    ];
    // Satırda en çok iki ikincil düğme: fazlası "Diğer kararlar"da.
    final inline = secondary.length > 2 ? [secondary.first] : secondary;
    final overflow = secondary.length > 2
        ? secondary.sublist(1)
        : const <ApprovalDecision>[];
    VoidCallback? act(ApprovalDecision m) =>
        online ? () => onDecision(m) : null;

    final secondarySpecs = <_Secondary>[
      for (final m in inline)
        (
          label: d.modeLabel(m),
          icon: decisionIcon(m),
          semantic: null,
          onTap: act(m),
        ),
      if (overflow.isNotEmpty)
        (
          label: 'Diğer',
          icon: Icons.more_horiz_rounded,
          semantic: 'Diğer kararlar: ${overflow.map(d.modeLabel).join(', ')}',
          onTap: online ? () => _more(context, overflow) : null,
        ),
      if (onForward != null && hasApprove)
        (
          label: 'Merkeze ilet',
          icon: Icons.upload_rounded,
          semantic: null,
          onTap: online ? onForward : null,
        ),
    ];
    List<Widget> secondaryButtons({required bool icons}) => [
      for (final b in secondarySpecs)
        AknButton.secondary(
          label: b.label,
          icon: icons ? b.icon : null,
          expand: true,
          semanticLabel: b.semantic,
          onPressed: b.onTap,
        ),
    ];
    final primaryLabel = hasApprove
        ? d.modeLabel(ApprovalDecision.approve)
        : onForward != null
        ? 'Merkeze ilet'
        : null;
    Widget? primaryButton(AknButtonSize size) => hasApprove
        ? AknButton(
            label: primaryLabel!,
            icon: Icons.check_rounded,
            expand: true,
            size: size,
            onPressed: act(ApprovalDecision.approve),
          )
        : onForward != null
        ? AknButton(
            label: primaryLabel!,
            icon: Icons.upload_rounded,
            expand: true,
            size: size,
            onPressed: online ? onForward : null,
          )
        : null;

    /// Tek satır (ikinciller simgesiz, olumlu karar iki pay): her etiket tek satırda bütün
    /// sığıyorsa. Sığmıyorsa ikinciller kendi satırında, olumlu karar tam genişlikte.
    bool rowFits(double width) {
      if (large || secondarySpecs.length > 2) return false;
      if (primaryLabel == null || secondarySpecs.isEmpty) return true;
      const gap = 10.0;
      final unit =
          (width - gap * secondarySpecs.length) / (secondarySpecs.length + 2);
      return secondarySpecs.every(
            (b) =>
                AknButton.fitsOneLine(context, b.label, unit, bordered: true),
          ) &&
          AknButton.fitsOneLine(context, primaryLabel, unit * 2, icon: true);
    }

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final inRow =
            constraints.hasBoundedWidth && rowFits(constraints.maxWidth);
        if (inRow) {
          final buttons = secondaryButtons(icons: false);
          final primary = primaryButton(
            buttons.isEmpty ? AknButtonSize.large : AknButtonSize.medium,
          );
          if (primary != null) {
            return Row(
              children: [
                for (final b in buttons) ...[
                  Expanded(child: b),
                  const SizedBox(width: 10),
                ],
                Expanded(flex: buttons.isEmpty ? 1 : 2, child: primary),
              ],
            );
          }
        }
        final buttons = secondaryButtons(icons: true);
        final primary = primaryButton(AknButtonSize.large);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (buttons.isNotEmpty)
              Row(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: buttons[i]),
                  ],
                ],
              ),
            if (buttons.isNotEmpty && primary != null)
              const SizedBox(height: 8),
            ?primary,
          ],
        );
      },
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!online)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              ApprovalsCopy.offlineDecision,
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        bar,
      ],
    );
  }
}
