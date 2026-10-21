import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../widgets/common.dart';

/// Sihirbaz adımlarının ortak parçaları (tasarım v2 §7.9): bölüm başlığı (20/26, sağda isteğe
/// bağlı hayalet düğme), 20 px kenarlı dolgu ve alan hatası satırı.

/// Adım içi bölüm başlığı: "Ürün ve litre", "Teslimat noktası", "Ödeme yöntemi".
class WizardHeading extends StatelessWidget {
  const WizardHeading(this.text, {super.key, this.action, this.top = 20});

  final String text;
  final Widget? action;
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final title = Semantics(
      header: true,
      child: Text(text, style: t.title.copyWith(color: c.ink)),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top, action == null ? 20 : 8, 10),
      child: TitleActionRow(title: title, action: action),
    );
  }
}

/// 20 px yan boşluklu, üstten [top] dolgulu içerik.
class WizardPad extends StatelessWidget {
  const WizardPad(this.child, {super.key, this.top = 12});

  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.fromLTRB(20, top, 20, 0), child: child);
}

/// Alan hatası (§6.10): `error_rounded` 16 + 13/18 500 tehlike rengi; ne yapılacağını söyler.
class WizardError extends StatelessWidget {
  const WizardError(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 8),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: padding,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.error_rounded, size: 16, color: c.danger.fg),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: t.label.copyWith(color: c.danger.fg)),
            ),
          ],
        ),
      ),
    );
  }
}
