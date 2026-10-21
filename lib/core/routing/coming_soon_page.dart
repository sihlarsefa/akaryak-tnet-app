import 'package:flutter/material.dart';

import '../ui/ui.dart';

/// Yer tutucu ekran ("Yakında"). Aşama 0'da her özellik rotası bunu gösterir; özellik ajanları kendi
/// ekranlarıyla değiştirir (spec C.3).
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({
    super.key,
    required this.title,
    this.message,
    this.illustration = AknIllustration.inbox,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String? message;
  final AknIllustration illustration;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: title,
      subtitle: subtitle,
      body: Center(
        child: EmptyState(
          title: 'Yakında',
          message: message ?? '$title ekranı hazırlanıyor.',
          illustration: illustration,
        ),
      ),
    );
  }
}
