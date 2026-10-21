import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/cm_access.dart';
import '../../application/company_controller.dart';
import '../../copy.dart';
import '../../data/company.dart';
import '../cm_widgets.dart';
import 'company_user_sheets.dart';

/// Şirket kullanıcıları (yalnızca şirket Yöneticisi + `CustomerCompanyUsers:Gorur`): liste (rol çipi,
/// "Davet bekliyor", son giriş), ekle, rol düzenle, aktif / pasif (onaylı), "Bağlantıyı yeniden gönder",
/// şirket içi onay eşikleri.
class CompanyUsersPage extends ConsumerWidget {
  const CompanyUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(accessPolicyProvider);
    if (!policy.cmCompanyUsers) {
      return const AppScaffold(
        title: CmCopy.usersTitle,
        body: Center(
          child: EmptyState(
            title: CmCopy.usersOnlyAdmin,
            message: CmCopy.usersOnlyAdminMessage,
            illustration: AknIllustration.locked,
          ),
        ),
      );
    }
    final s = ref.watch(companyUsersControllerProvider);
    final ctrl = ref.read(companyUsersControllerProvider.notifier);
    final online = ref.watch(isOnlineProvider);
    final active = s.users.where((u) => u.isActive).toList();
    final inactive = s.users.where((u) => !u.isActive).toList();
    Widget body;
    if (s.loading && s.users.isEmpty) {
      body = const SkeletonList(itemCount: 4, lines: 2);
    } else if (s.users.isEmpty && s.error != null) {
      body = ListView(
        children: [CmFailureView(failure: s.error!, onRetry: ctrl.load)],
      );
    } else {
      body = PullToRefresh(
        onRefresh: ctrl.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          children: [
            _ThresholdsCard(
              thresholds: s.thresholds,
              canEdit: policy.cmCompanyUserEdit && online,
            ),
            SectionHeader(
              title: 'Kullanıcılar',
              count: active.length,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            ),
            if (s.users.length <= 1)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: AknBanner(
                  tone: AknTone.info,
                  message: CmCopy.usersAlone,
                ),
              ),
            for (final u in active) UserCard(user: u),
            if (inactive.isNotEmpty) ...[
              SectionHeader(
                title: 'Pasif kullanıcılar',
                count: inactive.length,
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              ),
              for (final u in inactive) UserCard(user: u),
            ],
            const _RolesLegend(),
          ],
        ),
      );
    }
    return AppScaffold(
      title: CmCopy.usersTitle,
      subtitle: ref.watch(sessionControllerProvider).access?.customerTitle,
      refreshing: s.refreshing,
      actionBar: policy.cmCompanyUserCreate
          ? cmBar(
              AknButton(
                label: 'Kullanıcı ekle',
                icon: Icons.person_add_alt_1_rounded,
                expand: true,
                onPressed: online ? () => showAddUserSheet(context) : null,
              ),
            )
          : null,
      body: body,
    );
  }
}

class _ThresholdsCard extends StatelessWidget {
  const _ThresholdsCard({required this.thresholds, required this.canEdit});

  final ApprovalThresholds? thresholds;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final th = thresholds;
    final on = th?.isConfigured ?? false;
    return CmSection(
      title: CmCopy.thresholdsTitle,
      subtitle: on
          ? 'Talep edenin bu eşikleri aşan siparişi onaya düşer.'
          : 'Kapalı: Talep edenin siparişleri doğrudan bayiye gider.',
      trailing: canEdit
          ? AknIconButton(
              icon: Icons.edit_rounded,
              semanticLabel: 'Onay eşiklerini düzenle',
              onPressed: () => showThresholdsSheet(context, th),
            )
          : null,
      child: on
          ? Column(
              children: [
                FactRow(
                  label: 'Litre eşiği',
                  value: th!.aboveLitres == null
                      ? 'Yok'
                      : (th.aboveLitres == 0
                            ? 'Her sipariş'
                            : '${Fmt.liters(th.aboveLitres)} üstü'),
                ),
                FactRow(
                  label: 'Tahmini tutar eşiği',
                  value: th.aboveAmount == null
                      ? 'Yok'
                      : '${Fmt.money(th.aboveAmount)} üstü',
                ),
              ],
            )
          : Text('Şirket içi onay kapalı.', style: t.bodySmall),
    );
  }
}

/// Kullanıcı kartı: rol çipi, davet / pasif durumu, son giriş; dokununca eylemler.
class UserCard extends ConsumerWidget {
  const UserCard({super.key, required this.user});

  final CompanyUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = user;
    final t = context.aknText;
    final c = context.akn;
    final policy = ref.watch(accessPolicyProvider);
    final last = u.lastLoginAt == null
        ? 'Henüz giriş yapmadı'
        : 'Son giriş ${Fmt.relative(u.lastLoginAt)}';
    final role = u.role.statusStyle.withLabel(u.roleLabel);
    final canManage = policy.cmCompanyUserEdit;
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      onTap: canManage ? () => showUserActionsSheet(context, u) : null,
      semanticLabel: [
        u.displayName,
        if (u.isSelf) 'siz',
        role.label,
        if (u.invitationPending) 'davet bekliyor',
        if (!u.isActive) 'pasif',
        u.email,
        last,
      ].join(', '),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: u.isActive ? 1 : 0.55,
              child: AknAvatar(name: u.displayName),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u.isSelf ? '${u.displayName} (siz)' : u.displayName,
                    style: t.bodyStrong,
                  ),
                  if (u.email.isNotEmpty) Text(u.email, style: t.bodySmall),
                  if (u.phoneNumber != null)
                    Text(Fmt.phone(u.phoneNumber), style: t.caption),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusChip.style(role, size: StatusChipSize.small),
                      if (u.invitationPending)
                        const StatusChip(
                          label: 'Davet bekliyor',
                          tone: AknTone.info,
                          icon: Icons.mark_email_unread_rounded,
                          size: StatusChipSize.small,
                        ),
                      if (!u.isActive)
                        const StatusChip(
                          label: 'Pasif',
                          tone: AknTone.neutral,
                          icon: Icons.block_rounded,
                          size: StatusChipSize.small,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(last, style: t.caption),
                ],
              ),
            ),
            if (canManage) Icon(Icons.more_horiz_rounded, color: c.faint),
          ],
        ),
      ),
    );
  }
}

class _RolesLegend extends StatelessWidget {
  const _RolesLegend();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return CmSection(
      title: 'Roller',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in const [
            CustomerUserRole.requester,
            CustomerUserRole.approver,
            CustomerUserRole.admin,
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip.style(r.statusStyle, size: StatusChipSize.small),
                  const SizedBox(width: 8),
                  Expanded(child: Text(companyRoleHint(r), style: t.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
