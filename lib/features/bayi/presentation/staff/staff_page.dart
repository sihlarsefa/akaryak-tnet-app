import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/bayi_grants.dart';
import '../../application/staff_controller.dart';
import '../../copy.dart';
import '../../data/staff_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';

/// Ekip (`/bayi/staff`, spec A.4): rol çipleri, arama, ara, son giriş; aktif / pasif anahtarı ve "Şifre
/// bağlantısı gönder" yalnızca `StationStaff:Duzenler` ile. Saha satış temsilcisi bu ekranı görmez.
class StaffPage extends ConsumerStatefulWidget {
  const StaffPage({super.key});

  @override
  ConsumerState<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends ConsumerState<StaffPage> {
  // Arama kutusu listeyle kayar; yazılan metin kutu ekrandan çıkınca kaybolmasın.
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Yetkisiz kullanıcı için liste hiç istenmez.
    if (ref.read(bayiGrantsProvider).viewStaff) {
      _search.text = ref.read(staffProvider).query;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(bayiGrantsProvider);
    if (!g.viewStaff) {
      return const AppScaffold(
        title: 'Ekip',
        body: EmptyState(
          title: BayiCopy.forbiddenTitle,
          message: BayiCopy.forbiddenMessage,
          illustration: AknIllustration.locked,
        ),
      );
    }
    final s = ref.watch(staffProvider);
    final c = ref.read(staffProvider.notifier);
    final rows = s.visible;
    return AppScaffold(
      title: 'Ekip',
      subtitle: s.data.hasData ? '${s.all.length} personel' : null,
      refreshing: s.data.refreshing,
      body: LoadableBody<List<StaffMember>>(
        state: s.data,
        onRetry: c.refresh,
        builder: (context, _) => PullToRefresh(
          onRefresh: c.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchField(
                  hint: 'Ad, e-posta, telefon, rol',
                  controller: _search,
                  onChanged: c.setQuery,
                ),
              ),
              BayiSegmented<StaffFilter>(
                segments: [
                  for (final f in StaffFilter.values)
                    FilterOption(value: f, label: f.label, count: s.countOf(f)),
                ],
                value: s.filter,
                onChanged: c.setFilter,
              ),
              const SizedBox(height: 12),
              if (!g.manageStaff)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: AknBanner(
                    tone: AknTone.neutral,
                    icon: Icons.visibility_outlined,
                    message:
                        'Ekibi görüntüleyebilirsiniz; aktif / pasif ve şifre işlemleri için yetkiniz yok.',
                  ),
                ),
              if (rows.isEmpty)
                const EmptyState(
                  compact: true,
                  title: BayiCopy.staffEmptyTitle,
                  message: BayiCopy.staffEmptyMessage,
                  illustration: AknIllustration.customers,
                )
              else
                StaggerScope(
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        StaggerItem(
                          index: i,
                          child: _StaffCard(
                            member: rows[i],
                            manage: g.manageStaff,
                            busy: s.busy.contains(rows[i].userId),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffCard extends ConsumerWidget {
  const _StaffCard({
    required this.member,
    required this.manage,
    required this.busy,
  });

  final StaffMember member;
  final bool manage;
  final bool busy;

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool active) async {
    final m = member;
    if (!active) {
      final ok = await showConfirmSheet(
        context,
        title: '${m.displayName} pasifleştirilsin mi?',
        message:
            'Uygulamaya ve web portalına giriş yapamaz; açık oturumları kapanır. Daha sonra yeniden aktifleştirebilirsiniz.',
        confirmLabel: 'Pasifleştir',
        destructive: true,
      );
      if (!ok || !context.mounted) return;
    }
    try {
      await ref.read(staffProvider.notifier).setActive(m, active);
      if (context.mounted) {
        AppToast.success(
          active
              ? '${m.displayName} aktifleştirildi.'
              : '${m.displayName} pasifleştirildi.',
          context: context,
        );
      }
    } catch (e) {
      if (context.mounted) showActionFailure(context, e);
    }
  }

  Future<void> _sendLink(BuildContext context, WidgetRef ref) async {
    final m = member;
    final ok = await showConfirmSheet(
      context,
      title: 'Şifre bağlantısı gönderilsin mi?',
      message: '${m.email} adresine şifre belirleme bağlantısı gider.',
      confirmLabel: 'Gönder',
      icon: Icons.mark_email_read_outlined,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(staffProvider.notifier).sendPasswordLink(m);
      if (context.mounted) {
        AppToast.success(
          'Şifre bağlantısı ${m.email} adresine gönderildi.',
          context: context,
        );
      }
    } catch (e) {
      if (context.mounted) showActionFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final m = member;
    final online = ref.watch(isOnlineProvider);
    final me = ref.watch(currentUserIdProvider) == m.userId;
    final login = m.lastLoginAt == null
        ? 'Henüz giriş yapmadı'
        : 'Son giriş ${Fmt.relative(m.lastLoginAt)}';
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: m.isActive ? 1 : 0.6,
                child: AknAvatar(name: m.displayName, size: 44),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(m.displayName, style: t.bodyStrong),
                        if (me)
                          const StatusChip(
                            label: 'Siz',
                            tone: AknTone.brand,
                            icon: Icons.person_rounded,
                            size: StatusChipSize.small,
                          ),
                        if (!m.isActive)
                          const StatusChip(
                            label: 'Pasif',
                            tone: AknTone.neutral,
                            icon: Icons.block_rounded,
                            size: StatusChipSize.small,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(m.email, style: t.bodySmall),
                    Text(login, style: t.caption.copyWith(color: c.dim)),
                  ],
                ),
              ),
              if (m.phoneNumber != null)
                AknIconButton(
                  icon: Icons.call_outlined,
                  semanticLabel: '${m.displayName} ara',
                  onPressed: () => callPhone(context, m.phoneNumber!),
                ),
            ],
          ),
          if (m.roleLabels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in m.roles.where((r) => r.roleIsActive))
                  StatusChip(
                    label: r.label,
                    tone: AknTone.neutral,
                    icon: _roleIcon(r.templateCode),
                    size: StatusChipSize.small,
                  ),
                if (m.roles.isEmpty && m.permissionGroupName != null)
                  StatusChip(
                    label: m.permissionGroupName!,
                    tone: AknTone.neutral,
                    icon: Icons.group_outlined,
                    size: StatusChipSize.small,
                  ),
                if (m.isFieldSales &&
                    !m.roles.any(
                      (r) => r.templateCode == BayiRoleCodes.fieldRep,
                    ))
                  const StatusChip(
                    label: 'Saha satış',
                    tone: AknTone.neutral,
                    icon: Icons.storefront_rounded,
                    size: StatusChipSize.small,
                  ),
              ],
            ),
          ],
          if (manage && !me) ...[
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: MergeSemantics(
                    child: Row(
                      children: [
                        Semantics(
                          label: '${m.displayName} hesabı',
                          child: Switch(
                            value: m.isActive,
                            onChanged: busy || !online
                                ? null
                                : (v) => unawaited(_toggle(context, ref, v)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            m.isActive ? 'Aktif' : 'Pasif',
                            style: t.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (m.isActive)
                  Flexible(
                    child: TextButton.icon(
                      onPressed: busy || !online
                          ? null
                          : () => unawaited(_sendLink(context, ref)),
                      icon: const Icon(
                        Icons.mark_email_read_outlined,
                        size: 18,
                      ),
                      label: const Text('Şifre bağlantısı gönder'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static IconData _roleIcon(String? code) => switch (code) {
    BayiRoleCodes.owner ||
    BayiRoleCodes.manager => Icons.workspace_premium_outlined,
    BayiRoleCodes.financeManager ||
    BayiRoleCodes.financeSpecialist => Icons.account_balance_outlined,
    BayiRoleCodes.accounting => Icons.payments_outlined,
    BayiRoleCodes.salesManager ||
    BayiRoleCodes.fieldRep => Icons.storefront_outlined,
    BayiRoleCodes.orderDesk => Icons.request_quote_outlined,
    BayiRoleCodes.dispatch => Icons.route_outlined,
    BayiRoleCodes.driver => Icons.local_shipping_outlined,
    BayiRoleCodes.depot => Icons.local_gas_station_outlined,
    BayiRoleCodes.viewer => Icons.visibility_outlined,
    _ => Icons.badge_outlined,
  };
}
