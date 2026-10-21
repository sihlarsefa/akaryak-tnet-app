import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../customer_orders/api.dart';
import '../copy.dart';

/// Limitlerim rotası (spec C.4 derin bağlantı).
const limitsRoute = '/limits';

/// Bir bayideki limit kullanımı: dönem, tutar / litre, kullanılan, kalan ve gösterge.
class LimitMeter extends StatelessWidget {
  const LimitMeter({super.key, required this.limit, this.compact = false});

  final CustomerLimit limit;
  final bool compact;

  String _fmt(double? v) => v == null
      ? Fmt.dash
      : (limit.isLiters ? Fmt.liters(v) : Fmt.money(v, decimals: 0));

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final l = limit;
    if (!l.hasLimit) {
      return Semantics(
        label: '${l.stationTitle}: ${HomeCopy.unlimited}',
        excludeSemantics: true,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.stationTitle, style: t.bodyStrong),
                  Text(
                    'Bu bayide alım limitiniz yok.',
                    style: t.bodySmall.copyWith(color: c.dim),
                  ),
                ],
              ),
            ),
            const StatusChip(
              label: HomeCopy.unlimited,
              tone: AknTone.ok,
              icon: Icons.all_inclusive_rounded,
              size: StatusChipSize.small,
            ),
          ],
        ),
      );
    }
    final pct = (l.usedPct / 100).clamp(0.0, 1.5);
    final label =
        '${l.stationTitle}, ${l.periodLabel}: ${_fmt(l.used)} / ${_fmt(l.amount)} kullanıldı, '
        'kalan ${_fmt(l.remaining)}, %${Fmt.number(l.usedPct, maxFraction: 0)}';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(l.stationTitle, style: t.bodyStrong)),
              Text(l.periodLabel, style: t.caption.copyWith(color: c.dim)),
            ],
          ),
          const SizedBox(height: 8),
          UsageBar(
            value: pct.toDouble(),
            label: 'Kullanılan ${_fmt(l.used)}',
            valueLabel: '%${Fmt.number(l.usedPct, maxFraction: 0)}',
          ),
          const SizedBox(height: 6),
          if (compact)
            Text(
              'Kalan ${_fmt(l.remaining)} · limit ${_fmt(l.amount)}',
              style: t.bodySmall.copyWith(color: c.text),
            )
          else ...[
            FactRow(label: 'Limit', value: _fmt(l.amount)),
            FactRow(label: 'Kullanılan', value: _fmt(l.used)),
            FactRow(
              label: 'Kalan',
              value: _fmt(l.remaining),
              tone: l.usedPct >= 100
                  ? AknTone.danger
                  : (l.usedPct >= 80 ? AknTone.warn : AknTone.ok),
            ),
            if (l.type != null) FactRow(label: 'Tür', value: l.type!),
          ],
        ],
      ),
    );
  }
}

/// Limitlerim (spec A.4): bayi başına limit kullanımı (ana sayfa verisinden).
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
      final limits = home.limits;
      body = PullToRefresh(
        onRefresh: () => ref.read(customerHomeProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            LastUpdatedNote(updatedAt: s.updatedAt, fromCache: s.fromCache),
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Limit, onaylanan ve yoldaki siparişlerinizle dolar. Aşan siparişler '
                  'bayinin finans onayına düşebilir.',
                  style: context.aknText.bodySmall.copyWith(
                    color: context.akn.dim,
                  ),
                ),
              ),
              for (final l in limits)
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: AknCard(child: LimitMeter(limit: l)),
                  ),
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
