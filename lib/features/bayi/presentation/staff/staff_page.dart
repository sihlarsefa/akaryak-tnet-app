import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
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
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: SearchField(
                  hint: 'Ad, e-posta, telefon ya da rol',
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
              if (!g.manageStaff)
                const PageWell(
                  top: 12,
                  tone: AknTone.neutral,
                  icon: Icons.visibility_outlined,
                  message:
                      'Ekibi görüntüleyebilirsiniz; aktif / pasif ve şifre işlemleri için yetkiniz yok.',
                ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const EmptyState(
                  compact: true,
                  title: BayiCopy.staffEmptyTitle,
                  message: BayiCopy.staffEmptyMessage,
                  illustration: AknIllustration.customers,
                )
              else
                AknLedger(
                  children: [
                    for (final m in rows)
                      StaffRow(
                        member: m,
                        manage: g.manageStaff,
                        busy: s.busy.contains(m.userId),
                      ),
                  ],
                ),
              if (rows.isNotEmpty)
                ListFooterNote(
                  '${s.all.length} personel. Rolleri ve yeni personeli web portalından yönetebilirsiniz.',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ekip satırı (defter satırı): baş harf, ad ("Siz", "Pasif" lambaları), e-posta, roller, son giriş;
/// arama düğmesi; yönetici için aktif / pasif anahtarı ve "Şifre bağlantısı gönder".
class StaffRow extends ConsumerWidget {
  const StaffRow({
    super.key,
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
        : 'Son giriş ${TurkishText.lower(Fmt.relative(m.lastLoginAt))}';
    final roles = [
      for (final r in m.roles.where((r) => r.roleIsActive)) r.label,
      if (m.roles.isEmpty && m.permissionGroupName != null)
        m.permissionGroupName!,
      if (m.isFieldSales &&
          !m.roles.any((r) => r.templateCode == BayiRoleCodes.fieldRep))
        'Saha satış',
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: m.isActive ? 1 : 0.6,
                child: AknAvatar(name: m.displayName, size: 40),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          m.displayName,
                          style: t.headline.copyWith(
                            color: m.isActive ? c.ink : c.dim,
                          ),
                        ),
                        if (me)
                          const AknLamp(
                            label: 'Siz',
                            tone: AknTone.info,
                            size: AknLampSize.small,
                          ),
                        if (!m.isActive)
                          const AknLamp(
                            label: 'Pasif',
                            tone: AknTone.neutral,
                            size: AknLampSize.small,
                          ),
                      ],
                    ),
                    Text(m.email, style: t.bodySmall.copyWith(color: c.dim)),
                    if (roles.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          for (var i = 0; i < roles.length; i++)
                            Text(
                              roles[i],
                              semanticsLabel: roles[i],
                              style: t.bodySmall.copyWith(
                                color: c.ink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 2),
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
          if (manage && !me)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 54, top: 6),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MergeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                        const SizedBox(width: 6),
                        Text(
                          m.isActive ? 'Aktif' : 'Pasif',
                          style: t.label.copyWith(color: c.ink),
                        ),
                      ],
                    ),
                  ),
                  if (m.isActive)
                    AknButton.ghost(
                      label: 'Şifre bağlantısı gönder',
                      size: AknButtonSize.small,
                      onPressed: busy || !online
                          ? null
                          : () => unawaited(_sendLink(context, ref)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
