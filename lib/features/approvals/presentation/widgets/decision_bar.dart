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

    final secondaryButtons = <Widget>[
      for (final m in inline)
        AknButton.secondary(
          label: d.modeLabel(m),
          icon: decisionIcon(m),
          expand: true,
          onPressed: act(m),
        ),
      if (overflow.isNotEmpty)
        AknButton.secondary(
          label: 'Diğer',
          icon: Icons.more_horiz_rounded,
          expand: true,
          semanticLabel:
              'Diğer kararlar: ${overflow.map(d.modeLabel).join(', ')}',
          onPressed: online ? () => _more(context, overflow) : null,
        ),
      if (onForward != null && hasApprove)
        AknButton.secondary(
          label: 'Merkeze ilet',
          icon: Icons.upload_rounded,
          expand: true,
          onPressed: online ? onForward : null,
        ),
    ];
    Widget? primaryButton(AknButtonSize size) => hasApprove
        ? AknButton(
            label: d.modeLabel(ApprovalDecision.approve),
            icon: Icons.check_rounded,
            expand: true,
            size: size,
            onPressed: act(ApprovalDecision.approve),
          )
        : onForward != null
        ? AknButton(
            label: 'Merkeze ilet',
            icon: Icons.upload_rounded,
            expand: true,
            size: size,
            onPressed: online ? onForward : null,
          )
        : null;

    final Widget bar;
    final inRow = !large && secondaryButtons.length <= 2;
    final primary = primaryButton(
      inRow && secondaryButtons.isNotEmpty
          ? AknButtonSize.medium
          : AknButtonSize.large,
    );
    if (inRow && primary != null) {
      bar = Row(
        children: [
          for (final b in secondaryButtons) ...[
            Expanded(child: b),
            const SizedBox(width: 10),
          ],
          Expanded(flex: secondaryButtons.isEmpty ? 1 : 2, child: primary),
        ],
      );
    } else {
      bar = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (secondaryButtons.isNotEmpty)
            Row(
              children: [
                for (var i = 0; i < secondaryButtons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: secondaryButtons[i]),
                ],
              ],
            ),
          if (secondaryButtons.isNotEmpty && primary != null)
            const SizedBox(height: 8),
          ?primary,
        ],
      );
    }

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
