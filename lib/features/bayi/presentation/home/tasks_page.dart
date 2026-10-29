import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/tasks/task_inbox.dart';
import '../../../../core/push/unread_count_provider.dart';
import '../../../../core/ui/ui.dart';
import '../../application/bayi_grants.dart';
import '../../application/home_controller.dart';
import '../../data/home_models.dart';
import '../widgets/paged_list_body.dart';
import 'home_tasks.dart';

/// "Tüm işler" (v4 tur 2, B18): ana sayfanın "Sıra sizde" kartına sığmayan işler dahil bütün işler,
/// kartın sırasıyla ve aynı satırlarla ([AknTaskRow]). Ana sayfa kartının "Tüm işler ›" satırı bu
/// sayfayı iter (müşteri ve Merkez'de Onaylar, sahada Saha açılır; bayinin işleri tek bir listede
/// değil, burada toplanır). Her satır işin sayfasını açar. İş yoksa sakin boş durum.
class BayiTasksPage extends ConsumerWidget {
  const BayiTasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bayiHomeProvider);
    final controller = ref.read(bayiHomeProvider.notifier);
    return AppScaffold(
      title: 'Tüm işler',
      refreshing: state.refreshing,
      body: LoadableBody<BayiHomeData>(
        state: state,
        onRetry: () => controller.load(useCache: true),
        builder: (context, data) => PullToRefresh(
          onRefresh: () async {
            await Future.wait([
              controller.refresh(),
              ref.read(unreadCountProvider.notifier).refresh(),
            ]);
          },
          child: _TaskList(data: data),
        ),
      ),
    );
  }
}

class _TaskList extends ConsumerWidget {
  const _TaskList({required this.data});

  final BayiHomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(bayiGrantsProvider);
    final inbox = ref.watch(bayiTaskQueuesProvider);
    // Hat yalnızca ana sayfada: burada teklif satırı kendi sayısını söyler.
    final tasks = BayiHomeTasks.all(
      context,
      ref,
      inbox.items,
      g,
      data,
      pipeline: false,
      lead: false,
    );
    return StaggerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
        children: [
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                title: 'Bekleyen işiniz yok',
                message: 'Yeni sipariş gelince bildirim alırsınız.',
                illustration: AknIllustration.inbox,
              ),
            )
          else
            StaggerItem(
              index: 0,
              child: AknLedger(
                pour: true,
                children: [for (final t in tasks) AknTaskRow(task: t)],
              ),
            ),
        ],
      ),
    );
  }
}
