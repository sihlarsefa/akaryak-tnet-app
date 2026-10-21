import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/push/unread_count_provider.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../application/inbox_controller.dart';
import '../copy.dart';
import '../data/notification_models.dart';
import '../notifications_paths.dart';
import 'widgets/notification_tile.dart';

/// Bildirimler (spec A.4 A8): güne göre gruplu liste, okunmamış noktası, kaydırınca okundu, dokununca
/// derin bağlantı (erişim yoksa burada kalır), "Tümü / Okunmamış", tümünü okundu say, ayarlar.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(inboxControllerProvider);
    final badge = ref.watch(unreadCountProvider.select((u) => u.notifications));
    final ctl = ref.read(inboxControllerProvider.notifier);
    final canMarkAll = s.unreadCount > 0 || (badge > 0 && !s.loading);
    return AppScaffold(
      title: NotificationsCopy.title,
      showBell: false,
      refreshing: s.refreshing,
      actions: [
        AknIconButton(
          icon: Icons.done_all_rounded,
          semanticLabel: NotificationsCopy.markAll,
          onPressed: canMarkAll ? () => _markAll(context, ref) : null,
        ),
        AknIconButton(
          icon: Icons.tune_rounded,
          semanticLabel: NotificationsCopy.settings,
          onPressed: () => context.push(NotificationsPaths.settings),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          // Çipler (kaydırılabilir; büyük yazıda sığar, seçili olan işaretli).
          FilterChips<bool>(
            options: [
              const FilterOption(value: false, label: NotificationsCopy.all),
              FilterOption(
                value: true,
                label: NotificationsCopy.unread,
                count: badge > 0 ? badge : null,
              ),
            ],
            selected: {s.unreadOnly},
            allowEmpty: false,
            onChanged: (v) {
              if (v.isNotEmpty) unawaited(ctl.setUnreadOnly(v.first));
            },
          ),
          if (s.fromCache)
            AknBanner(
              tone: AknTone.neutral,
              icon: Icons.cloud_off_rounded,
              message:
                  '${NotificationsCopy.offlineCached} ${NotificationsCopy.lastUpdated} ${Fmt.time(s.loadedAt)}',
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            ),
          Expanded(child: _Body(state: s)),
        ],
      ),
    );
  }

  static Future<void> _markAll(BuildContext context, WidgetRef ref) async {
    final view = View.maybeOf(context);
    final f = await ref.read(inboxControllerProvider.notifier).markAllRead();
    if (f != null) {
      AppToast.error(f.message);
    } else if (view != null) {
      // Görsel geri bildirim noktaların kaybolmasıdır; ekran okuyucuya duyurulur.
      unawaited(
        SemanticsService.sendAnnouncement(
          view,
          NotificationsCopy.markAllDone,
          TextDirection.ltr,
        ),
      );
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final InboxState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final ctl = ref.read(inboxControllerProvider.notifier);
    if (s.loading && s.items.isEmpty) {
      return const SkeletonList(itemCount: 6, lines: 2);
    }
    final error = s.error;
    if (error != null && s.items.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: error is OfflineFailure
              ? EmptyState(
                  title: NotificationsCopy.offlineTitle,
                  message: NotificationsCopy.offlineMessage,
                  illustration: AknIllustration.offline,
                  actionLabel: NotificationsCopy.retry,
                  onAction: () => unawaited(ctl.refresh()),
                )
              : ErrorState(
                  title: NotificationsCopy.errorTitle,
                  message: error.message,
                  traceId: _shortTrace(error.traceId),
                  onRetry: () => unawaited(ctl.refresh()),
                ),
        ),
      );
    }
    if (s.items.isEmpty) {
      return PullToRefresh(
        onRefresh: ctl.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 24),
            if (s.unreadOnly)
              EmptyState(
                title: NotificationsCopy.emptyUnreadTitle,
                message: NotificationsCopy.emptyUnreadMessage,
                illustration: AknIllustration.notifications,
                secondaryLabel: NotificationsCopy.showAll,
                onSecondary: () => unawaited(ctl.setUnreadOnly(false)),
              )
            else
              const EmptyState(
                title: NotificationsCopy.emptyTitle,
                message: NotificationsCopy.emptyMessage,
                illustration: AknIllustration.notifications,
              ),
          ],
        ),
      );
    }

    final entries = _entries(s.items);
    final footer = s.hasMore || s.moreError != null;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0 &&
            n.metrics.extentAfter < 480 &&
            s.hasMore &&
            !s.loadingMore &&
            s.moreError == null) {
          unawaited(ctl.loadMore());
        }
        return false;
      },
      child: PullToRefresh(
        onRefresh: ctl.refresh,
        child: StaggerScope(
          key: ValueKey('inbox-${s.unreadOnly}'),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: entries.length + (footer ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= entries.length) {
                return _Footer(
                  loading: s.loadingMore,
                  error: s.moreError,
                  onRetry: () => unawaited(ctl.loadMore()),
                );
              }
              final e = entries[i];
              if (e.header != null) {
                return SectionHeader(
                  title: e.header!,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                );
              }
              final n = e.item!;
              return StaggerItem(
                index: i,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NotificationTile(
                      notification: n,
                      onTap: () => _open(context, ref, n),
                      onMarkRead: () => unawaited(_markRead(ref, n)),
                    ),
                    if (e.dividerAfter)
                      const Divider(height: 1, indent: 68, endIndent: 16),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static Future<void> _markRead(WidgetRef ref, UserNotification n) async {
    final f = await ref.read(inboxControllerProvider.notifier).markRead(n.id);
    if (f != null) AppToast.error(f.message);
  }

  void _open(BuildContext context, WidgetRef ref, UserNotification n) {
    unawaited(_markRead(ref, n));
    final target = RouteAccess.resolvePushRoute(
      n.route,
      ref.read(accessPolicyProvider),
      ref.read(appConfigProvider).features,
    );
    if (target == AppRoutes.notifications) {
      final r = n.route;
      if (r != null && r.trim().isNotEmpty && r.trim() != target) {
        AppToast.info(NotificationsCopy.routeUnavailable);
      }
      return;
    }
    context.push(target);
  }
}

/// Liste satırı: gün başlığı ya da bildirim.
class _Entry {
  const _Entry.header(this.header) : item = null, dividerAfter = false;
  const _Entry.item(this.item, {this.dividerAfter = false}) : header = null;

  final String? header;
  final UserNotification? item;
  final bool dividerAfter;
}

List<_Entry> _entries(List<UserNotification> items) {
  final out = <_Entry>[];
  String? current;
  for (var i = 0; i < items.length; i++) {
    final n = items[i];
    final label = dayLabel(n.createdAt);
    if (label != current) {
      out.add(_Entry.header(label));
      current = label;
    }
    final next = i + 1 < items.length ? items[i + 1] : null;
    final sameGroup = next != null && dayLabel(next.createdAt) == label;
    out.add(_Entry.item(n, dividerAfter: sameGroup));
  }
  return out;
}

/// Gün başlığı: "Bugün", "Dün", bu hafta gün adı, sonra "18 Ekim" (başka yıl: "18 Ekim 2025").
String dayLabel(DateTime instant, {DateTime? now}) {
  final n = now ?? TrTime.now();
  final diff = TrTime.dayDiff(instant, n);
  if (diff <= 0) return NotificationsCopy.today;
  if (diff == 1) return NotificationsCopy.yesterday;
  if (diff < 7) return Fmt.weekday(instant);
  final w = TrTime.wall(instant);
  final label = '${w.day} ${Fmt.monthNames[w.month - 1]}';
  return w.year == TrTime.wall(n).year ? label : '$label ${w.year}';
}

String? _shortTrace(String? traceId) {
  if (traceId == null || traceId.isEmpty) return null;
  return traceId.length <= 8 ? traceId : traceId.substring(0, 8);
}

class _Footer extends StatelessWidget {
  const _Footer({required this.loading, required this.error, this.onRetry});

  final bool loading;
  final AppFailure? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              NotificationsCopy.loadMoreFailed,
              style: context.aknText.bodySmall,
            ),
            AknButton.ghost(
              label: NotificationsCopy.retry,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: ChevronSpinner(size: 22)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: AknButton.ghost(
          label: NotificationsCopy.loadMore,
          icon: Icons.expand_more_rounded,
          onPressed: onRetry,
        ),
      ),
    );
  }
}
