import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../widgets/common.dart';

/// Sihirbaz adımlarının ortak parçaları (tasarım v3): bölüm başlığı (18/24 800, sağda isteğe
/// bağlı hayalet düğme), 20 px kenarlı dolgu, alan hatası satırı (titreyerek belirir), adım
/// listesi (bölümler birbiri ardına yükselerek gelir) ve listelerin dip boşluğu (buzlu çubuğun
/// altından kayabilsin diye).

/// Adım listesinin dolgusu: altta buzlu çubuğun yüksekliği (MediaQuery alt boşluğu) + 24.
EdgeInsets wizardListPadding(BuildContext context) =>
    EdgeInsets.only(top: 4, bottom: 24 + MediaQuery.paddingOf(context).bottom);

/// Adımın kaydırılan içeriği (tasarım v3 §5): adım açılınca (paylaşılan eksen geçişiyle birlikte)
/// bölümler birbiri ardına yükselerek yerine oturur ([A2RiseScope]); sonradan eklenen bölüm
/// (uyarı, yeni satır) kendi yerinde belirir. Bölümler [WizardCascade] ile sarılır ([A2Rise]:
/// giriş bitince içerik yeniden kurulmaz, yazı alanları odağını korur); liste buzlu alt çubuğun
/// altından kayabilsin diye dip boşlukludur.
class WizardStepList extends StatelessWidget {
  const WizardStepList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => A2RiseScope(
    child: ListView(
      padding: wizardListPadding(context),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    ),
  );
}

/// Adım bölümlerinin giriş sırası: `enter(id, bölüm)` her çağrıda sıradaki [A2Rise]'ı verir.
/// [id] bölümün kimliğidir; araya bir hata ya da uyarı girince diğer bölümler yeniden oynamaz.
class WizardCascade {
  int _next = 0;

  Widget call(Object id, Widget child) =>
      A2Rise(key: ValueKey(id), index: _next++, child: child);

  /// İçinde kendi sıralı öğelerini taşıyan bölüm için [n] sıra ayırır; ilk sırayı verir.
  int take(int n) {
    final first = _next;
    _next += n;
    return first;
  }
}

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
      child: Text(text, style: a2SectionTitle(t, c)),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top, action == null ? 20 : 8, 12),
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

/// Alan hatası (§6.10): `warningCircle` 16 + 13/18 tehlike rengi; ne yapılacağını söyler. Belirince
/// üç kısa ±6 px titreşimle dikkati çeker (v3 §5, bir kez; hareket azaltıldığında durgun).
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
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AknMotion.of(context, const Duration(milliseconds: 420)),
          builder: (context, v, child) => Transform.translate(
            offset: Offset(math.sin(v * 3 * 2 * math.pi) * 6 * (1 - v), 0),
            child: child,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  PhosphorIconsFill.warningCircle,
                  size: 16,
                  color: c.danger.fg,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text, style: t.label.copyWith(color: c.danger.fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
