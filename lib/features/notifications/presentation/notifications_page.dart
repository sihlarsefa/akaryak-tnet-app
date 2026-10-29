import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/push/unread_count_provider.dart';
import '../../../core/routing/app_location.dart';
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

/// Bildirimler (spec A.4 A8; tasarım v4 §5 10): bantta "Bildirimler" ve canlı durum satırı ("3 okunmamış"),
/// okunmamış varken "Tümünü okundu say" (✓✓) ve ayarlar (dişli). Altında tek anahtar [Tümü | Okunmamış n];
/// liste günlere göre birer defter ([AknLedger], satırlar ince çizgiyle; satırlar bir kez dökülür).
/// Kaydırınca okundu, dokununca derin bağlantı (erişim yoksa burada kalır ve açıklar). Bu oturumda
/// açılan bir kaydın bildirimleri okundu sayılır ([InboxController], v4 §3.5).
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(inboxControllerProvider);
    final badge = ref.watch(unreadCountProvider.select((u) => u.notifications));
    final ctl = ref.read(inboxControllerProvider.notifier);
    final unread = badge > 0 ? badge : s.unreadCount;
    final canMarkAll = unread > 0;
    return AppScaffold(
      title: NotificationsCopy.title,
      bandIcon: PhosphorIconsRegular.bell,
      // Zilden açılınca da (itilmiş sayfa) bandıyla görünür; önde geri ya da ana sayfa düğmesi:
      // Diğer'den açılan Onaylar ve Finans gibi (v4 §5 09).
      largeTitle: true,
      status: unread > 0
          ? NotificationsCopy.unreadStatus(unread)
          : NotificationsCopy.calmStatus,
      refreshing: s.refreshing,
      actions: [
        // Yalnızca okunmamış varken (v4 §5 10).
        if (canMarkAll)
          AknIconButton(
            icon: PhosphorIconsRegular.checks,
            semanticLabel: NotificationsCopy.markAll,
            onPressed: () => _markAll(context, ref),
          ),
        AknIconButton(
          icon: PhosphorIconsRegular.gearSix,
          semanticLabel: NotificationsCopy.settings,
          onPressed: () => context.push(NotificationsPaths.settings),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          AknSegmented<bool>(
            segments: [
              const FilterOption(value: false, label: NotificationsCopy.all),
              FilterOption(
                value: true,
                label: NotificationsCopy.unread,
                count: unread > 0 ? unread : null,
              ),
            ],
            value: s.unreadOnly,
            onChanged: (v) => unawaited(ctl.setUnreadOnly(v)),
          ),
          // Çevrimdışı, son kaydedilen liste: çevrimdışı satırını kabuk gösterir; burada yalnızca ne
          // zamandan olduğu (bant yerine sayfa içinde: zilden itilen sayfada da görünür).
          if (s.fromCache)
            _CachedNote(at: s.loadedAt)
          else
            const SizedBox(height: 4),
          // Görünüm değişince içerik dokunulan yöne kayar (v4 §6 Add 6).
          Expanded(
            child: SharedAxisSwitcher(
              reverse: !s.unreadOnly,
              duration: AknMotion.stageStep,
              child: KeyedSubtree(
                key: ValueKey('inbox-${s.unreadOnly}'),
                child: _Body(state: s),
              ),
            ),
          ),
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
              ? EmptyState.compact(
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
              EmptyState.compact(
                title: NotificationsCopy.emptyUnreadTitle,
                message: NotificationsCopy.emptyUnreadMessage,
                illustration: AknIllustration.notifications,
                actionLabel: NotificationsCopy.showAll,
                onAction: () => unawaited(ctl.setUnreadOnly(false)),
              )
            else
              const EmptyState.compact(
                title: NotificationsCopy.emptyTitle,
                message: NotificationsCopy.emptyMessage,
                illustration: AknIllustration.notifications,
              ),
          ],
        ),
      );
    }

    final days = notificationDays(s.items);
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
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          itemCount: days.length + (footer ? 1 : 0),
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final i = days.indexWhere((d) => 'day-${d.label}' == key.value);
            return i < 0 ? null : i;
          },
          itemBuilder: (context, i) {
            if (i >= days.length) {
              return _Footer(
                loading: s.loadingMore,
                error: s.moreError,
                onRetry: () => unawaited(ctl.loadMore()),
              );
            }
            final day = days[i];
            // v4: bir gün = bir defter; başlık (13/18 700 soluk), altında satırlar ince çizgiyle.
            return Column(
              key: ValueKey('day-${day.label}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AknLedgerGroup(title: day.label),
                AknLedger(
                  pour: true,
                  children: [
                    for (final n in day.items)
                      NotificationTile(
                        key: ValueKey('notification-row-${n.id}'),
                        notification: n,
                        onTap: () => _open(context, ref, n),
                        onMarkRead: () => unawaited(_markRead(ref, n)),
                      ),
                  ],
                ),
              ],
            );
          },
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
    // Sekme rotaları `go` ile açılır (QA SC-01).
    context.openAppLocation(target);
  }
}

/// Son kaydedilen listenin zamanı: "Son güncelleme 09:58" (soluk, saat simgesiyle).
class _CachedNote extends StatelessWidget {
  const _CachedNote({required this.at});

  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final text = NotificationsCopy.cachedAt(Fmt.time(at));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 10, AknSpace.page, 0),
      child: Semantics(
        liveRegion: true,
        label: text,
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(
              PhosphorIconsRegular.clockCounterClockwise,
              size: 18,
              color: c.dim,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: t.label.copyWith(
                  fontWeight: FontWeight.w500,
                  color: c.dim,
                  fontFeatures: AknNumerals.tabular,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bir günün bildirimleri (yeni önce): başlık "Bugün", "Dün", gün adı ya da tarih.
@immutable
class NotificationDay {
  const NotificationDay(this.label, this.items);

  final String label;
  final List<UserNotification> items;
}

/// Bildirimleri (yeni önce sıralı) günlere ayırır; her gün bir defter olur.
List<NotificationDay> notificationDays(List<UserNotification> items) {
  final out = <NotificationDay>[];
  for (final n in items) {
    final label = dayLabel(n.createdAt);
    if (out.isNotEmpty && out.last.label == label) {
      out.last.items.add(n);
    } else {
      out.add(NotificationDay(label, [n]));
    }
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
              icon: PhosphorIconsRegular.arrowClockwise,
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
          icon: PhosphorIconsRegular.caretDown,
          onPressed: onRetry,
        ),
      ),
    );
  }
}
