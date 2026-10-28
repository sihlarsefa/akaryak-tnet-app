import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../copy.dart';
import '../../data/approval_models.dart';
import '../../shared/layout.dart';

IconData decisionIcon(ApprovalDecision d) => switch (d) {
  ApprovalDecision.approve => PhosphorIconsRegular.check,
  ApprovalDecision.conditionalApprove => PhosphorIconsRegular.listChecks,
  ApprovalDecision.requestInfo => PhosphorIconsFill.chatCircleDots,
  ApprovalDecision.reject => PhosphorIconsRegular.x,
  ApprovalDecision.unknown => PhosphorIconsRegular.question,
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

/// Karar çubuğu (spec A.4, tasarım v3 §4 karar rıhtımı; alttaki buzlu rafta): yalnızca sunucunun
/// verdiği [ApprovalDetail.modes].
///
/// - Üstte tam genişlik birincil "Onayla" (turuncu degrade, beyaz yazı, sıcak parıltı); altında
///   ikinciller yan yana: "Ek bilgi iste" / "Koşullu onayla" ikincil, "Reddet" tehlike düğmesi (48
///   yüksek). Üçten fazla karar varsa fazlası "Diğer kararlar" sayfasında (seçenekler sırayla
///   yükselir).
/// - Çubuk ilk belirişte aşağıdan yükselir; düğmeler basınca küçülür ve hafif titreşir.
/// - Büyük yazıda ikinciller alt alta dizilir.
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
        children: a5Staggered([
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
        ]),
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
          icon: PhosphorIconsRegular.dotsThree,
          semantic: 'Diğer kararlar: ${overflow.map(d.modeLabel).join(', ')}',
          onTap: online ? () => _more(context, overflow) : null,
        ),
      if (onForward != null && hasApprove)
        (
          label: 'Merkeze ilet',
          icon: PhosphorIconsRegular.uploadSimple,
          semantic: null,
          onTap: online ? onForward : null,
        ),
    ];
    final primaryLabel = hasApprove
        ? d.modeLabel(ApprovalDecision.approve)
        : onForward != null
        ? 'Merkeze ilet'
        : null;
    final primary = hasApprove
        ? AknButton(
            label: primaryLabel!,
            expand: true,
            onPressed: act(ApprovalDecision.approve),
          )
        : onForward != null
        ? AknButton(
            label: primaryLabel!,
            expand: true,
            onPressed: online ? onForward : null,
          )
        : null;
    // "Reddet" sağda (en sonda): olumludan olumsuza.
    final rejectLabel = d.modeLabel(ApprovalDecision.reject);
    final ordered = [
      for (final b in secondarySpecs)
        if (b.label != rejectLabel) b,
      for (final b in secondarySpecs)
        if (b.label == rejectLabel) b,
    ];
    final secondaries = [
      for (final b in ordered)
        b.label == rejectLabel
            ? AknButton.danger(
                label: b.label,
                expand: true,
                size: AknButtonSize.medium,
                semanticLabel: b.semantic,
                onPressed: b.onTap,
              )
            : AknButton.secondary(
                label: b.label,
                expand: true,
                size: AknButtonSize.medium,
                semanticLabel: b.semantic,
                onPressed: b.onTap,
              ),
    ];

    /// İkinciller yan yana sığıyor mu (her etiket kendi payında tek satır).
    bool rowFits(double width) {
      if (large || secondarySpecs.isEmpty) return false;
      const gap = 10.0;
      final unit =
          (width - gap * (secondarySpecs.length - 1)) / secondarySpecs.length;
      return secondarySpecs.every(
        (b) => AknButton.fitsOneLine(context, b.label, unit, bordered: true),
      );
    }

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final inRow =
            constraints.hasBoundedWidth && rowFits(constraints.maxWidth);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?primary,
            if (primary != null && secondaries.isNotEmpty)
              const SizedBox(height: 10),
            if (secondaries.isNotEmpty && inRow)
              Row(
                children: [
                  for (var i = 0; i < secondaries.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: secondaries[i]),
                  ],
                ],
              )
            else
              for (var i = 0; i < secondaries.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                secondaries[i],
              ],
          ],
        );
      },
    );

    return A5FadeUp(
      offset: 16,
      duration: AknMotion.stagger,
      curve: AknMotion.emphasizedCurve,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknAnimatedSize(
            alignment: Alignment.bottomCenter,
            child: online
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIconsRegular.cloudSlash,
                          size: 16,
                          color: context.akn.dim,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            ApprovalsCopy.offlineDecision,
                            style: t.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          bar,
        ],
      ),
    );
  }
}
