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

/// Tek rolde yalnız kullanıcıya not (rol belirleme yok).
const _usersAloneSingleRole =
    'Şu an şirketinizde yalnızca siz varsınız. Satın alma ekibinizi ekleyin; '
    'herkes doğrudan sipariş verir ve teklife karar verir.';

/// Ana kullanıcı etiketi (`CompanyUserDto.isMainUser`; sunucu `CustomerSingleRoleTexts.MainUserChip`).
const mainUserLabel = 'Ana kullanıcı';

/// Şirket kullanıcıları (yalnızca şirket Yöneticisi + `CustomerCompanyUsers:Gorur`): liste (rol çipi,
/// "Davet bekliyor", son giriş), ekle, rol düzenle, aktif / pasif (onaylı), "Bağlantıyı yeniden gönder",
/// şirket içi onay eşikleri.
///
/// Roller v5 (`me/access.companyApprovalsEnabled == false`, tek müşteri rolü): rol sütunu, rol seçimi,
/// rol açıklamaları ve eşik kartı yok; ana kullanıcıda "Ana kullanıcı" yazar (panelle aynı). Eski akış
/// (eski sunucu, geçiş yapılmamış şirket) olduğu gibi kalır.
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
    final approvals = policy.companyApprovals;
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
      // Kullanıcılar gruplanmış beyaz kartlarda (içeriden çizgilerle), bölümler sırayla yükselir.
      Widget group(List<CompanyUser> users) =>
          AknLedger(children: [for (final u in users) UserCard(user: u)]);
      final blocks = <Widget>[
        SectionHeader(
          title: 'Kullanıcılar',
          count: active.length,
          padding: const EdgeInsets.fromLTRB(24, 8, 12, 8),
        ),
        if (s.users.length <= 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: AknBanner(
              tone: AknTone.info,
              message: approvals ? CmCopy.usersAlone : _usersAloneSingleRole,
            ),
          ),
        if (active.isNotEmpty) group(active),
        if (inactive.isNotEmpty) ...[
          SectionHeader(
            title: 'Pasif kullanıcılar',
            count: inactive.length,
            padding: const EdgeInsets.fromLTRB(24, 22, 12, 8),
          ),
          group(inactive),
        ],
        // Eşikler yüklenemediyse kart yok (liste yine açılır); onay kapalıyken kart ve rol açıklamaları
        // hiç yok.
        if (approvals && s.thresholds != null)
          _ThresholdsCard(
            thresholds: s.thresholds,
            canEdit: policy.cmCompanyUserEdit && online,
          ),
        if (approvals) const _RolesLegend(),
      ];
      body = PullToRefresh(
        onRefresh: ctrl.load,
        child: StaggerScope(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              for (final (i, b) in blocks.indexed)
                StaggerItem(index: i, child: b),
            ],
          ),
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
                icon: PhosphorIconsRegular.userPlus,
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
              icon: PhosphorIconsRegular.pencilSimple,
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
          : Text(
              'Şirket içi onay kapalı.',
              style: t.bodySmall.copyWith(color: context.akn.dim),
            ),
    );
  }
}

/// Kullanıcı satırı (tasarım v3 §4, grup kartının içinde): baş harfli avatar, ad ("(siz)"), e-posta /
/// telefon, sağda rol; davet / pasif lambası ve son giriş. Yönetici dokununca eylemler açılır.
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
    // Roller v5: tek rolde rol sütunu yok; ana kullanıcıda "Ana kullanıcı".
    final meta = policy.companyApprovals
        ? role.label
        : (u.isMainUser ? mainUserLabel : null);
    final canManage = policy.cmCompanyUserEdit;
    final contact = [
      if (u.email.isNotEmpty) u.email,
      if (u.phoneNumber != null) Fmt.phone(u.phoneNumber),
    ].join('\n');
    final lamp = u.invitationPending
        ? const AknLamp(label: 'Davet bekliyor', tone: AknTone.info)
        : (!u.isActive
              ? const AknLamp(label: 'Pasif', tone: AknTone.neutral)
              : null);
    return AknListTile(
      leading: Opacity(
        opacity: u.isActive ? 1 : 0.55,
        child: AknAvatar(name: u.displayName),
      ),
      padding: cmRowPadding,
      titleStyle: cmRowTitle(context),
      title: u.isSelf ? '${u.displayName} (siz)' : u.displayName,
      subtitle: contact.isEmpty ? null : contact,
      meta: meta,
      status: AknStatusLine(
        lamp: lamp ?? Text(last, style: t.bodySmall.copyWith(color: c.dim)),
        trailing: lamp == null
            ? null
            : Text(last, style: t.bodySmall.copyWith(color: c.dim)),
      ),
      showChevron: canManage,
      onTap: canManage
          ? () {
              AknHaptics.selection();
              showUserActionsSheet(
                context,
                u,
                companyApprovals: policy.companyApprovals,
              );
            }
          : null,
      semanticLabel: [
        u.displayName,
        if (u.isSelf) 'siz',
        ?meta,
        if (u.invitationPending) 'davet bekliyor',
        if (!u.isActive) 'pasif',
        u.email,
        last,
      ].join(', '),
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
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.label,
                    style: t.bodyStrong.copyWith(color: context.akn.ink),
                  ),
                  Text(
                    companyRoleHint(r),
                    style: t.bodySmall.copyWith(color: context.akn.dim),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
