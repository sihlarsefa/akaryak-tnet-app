import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/external_activity.dart';
import '../../../core/utils/format.dart';
import '../application/field_access.dart';
import '../application/field_detail_controllers.dart';
import '../copy.dart';
import '../data/lead_models.dart';
import 'widgets/field_widgets.dart';

/// Ön kayıt ayrıntısı (spec A.3 L2–L5; tasarım v3): başlıkta firma ve durum lambaları, ardından
/// sayfada yüzen gruplanmış bilgi kartları (Firma, Yetkililer, Yakıt ihtiyacı, Ödeme talebi, Tedarik
/// ve filo, Ziyaret, İlk teslimat noktası, KVKK, Belgeler) — sayfa açılınca sırayla belirir. Düzenle,
/// Finansa gönder, İptal et, Merkeze ilet (`approve.finance.lead`), Daveti yeniden gönder.
class FieldLeadDetailPage extends ConsumerWidget {
  const FieldLeadDetailPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(fieldLeadDetailProvider(id));
    final view = async.valueOrNull;
    if (view == null) {
      return AppScaffold(
        title: 'Ön kayıt',
        body: async.hasError
            ? _error(ref, AppFailure.from(async.error!))
            : const SkeletonList(itemCount: 4, lines: 3, leading: false),
      );
    }
    final d = view.detail;
    final draft = d.draft;
    final access = ref.watch(fieldAccessProvider);
    return AppScaffold(
      title: d.leadNumber,
      refreshing: async.isRefreshing,
      body: PullToRefresh(
        onRefresh: () =>
            ref.read(fieldLeadDetailProvider(id).notifier).refresh(),
        child: FieldStaggeredList(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _Hero(detail: d),
            ..._banners(context, d, access),
            FieldSectionCard(
              title: 'Firma',
              icon: PhosphorIconsRegular.buildingOffice,
              child: FieldFacts(
                facts: [
                  ('VKN / TCKN', _taxNumber(draft.taxNumber)),
                  ('Vergi dairesi', draft.taxOffice),
                  ('İl / ilçe', [?draft.city, ?draft.district].join(' / ')),
                  ('Adres', draft.address),
                  ('Sektör', draft.sector),
                  ('Faaliyet yılı', draft.foundedYear?.toString()),
                  (
                    'Telefon',
                    draft.phone == null ? null : Fmt.phone(draft.phone),
                  ),
                  ('E-posta', draft.email),
                  ('Web', draft.website),
                ],
              ),
            ),
            FieldSectionCard(
              title: 'Yetkililer',
              icon: PhosphorIconsRegular.users,
              child: Column(
                children: [
                  for (final c in draft.contacts.where((c) => !c.isEmpty))
                    AknListTile(
                      title: c.name,
                      subtitle: [
                        ?c.title,
                        ?c.email,
                        if (c.isInviteRecipient) 'Portal daveti bu kişiye',
                      ].join(', '),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      trailing: c.phone == null
                          ? null
                          : AknIconButton(
                              icon: PhosphorIconsRegular.phone,
                              semanticLabel: '${c.name} kişisini ara',
                              onPressed: () => launchExternal(
                                Uri(scheme: 'tel', path: c.phone),
                              ),
                            ),
                    ),
                  if (draft.contacts.every((c) => c.isEmpty))
                    Text(
                      'Yetkili girilmedi.',
                      style: context.aknText.bodySmall,
                    ),
                ],
              ),
            ),
            FieldSectionCard(
              title: 'Yakıt ihtiyacı',
              icon: PhosphorIconsRegular.gasPump,
              child: FieldFacts(
                facts: [
                  for (final p in draft.products.where(
                    (p) => p.monthlyLiters > 0,
                  ))
                    (
                      p.productName ?? 'Ürün #${p.productId}',
                      '${Fmt.liters(p.monthlyLiters)}/ay'
                          '${p.committedMonthlyLiters == null ? '' : ', taahhüt ${Fmt.liters(p.committedMonthlyLiters)}'}',
                    ),
                  ('Toplam', '${Fmt.liters(d.totalMonthlyLiters)}/ay'),
                  (
                    'İlk sipariş',
                    [
                      ?d.firstOrderProductName,
                      if (draft.firstOrderLiters != null)
                        Fmt.liters(draft.firstOrderLiters),
                    ].join(', '),
                  ),
                  (
                    'İlk sevk',
                    draft.firstShipDate == null
                        ? null
                        : Fmt.date(draft.firstShipDate),
                  ),
                  (
                    'Sözleşme',
                    draft.contractMonths == null
                        ? null
                        : '${draft.contractMonths} ay',
                  ),
                ],
              ),
            ),
            FieldSectionCard(
              title: 'Ödeme talebi',
              icon: PhosphorIconsRegular.money,
              child: FieldFacts(
                facts: [
                  ('Yöntemler', d.requestedMethodNames.join(', ')),
                  (
                    'Vade',
                    draft.requestedTermDays == null
                        ? null
                        : '${draft.requestedTermDays} gün',
                  ),
                  (
                    'Talep edilen limit',
                    draft.requestedLimitAmount == null
                        ? null
                        : Fmt.money(draft.requestedLimitAmount),
                  ),
                  (
                    'Teminat',
                    [
                      ?draft.collateralOfferKind?.label,
                      if (draft.collateralOfferAmount != null)
                        Fmt.money(draft.collateralOfferAmount),
                      ?draft.collateralOfferNote,
                    ].join(', '),
                  ),
                  (
                    'Teminat oranı',
                    draft.collateralRatioPercent == null
                        ? null
                        : Fmt.percent(draft.collateralRatioPercent),
                  ),
                ],
              ),
            ),
            FieldSectionCard(
              title: 'Tedarik ve filo',
              icon: PhosphorIconsRegular.truck,
              child: FieldFacts(
                facts: [
                  ('Mevcut dağıtıcı', draft.currentDistributor),
                  ('Terminal', draft.currentTerminal),
                  ('Mevcut fiyat', draft.currentPriceNote),
                  ('Fiyat beklentisi', draft.priceExpectation),
                  (
                    'Araç',
                    [
                      if (draft.vehicleCount != null)
                        '${draft.vehicleCount} araç',
                      ?draft.vehicleTypes,
                    ].join(', '),
                  ),
                  (
                    'Depo',
                    draft.hasTank
                        ? 'Var${draft.tankCapacityLiters == null ? '' : ', ${Fmt.liters(draft.tankCapacityLiters)}'}'
                        : null,
                  ),
                ],
              ),
            ),
            _VisitCard(draft: draft),
            FieldSectionCard(
              title: 'İlk teslimat noktası',
              icon: PhosphorIconsRegular.mapPin,
              child: FieldFacts(
                facts: [
                  ('Ad', draft.deliveryPointName),
                  (
                    'İl / ilçe',
                    [
                      ?draft.deliveryPointCity,
                      ?draft.deliveryPointDistrict,
                    ].join(' / '),
                  ),
                  ('Adres', draft.deliveryPointAddress),
                ],
              ),
            ),
            FieldSectionCard(
              title: 'KVKK açık rıza',
              icon: PhosphorIconsRegular.shieldCheck,
              child: draft.kvkkConsent
                  ? FieldFacts(
                      facts: [
                        ('Yöntem', draft.kvkkConsentMethod),
                        (
                          'Kayıt',
                          d.kvkkConsentAt == null
                              ? null
                              : Fmt.dateTime(d.kvkkConsentAt),
                        ),
                        ('Metin sürümü', d.kvkkDocumentVersion),
                      ],
                    )
                  : const AknBanner(
                      tone: AknTone.warn,
                      message:
                          'Açık rıza alınmadı; finansa göndermek için gerekir.',
                    ),
            ),
            FieldSectionCard(
              title: 'Belgeler',
              icon: PhosphorIconsRegular.paperclip,
              trailing: Text(
                '${view.documents.length}',
                style: context.aknText.caption,
              ),
              child: view.documents.isEmpty
                  ? Text(
                      'Belge eklenmedi. Vergi levhası finansa gönderim için zorunludur.',
                      style: context.aknText.bodySmall,
                    )
                  : FieldDocumentList(attachments: view.documents),
            ),
          ],
        ),
      ),
      actionBar: _actions(context, ref, d, access),
    );
  }

  Widget _error(WidgetRef ref, AppFailure f) => switch (f) {
    NotFoundFailure() => const EmptyState(
      title: FieldCopy.notFoundTitle,
      message: FieldCopy.notFoundMessage,
      illustration: AknIllustration.search,
    ),
    _ => ErrorState(
      offline: f is OfflineFailure,
      message: f is OfflineFailure ? null : f.message,
      onRetry: () => ref.invalidate(fieldLeadDetailProvider(id)),
    ),
  };

  static String? _taxNumber(String digits) {
    if (digits.isEmpty) return null;
    if (digits.length == 10) {
      return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
    }
    return digits;
  }

  List<Widget> _banners(
    BuildContext context,
    LeadDetail d,
    FieldAccess access,
  ) {
    const m = EdgeInsets.fromLTRB(20, 12, 20, 0);
    return [
      if (d.status == LeadStatus.infoRequested)
        AknBanner(
          margin: m,
          tone: AknTone.warn,
          icon: PhosphorIconsRegular.chatCircleDots,
          title: 'Finans ek bilgi istedi',
          message:
              '${d.decisionNote ?? 'Bilgileri tamamlayın.'} Düzenleyip "Finansa gönder" ile yeniden gönderin.',
          actionLabel: d.canEdit && access.canEditLead ? 'Düzenle' : null,
          onAction: d.canEdit && access.canEditLead
              ? () => context.push('${AppRoutes.fieldLead(id)}/edit')
              : null,
        ),
      if (d.existsElsewhere)
        const AknBanner(
          margin: m,
          tone: AknTone.info,
          title: 'Bu VKN sistemde kayıtlı',
          message:
              'Ön kayıt finansa gönderilebilir; cari açılışı merkez onayıyla yapılır.',
        ),
      if (d.isForwardedToHq)
        const AknBanner(
          margin: m,
          tone: AknTone.info,
          icon: PhosphorIconsRegular.treeStructure,
          message: 'Talep merkez onayına iletildi.',
        ),
      if (d.status == LeadStatus.rejected && d.decisionNote != null)
        AknBanner(
          margin: m,
          tone: AknTone.danger,
          title: 'Reddedildi',
          message: d.decisionNote!,
        ),
      if (d.status == LeadStatus.converted)
        AknBanner(
          margin: m,
          tone: AknTone.ok,
          title: 'Cariye dönüştürüldü',
          message: [
            if (d.customerCode != null) 'Cari kodu ${d.customerCode}.',
            if (d.inviteEmail != null)
              'Portal daveti ${d.inviteEmail} adresine gönderildi'
                  '${d.inviteExpiresAt == null ? '.' : ' (geçerlilik ${Fmt.dateTime(d.inviteExpiresAt)}).'}',
            if (d.customerHasPortalUser) 'Carinin portal kullanıcısı var.',
          ].join(' '),
        ),
      if (d.approvalRequestId != null &&
          d.isFinanceViewer &&
          access.canOpenApprovals)
        Padding(
          padding: m,
          child: AknButton.secondary(
            label: 'Onay talebini aç',
            icon: PhosphorIconsFill.checkCircle,
            expand: true,
            onPressed: () =>
                context.push(AppRoutes.approval(d.approvalRequestId!)),
          ),
        ),
    ];
  }

  Widget? _actions(
    BuildContext context,
    WidgetRef ref,
    LeadDetail d,
    FieldAccess a,
  ) {
    final edit = d.canEdit && a.canEditLead;
    final submit = d.canSubmit && a.canEditLead;
    final cancel = d.canCancel && a.canEditLead;
    final forward = d.canForwardToHq && a.canForwardLeadToHq;
    final invite = d.canResendInvite && a.canEditLead;
    if (!edit && !submit && !cancel && !forward && !invite) return null;
    // Alt çubuk yalnızca içeriği kadar yer kaplar (genişleyen düğmeler satırı uzatmasın).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LeadActions(
          id: id,
          detail: d,
          edit: edit,
          submit: submit,
          cancel: cancel,
          forward: forward,
          invite: invite,
        ),
      ],
    );
  }
}

