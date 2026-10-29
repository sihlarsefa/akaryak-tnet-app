import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/turkish_text.dart';
import '../../customer_orders/api.dart';
import '../copy.dart';

/// Limitlerim rotası (spec C.4 derin bağlantı).
const limitsRoute = '/limits';

/// Bir bayideki limit kullanımı, kart satırı olarak (tasarım v3 §4 AknListTile): durumun
/// kuyusunda gösterge karosu, bayi ve dönem solda, tablo rakamlı kalan tutar sağda ("360.000 ₺ /
/// Kalan"), altında soldan dolan kullanım çubuğu (%80 üstü uyarı, %100 üstü tehlike rengi ve
/// sözcükle). Tam görünümde ([compact] false) kullanılan / limit ve tür satırı da yazılır.
/// Limitsiz bayide çubuk yok, sağda "Limitsiz".
class LimitMeter extends StatelessWidget {
  const LimitMeter({
    super.key,
    required this.limit,
    this.compact = false,
    this.padding,
  });

  final CustomerLimit limit;
  final bool compact;

  /// Satır dolgusu (varsayılan kart satırı).
  final EdgeInsetsGeometry? padding;

  String _fmt(double? v) => v == null
      ? Fmt.dash
      : (limit.isLiters ? Fmt.liters(v) : Fmt.money(v, decimals: 0));

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final l = limit;
    final titleStyle = t.bodyStrong.copyWith(height: 20 / 15, color: c.ink);
    if (!l.hasLimit) {
      return AknListTile(
        padding: padding,
        titleStyle: titleStyle,
        title: l.stationTitle,
        subtitle: HomeCopy.unlimitedMessage,
        amount: HomeCopy.unlimited,
        semanticLabel: '${l.stationTitle}: ${HomeCopy.unlimited}',
      );
    }
    final pct = (l.usedPct / 100).clamp(0.0, 1.5);
    final pctText = '%${Fmt.number(l.usedPct, maxFraction: 0)}';
    final full = l.usedPct >= 100;
    final near = !full && l.usedPct >= 80;
    final state = full
        ? 'Limit doldu'
        : near
        ? 'Limitinize yaklaştınız'
        : null;
    final label =
        '${l.stationTitle}, ${l.periodLabel}: ${_fmt(l.used)} / ${_fmt(l.amount)} kullanıldı, '
        'kalan ${_fmt(l.remaining)}, $pctText${state == null ? '' : ', $state'}';
    final usedLine = '${_fmt(l.used)} kullanıldı, limit ${_fmt(l.amount)}';
    return AknListTile(
      padding: padding,
      titleStyle: titleStyle,
      title: l.stationTitle,
      subtitle: '${l.periodLabel}, $pctText kullanıldı',
      amount: _fmt(l.remaining),
      amountMeta: 'Kalan',
      semanticLabel: label,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          UsageBar(value: pct.toDouble()),
          if (state != null) ...[
            const SizedBox(height: 8),
            AknLamp(
              label: state,
              tone: full ? AknTone.danger : AknTone.warn,
              size: AknLampSize.small,
            ),
          ],
          if (!compact) ...[
            const SizedBox(height: 8),
            Text(usedLine, style: t.bodySmall.copyWith(color: c.dim)),
            if (l.type != null)
              Text(
                'Limit türü: ${TurkishText.lower(l.type!)}',
                style: t.bodySmall.copyWith(color: c.dim),
              ),
          ],
        ],
      ),
    );
  }
}

/// Limitler (spec A.4; tasarım v4): bayi başına limit kullanımı (ana sayfa verisinden); tek defter,
/// her bayi bir satır; satırlar defterin içine dökülür.
class LimitsPage extends ConsumerWidget {
  const LimitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(customerHomeProvider);
    final home = s.data;
    Widget body;
    if (home == null && s.isFirstLoad) {
      body = const SkeletonList(itemCount: 2, lines: 3, leading: false);
    } else if (home == null) {
      body = Center(
        child: SingleChildScrollView(
          child: FailureView(
            failure: s.error ?? const UnknownFailure(),
            onRetry: () => ref.read(customerHomeProvider.notifier).refresh(),
          ),
        ),
      );
    } else {
      final limits = [...home.limits]
        ..sort((a, b) {
          if (a.hasLimit != b.hasLimit) return a.hasLimit ? -1 : 1;
          return b.usedPct.compareTo(a.usedPct);
        });
      body = PullToRefresh(
        onRefresh: () => ref.read(customerHomeProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: 32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            LastUpdatedNote(
              updatedAt: s.updatedAt,
              fromCache: s.fromCache,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            ),
            if (limits.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: EmptyState(
                  title: HomeCopy.limitsEmpty,
                  message: HomeCopy.limitsEmptyMessage,
                  illustration: AknIllustration.payments,
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  HomeCopy.limitsNote,
                  style: context.aknText.bodySmall.copyWith(
                    color: context.akn.dim,
                  ),
                ),
              ),
              // Tek defter: her bayi bir satır (kutu içinde kutu yok).
              AknLedger(
                pour: true,
                children: [
                  for (final l in limits)
                    LimitMeter(
                      limit: l,
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    }
    return AppScaffold(
      title: HomeCopy.limits,
      refreshing: s.refreshing,
      body: body,
    );
  }
}
