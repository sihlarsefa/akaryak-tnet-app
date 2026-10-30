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

/// Ekip (`/bayi/staff`, spec A.4; tasarım v3): rol çipleri, arama, ara, son giriş; aktif / pasif
/// anahtarı ve "Şifre bağlantısı gönder" yalnızca `StationStaff:Duzenler` ile. Her personel beyaz bir
/// kart; kartlar art arda yükselerek gelir (süzgeç değişince yeniden). Saha satış temsilcisi bu ekranı
/// görmez.
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
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: SearchField(
                  hint: 'Ad, e-posta, telefon ya da rol',
                  controller: _search,
                  onChanged: c.setQuery,
                ),
              ),
              AknSegmented<StaffFilter>(
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
                  icon: PhosphorIconsRegular.eye,
                  message:
                      'Ekibi görüntüleyebilirsiniz; aktif / pasif ve şifre işlemleri için yetkiniz yok.',
                ),
              const SizedBox(height: 10),
              if (rows.isEmpty)
                const FadeUp(
                  offset: 18,
                  scale: 0.96,
                  duration: AknMotion.slow,
                  child: EmptyState(
                    compact: true,
                    title: BayiCopy.staffEmptyTitle,
                    message: BayiCopy.staffEmptyMessage,
                    illustration: AknIllustration.customers,
                  ),
                )
              else
                // Süzgeç değişince kartlar yeniden art arda gelir (seçici yerinde kalır, başparmağı
                // kayar).
                StaggerScope(
                  key: ValueKey(s.filter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        StaggerItem(
                          key: ValueKey(rows[i].userId),
                          index: i,
                          child: BayiCard(
                            margin: PagedListBody.cardMargin,
                            pressable: false,
                            child: StaffRow(
                              member: rows[i],
                              manage: g.manageStaff,
                              busy: s.busy.contains(rows[i].userId),
                            ),
                          ),
                        ),
                    ],
                  ),
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

/// Ekip kartının içeriği (tasarım v3): baş harf yuvarlağı (pasifken soluk), ad ("Siz", "Pasif",
/// "İncelenecek" çipleri), e-posta, roller Beton küçük haplarda (adı sunucudan; pasif rol "(pasif)"
/// ekiyle), birim onaycısında "Onaycı · Finans" hapı, son giriş; arama düğmesi; yönetici için aktif /
/// pasif anahtarı ve "Şifre bağlantısı gönder" (kart içinde ince çizginin altında). Roller v5:
/// "İncelenecek" (amber) rolü otomatik taşınan ve pasif kalan personeldedir (`needsReview`).
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

  /// Gözden geçirme çipi (sunucu `BayiRoleDisplay.ReviewChip`).
  static const reviewLabel = 'İncelenecek';

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
      icon: PhosphorIconsRegular.envelopeSimpleOpen,
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
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedOpacity(
                opacity: m.isActive ? 1 : 0.55,
                duration: AknMotion.of(context, AknMotion.base),
                child: AknAvatar(name: m.displayName, size: 44),
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
                        if (m.needsReview)
                          const AknLamp(
                            label: StaffRow.reviewLabel,
                            tone: AknTone.warn,
                            size: AknLampSize.small,
                            semanticLabel:
                                'İncelenecek: rolü pasif, gözden geçirilmeli',
                          ),
                      ],
                    ),
                    Text(m.email, style: t.bodySmall.copyWith(color: c.dim)),
                    if (roles.isNotEmpty || m.approverOf.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < roles.length; i++)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.surfaceAlt,
                                borderRadius: AknRadius.pillAll,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                child: Text(
                                  roles[i],
                                  semanticsLabel: roles[i],
                                  style: t.label.copyWith(color: c.ink),
                                ),
                              ),
                            ),
                          // Birim onaycısı (roller v5): rol hapıyla aynı Beton zemin, mühür simgesi.
                          for (final u in m.approverOf)
                            DecoratedBox(
                              key: ValueKey('approver-$u'),
                              decoration: BoxDecoration(
                                color: c.surfaceAlt,
                                borderRadius: AknRadius.pillAll,
                              ),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  8,
                                  3,
                                  10,
                                  3,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      PhosphorIconsBold.sealCheck,
                                      size: 13,
                                      color: c.ink,
                                    ),
                                    const SizedBox(width: 4),
                                    // Büyük yazıda hap içinde sarılır (taşmaz).
                                    Flexible(
                                      child: Text(
                                        'Onaycı · ${ApproverUnits.shortLabel(u)}',
                                        semanticsLabel: ApproverUnits.label(u),
                                        style: t.label.copyWith(color: c.ink),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          PhosphorIconsRegular.clockCounterClockwise,
                          size: 14,
                          color: c.dim,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            login,
                            style: t.caption.copyWith(color: c.dim),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (m.phoneNumber != null)
                AknIconButton(
                  icon: PhosphorIconsRegular.phone,
                  semanticLabel: '${m.displayName} ara',
                  onPressed: () => callPhone(context, m.phoneNumber!),
                ),
            ],
          ),
          if (manage && !me) ...[
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 58,
                top: 10,
                end: 8,
                bottom: 4,
              ),
              child: SizedBox(height: 1, child: ColoredBox(color: c.lineSoft)),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 54, top: 2),
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
                      icon: PhosphorIconsRegular.envelopeSimple,
                      size: AknButtonSize.small,
                      onPressed: busy || !online
                          ? null
                          : () => unawaited(_sendLink(context, ref)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