/// Sayfanın başı (tasarım v3 §4: ön kayıt ayrıntısında plaka yok): firmanın baş harfleriyle yuvarlak
/// avatar, `display` başlıkta firma, altında kayıt no, temsilci, tarih ve aylık litre; durum lambaları.
class _Hero extends StatelessWidget {
  const _Hero({required this.detail});

  final LeadDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final t = context.aknText;
    final c = context.akn;
    final status = d.status.statusStyle.withLabel(d.statusLabel);
    final approval = d.approvalStatus != null && d.status != LeadStatus.draft
        ? d.approvalStatus!.statusStyle
        : null;
    final title = d.companyTitle.isEmpty ? 'Ünvansız ön kayıt' : d.companyTitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: AknAvatar(name: title, size: 52)),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(title, style: t.display.copyWith(color: c.ink)),
          ),
          const SizedBox(height: 4),
          Text(
            [
              d.leadNumber,
              ?d.salesRepName,
              if (d.createdAt != null) Fmt.date(d.createdAt),
              if (d.totalMonthlyLiters > 0)
                'ayda ${Fmt.liters(d.totalMonthlyLiters)}',
            ].join(', '),
            style: t.bodySmall.copyWith(color: c.dim),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              AknLamp.style(status),
              // Onay durumu, kaydın durumuyla aynı kelimeyse ikinci kez yazılmaz.
              if (approval != null && approval.label != status.label)
                AknLamp.style(approval),
            ],
          ),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.draft});

  final LeadDraft draft;

  @override
  Widget build(BuildContext context) {
    final lat = draft.visitLatitude;
    final lng = draft.visitLongitude;
    return FieldSectionCard(
      title: 'Ziyaret',
      icon: PhosphorIconsRegular.storefront,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldFacts(
            facts: [
              ('Tarih', draft.visitAt == null ? null : Fmt.date(draft.visitAt)),
              ('Not', draft.visitNote),
            ],
          ),
          if (lat != null && lng != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AccuracyChip(meters: draft.visitAccuracyMeters),
                TextButton.icon(
                  onPressed: () => launchExternal(
                    Uri.parse(
                      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(PhosphorIconsRegular.mapTrifold, size: 18),
                  label: const Text('Haritada aç'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LeadActions extends ConsumerWidget {
  const _LeadActions({
    required this.id,
    required this.detail,
    required this.edit,
    required this.submit,
    required this.cancel,
    required this.forward,
    required this.invite,
  });

  final int id;
  final LeadDetail detail;
  final bool edit;
  final bool submit;
  final bool cancel;
  final bool forward;
  final bool invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    final ctrl = ref.read(fieldLeadDetailProvider(id).notifier);

    Future<void> run(Future<String> Function() action) async {
      try {
        final message = await action();
        if (context.mounted && message.isNotEmpty) {
          AppToast.success(message, context: context);
        }
      } on AppFailure catch (f) {
        if (context.mounted) AppToast.error(f.message, context: context);
      }
    }

    Future<void> more() async {
      final choice = await showAppSheet<String>(
        context: context,
        title: 'Diğer işlemler',
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (forward)
              AknListTile(
                title: 'Merkeze ilet',
                subtitle:
                    'VKN başka bayide kayıtlı; cari açılışı merkez onayıyla',
                leadingIcon: PhosphorIconsRegular.treeStructure,
                onTap: () => Navigator.of(ctx).pop('forward'),
              ),
            if (invite)
              AknListTile(
                title: 'Portal davetini yeniden gönder',
                leadingIcon: PhosphorIconsRegular.envelopeSimple,
                onTap: () => Navigator.of(ctx).pop('invite'),
              ),
            if (cancel)
              AknListTile(
                title: 'Ön kaydı iptal et',
                leadingIcon: PhosphorIconsRegular.prohibit,
                leadingTone: AknTone.danger,
                onTap: () => Navigator.of(ctx).pop('cancel'),
              ),
          ],
        ),
      );
      if (!context.mounted || choice == null) return;
      switch (choice) {
        case 'forward':
          final ok = await showConfirmSheet(
            context,
            title: 'Merkeze iletilsin mi?',
            message:
                'Talep merkez onayına gider; bayi kademesinde karar verilmez.',
            confirmLabel: 'Merkeze ilet',
          );
          if (ok) await run(ctrl.forwardToHq);
        case 'invite':
          final email = detail.inviteCandidates.isEmpty
              ? null
              : await showAppSheet<String>(
                  context: context,
                  title: 'Davet kime gitsin?',
                  builder: (ctx) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in detail.inviteCandidates)
                        ChoiceCard(
                          title: e,
                          selected: e == detail.inviteEmail,
                          margin: const EdgeInsets.only(bottom: 8),
                          onTap: () => Navigator.of(ctx).pop(e),
                        ),
                    ],
                  ),
                );
          if (!context.mounted) return;
          if (detail.inviteCandidates.isNotEmpty && email == null) return;
          await run(() => ctrl.resendInvite(email: email));
        case 'cancel':
          final ok = await showConfirmSheet(
            context,
            title: 'Ön kayıt iptal edilsin mi?',
            message: 'İptal edilen ön kayıt finansa gönderilemez.',
            confirmLabel: 'İptal et',
            destructive: true,
          );
          if (ok) await run(ctrl.cancel);
      }
    }

    final hasMore = forward || invite || cancel;
    return Row(
      children: [
        if (hasMore)
          AknIconButton(
            icon: PhosphorIconsRegular.dotsThree,
            semanticLabel: 'Diğer işlemler',
            onPressed: online ? more : null,
          ),
        if (edit)
          Expanded(
            child: AknButton.secondary(
              label: 'Düzenle',
              icon: PhosphorIconsRegular.pencilSimple,
              expand: true,
              onPressed: () => context.push('${AppRoutes.fieldLead(id)}/edit'),
            ),
          ),
        if (edit && submit) const SizedBox(width: 12),
        if (submit)
          Expanded(
            child: AknButton(
              label: 'Finansa gönder',
              icon: PhosphorIconsRegular.paperPlaneRight,
              expand: true,
              showSuccess: false,
              onPressedAsync: online
                  ? () async {
                      final ok = await showConfirmSheet(
                        context,
                        title: 'Finansa gönderilsin mi?',
                        message:
                            'Finans ön kaydı inceler; ek bilgi isterse size bildirim gelir.',
                        confirmLabel: 'Gönder',
                        icon: PhosphorIconsRegular.paperPlaneRight,
                      );
                      if (ok) await run(ctrl.submit);
                    }
                  : null,
            ),
          ),
        if (!edit && !submit && !hasMore) const Spacer(),
      ],
    );
  }
}
