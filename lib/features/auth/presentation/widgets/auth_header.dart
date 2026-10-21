import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// Giriş ekranlarının lacivert başlığı: » işareti (bir kez çizilir), kelime işareti, "Siparişten
/// teslimata" ve canlı olmayan derlemelerde ortam rozeti. Durum çubuğu boşluğunu kendisi bırakır.
class AuthHeader extends ConsumerWidget {
  const AuthHeader({super.key, this.compact = false});

  /// Kısa başlık (durum ekranları).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(appEnvProvider);
    final top = MediaQuery.paddingOf(context).top;
    return AknHeroPanel(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AknRadius.xl),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        top + (compact ? 20 : 32),
        24,
        compact ? 20 : 28,
      ),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LogoMark(
                    size: compact ? 40 : 52,
                    animate: true,
                    semanticLabel: null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: env.isProd
                          ? const SizedBox.shrink()
                          : _EnvBadge(label: env.badge),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 16),
              AknWordmark(fontSize: compact ? 22 : 26, onDark: true),
              const SizedBox(height: 4),
              Text(AuthCopy.tagline, style: t.body.copyWith(color: c.dim)),
            ],
          );
        },
      ),
    );
  }
}

class _EnvBadge extends StatelessWidget {
  const _EnvBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.pillAll,
        border: Border.all(color: c.lineStrong),
      ),
      child: Text(
        label,
        style: t.captionStrong.copyWith(color: c.ink),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
