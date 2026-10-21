import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../application/approval_detail_controller.dart';
import '../application/approvals_providers.dart';
import '../copy.dart';
import '../data/approval_models.dart';
import '../shared/attachment_grid.dart';
import '../shared/failure_view.dart';
import '../shared/layout.dart';
import '../shared/uploads.dart';
import 'widgets/approval_card.dart';
import 'widgets/approval_timelines.dart';
import 'widgets/company_request_outcome.dart';
import 'widgets/decision_bar.dart';
import 'widgets/decision_sheets.dart';
import 'widgets/info_cards.dart';
import 'widgets/summary_sections.dart';

/// Onay ayrıntısı (spec A.4 A5): başlık, sunucu özeti, adımlar, olaylar, belgeler (açılış günlüğe
/// yazılır), karar çubuğu (`modes`), "X adına", karar veremeyene `decisionHint`; ek bilgi yanıtı
/// (`canProvideInfo`) ve "Bilgi alındı" (`canResumeInfo`). Cari görünümünde SLA ve kademe yoktur.
class ApprovalDetailPage extends ConsumerStatefulWidget {
  const ApprovalDetailPage({
    super.key,
    required this.id,
    this.focusReply = false,
  });

  final int id;

  /// `?reply=1`: yanıt alanına odaklanır (Finans bilgisi ekranından gelindiğinde).
  final bool focusReply;

  @override
  ConsumerState<ApprovalDetailPage> createState() => _ApprovalDetailPageState();
}

class _ApprovalDetailPageState extends ConsumerState<ApprovalDetailPage> {
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  String? _replyError;
  bool _replying = false;
  bool _focused = false;

  ApprovalDetailController get _ctrl =>
      ref.read(approvalDetailProvider(widget.id).notifier);

  @override
  void dispose() {
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _decide(ApprovalDecision m) async {
    final message = await showDecisionSheet(
      context,
      approvalId: widget.id,
      decision: m,
    );
    if (message != null && mounted) {
      AppToast.success(message, context: context);
    }
  }

  Future<void> _resume() async {
    final message = await showNoteActionSheet(
      context,
      title: 'Bilgi alındı',
      subtitle: 'Talep yeniden incelemeye alınır.',
      message:
          'İstenen bilgi ya da belge size başka yoldan (e-posta, telefon) ulaştıysa kısaca not edin.',
      noteLabel: 'Not (isteğe bağlı)',
      noteHint: 'Ör. Vergi levhası e-postayla geldi.',
      buttonLabel: 'İncelemeye al',
      icon: Icons.check_rounded,
      run: (note) => _ctrl.provideInfo(note: note, resume: true),
      onReload: _ctrl.refresh,
    );
    if (message != null && mounted) {
      AppToast.success(message, context: context);
    }
  }

  Future<void> _forward(int leadId) async {
    final message = await showNoteActionSheet(
      context,
      title: 'Merkeze ilet',
      subtitle: 'Cari açılışını merkez onaylar.',
      message:
          'Bu ön kaydın VKN\'si sistemde başka bir bayide kayıtlı. Talep merkez onayına iletilir; bayi kademesinde karar verilmez.',
      noteLabel: 'Merkeze not (isteğe bağlı)',
      buttonLabel: 'Merkeze ilet',
      icon: Icons.upload_rounded,
      run: (note) => _ctrl.forwardToHq(leadId, note: note),
      onReload: _ctrl.refresh,
    );
    if (message != null && mounted) {
      AppToast.success(message, context: context);
    }
  }

  Future<void> _sendReply(ApprovalDetail d) async {
    if (_replying) return;
    final target = replyTarget(d.id);
    final uploads = ref.read(uploadsProvider(target));
    final note = _reply.text.trim();
    if (uploads.any((u) => u.phase == UploadPhase.uploading)) {
      AppToast.info(
        'Belge yüklemesi sürüyor; birazdan yanıtlayın.',
        context: context,
      );
      return;
    }
    if (note.isEmpty && !uploads.any((u) => u.phase == UploadPhase.done)) {
      setState(
        () => _replyError = 'Yanıtınızı yazın ya da istenen belgeyi ekleyin.',
      );
      _replyFocus.requestFocus();
      return;
    }
    if (!requiredKindSatisfied(d, uploads)) {
      final kind = d.infoRequest?.displayKindLabel ?? 'Belge';
      final go = await showConfirmSheet(
        context,
        title: 'İstenen belge eklenmedi',
        message:
            '"$kind" istendi. Belge olmadan yanıtlarsanız talep yeniden ek bilgiye düşebilir.',
        confirmLabel: 'Yine de yanıtla',
        cancelLabel: 'Vazgeç',
        tone: AknTone.warn,
        icon: Icons.warning_amber_rounded,
      );
      if (!go || !mounted) return;
    }
    setState(() {
      _replying = true;
      _replyError = null;
    });
    final outcome = await _ctrl.provideInfo(note: note);
    if (!mounted) return;
    setState(() => _replying = false);
    switch (outcome) {
      case ActionDone(:final message):
        AknHaptics.success();
        _reply.clear();
        ref.invalidate(uploadsProvider(target));
        AppToast.success(message, context: context);
      case ActionConflict():
        AppToast.warning(
          'Talep güncellendi; ek bilgi artık beklenmiyor olabilir.',
          context: context,
        );
        unawaited(_ctrl.refresh());
      case ActionInvalid(:final fieldErrors, :final message):
        setState(() => _replyError = fieldErrors['note'] ?? message);
      case ActionFailed(:final failure):
        showFailureToast(context, failure);
      case ActionUnverified(:final message):
        AppToast.warning(message, context: context);
    }
  }

  void _openFile(ApprovalDetail d, String publicId) {
    _ctrl.markViewed(publicId);
    openAttachmentById(
      context,
      publicId: publicId,
      known: d.attachments,
      approvalId: d.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(approvalDetailProvider(widget.id));
    final d = s.detail;

    if (s.doneMessage != null) {
      return AppScaffold(
        title: 'Ek bilgi yanıtı',
        body: ListView(
          children: [
            ResultView(
              title: 'Yanıtınız iletildi',
              message: s.doneMessage,
              primaryLabel: 'Tamam',
              onPrimary: () =>
                  context.canPop() ? context.pop() : context.go(AppRoutes.home),
            ),
          ],
        ),
      );
    }

    if (d == null) {
      return AppScaffold(
        title: 'Onay talebi',
        body: s.error == null
            ? const _DetailSkeleton()
            : Center(
                child: SingleChildScrollView(
                  child: A5FailureView(
                    failure: s.error!,
                    onRetry: () => unawaited(_ctrl.refresh()),
                    notFoundTitle: ApprovalsCopy.notFoundTitle,
                    notFoundMessage: ApprovalsCopy.notFoundMessage,
                  ),
                ),
              ),
      );
    }

    if (widget.focusReply && !_focused && d.canProvideInfo) {
      _focused = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _replyFocus.requestFocus();
      });
    }

    final policy = ref.watch(accessPolicyProvider);
    final leadId = d.type == ApprovalType.leadFinance ? d.leadId : null;
    final lead = leadId == null
        ? null
        : ref.watch(leadForwardInfoProvider(leadId)).valueOrNull;
    // "Merkeze ilet": approve.finance.lead ile, talep finans onayı beklerken (Submitted / InReview).
    // Sunucunun ön kayıt bilgisi okunabiliyorsa onun `canForwardToHq` kuralı geçerlidir.
    final canForward =
        leadId != null &&
        policy.isBayi &&
        policy.hasCap(Caps.approveFinanceLead) &&
        d.status == ApprovalStatus.pending &&
        (lead == null
            ? true
            : (lead.awaitingFinance &&
                  lead.canForwardToHq &&
                  !lead.isForwardedToHq));

    final online = ref.watch(isOnlineProvider);
    Widget? actionBar;
    if (d.canProvideInfo && d.infoRequest != null) {
      actionBar = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!online)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Çevrimdışısınız; yanıt için bağlantı gerekli.',
                style: context.aknText.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          AknButton(
            label: 'Yanıtla',
            icon: Icons.reply_rounded,
            expand: true,
            size: AknButtonSize.large,
            loading: _replying,
            onPressed: online && !_replying ? () => _sendReply(d) : null,
          ),
        ],
      );
    } else if (d.canResumeInfo) {
      actionBar = _BarColumn(
        offline: !online,
        child: Row(
          children: [
            if (d.can(ApprovalDecision.reject)) ...[
              Expanded(
                child: AknButton.secondary(
                  label: d.modeLabel(ApprovalDecision.reject),
                  icon: Icons.close_rounded,
                  expand: true,
                  onPressed: online
                      ? () => _decide(ApprovalDecision.reject)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: AknButton(
                label: 'Bilgi alındı',
                icon: Icons.check_rounded,
                expand: true,
                onPressed: online ? _resume : null,
              ),
            ),
          ],
        ),
      );
    } else if (d.modes.isNotEmpty) {
      actionBar = DecisionBar(
        detail: d,
        onDecision: _decide,
        onForward: canForward ? () => _forward(leadId) : null,
      );
    } else if (canForward) {
      actionBar = _BarColumn(
        offline: !online,
        child: AknButton(
          label: 'Merkeze ilet',
          icon: Icons.upload_rounded,
          expand: true,
          onPressed: online ? () => _forward(leadId) : null,
        ),
      );
    }

    final children = <Widget>[
      _ApprovalHero(detail: d),
      _DecisionOutcomeBanner(detail: d),
      if (CompanyRequestOutcome.applies(d)) CompanyRequestOutcome(detail: d),
      if (d.canProvideInfo && d.infoRequest != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: InfoReplyCard(
            detail: d,
            note: _reply,
            noteFocus: _replyFocus,
            noteError: _replyError,
          ),
        )
      else if (d.canResumeInfo && d.infoRequest != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: InfoWaitingCard(detail: d),
        ),
      if (d.modes.isEmpty && d.decisionHint != null && !d.canProvideInfo)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AknBanner(
            tone: AknTone.neutral,
            icon: Icons.info_outline_rounded,
            message: d.decisionHint!,
          ),
        ),
      if (d.onBehalfOfName != null && d.modes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AknBanner(
            tone: AknTone.info,
            icon: Icons.share_rounded,
            message: '${d.onBehalfOfName} ${ApprovalsCopy.behalfNote}',
          ),
        ),
      if (lead?.isForwardedToHq ?? false)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AknBanner(
            tone: AknTone.info,
            icon: Icons.upload_rounded,
            message: 'Talep merkez onayına iletildi.',
          ),
        ),
      WarningBanners(warnings: d.summary.warnings),
      if (d.summary.facts.isNotEmpty)
        DetailSection(
          title: 'Özet',
          child: FactsCard(facts: d.summary.facts),
        ),
      if (d.summary.lines.isNotEmpty &&
          d.type != ApprovalType.companyOrderRequest)
        DetailSection(
          title: 'Kalemler',
          child: LinesCard(lines: d.summary.lines),
        )
      else if (d.summary.lines.isNotEmpty && !CompanyRequestOutcome.applies(d))
        DetailSection(
          title: 'Talep satırları',
          child: LinesCard(lines: d.summary.lines),
        ),
      RelatedLinksCard(detail: d),
      if (d.attachments.isNotEmpty)
        DetailSection(
          title: 'Belgeler',
          subtitle: d.customerView
              ? null
              : 'Açtığınız belgeler talebin günlüğüne yazılır.',
          child: A5AttachmentGrid(
            attachments: d.attachments,
            approvalId: d.id,
            onOpened: (a) => _ctrl.markViewed(a.publicId),
          ),
        ),
      if (d.customerView)
        DetailSection(
          title: 'Süreç',
          child: CustomerProcessTimeline(detail: d),
        )
      else ...[
        if (d.steps.isNotEmpty)
          DetailSection(
            title: 'Onay adımları',
            child: ApprovalStepsTimeline(detail: d),
          ),
        if (d.events.isNotEmpty)
          DetailSection(
            title: 'Olay günlüğü',
            child: ApprovalEventsLog(
              detail: d,
              onOpenFile: (id) => _openFile(d, id),
            ),
          ),
      ],
      const SizedBox(height: 24),
    ];

    return AppScaffold(
      title: d.type.label,
      subtitle: d.row.subjectNumber,
      refreshing: s.refreshing,
      actionBar: actionBar,
      body: PullToRefresh(
        onRefresh: _ctrl.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: children,
        ),
      ),
    );
  }
}

/// Alt çubuk içeriği: yüksekliği içeriğe göre (genişletilmiş düğme alt çubukta tüm yüksekliği
/// kaplamasın), çevrimdışıyken açıklama satırıyla.
class _BarColumn extends StatelessWidget {
  const _BarColumn({required this.child, required this.offline});

  final Widget child;
  final bool offline;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (offline)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            ApprovalsCopy.offlineDecision,
            style: context.aknText.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      child,
    ],
  );
}

/// Lacivert başlık: tür, durum, sunucu başlığı, tutar / litre, SLA geri sayımı ve kademe
/// (cari görünümünde yok), talep eden ve zaman.
class _ApprovalHero extends StatelessWidget {
  const _ApprovalHero({required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context) => AknHeroPanel(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: _HeroBody(detail: detail),
  );
}

class _HeroBody extends StatelessWidget {
  const _HeroBody({required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final d = detail;
    final status = approvalStatusStyle(
      d.row,
      customerSide: d.customerView,
      canProvideInfo: d.canProvideInfo,
    );
    final headline = d.summary.headline.isNotEmpty
        ? d.summary.headline
        : [?d.row.subjectNumber, ?d.row.customerTitle].join(' · ');
    // "SIP-… · Marmara İnşaat": numara ayrı satırda (büyük yazıda numara bölünmesin).
    final parts = headline.split(' · ');
    final codeFirst =
        parts.length > 1 &&
        !parts.first.contains(' ') &&
        RegExp(r'\d').hasMatch(parts.first);
    final number = codeFirst ? parts.first : null;
    final title = codeFirst ? parts.skip(1).join(' · ') : headline;
    final overdue =
        d.row.slaState == ApprovalSlaState.overdue ||
        (d.row.dueAt != null && d.row.dueAt!.isBefore(DateTime.now().toUtc()));
    final amount = d.summary.amount ?? d.row.amount;
    final liters = d.summary.liters ?? d.row.liters;
    final band = d.summary.band;
    final showSla = !d.customerView && d.isOpen && d.row.dueAt != null;
    final showLevels = !d.customerView && d.isOpen && d.row.hasLevels;
    final typeStyle = AknStatus.approvalType(d.type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(typeStyle.icon, size: 18, color: c.dim),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    d.row.displayTypeLabel,
                    style: t.captionStrong.copyWith(color: c.dim),
                  ),
                ),
              ],
            ),
            Shrinkable(child: StatusChip.style(status)),
          ],
        ),
        const SizedBox(height: 12),
        if (number != null)
          Text(
            number,
            style: t.label.copyWith(
              color: c.dim,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        Semantics(
          header: true,
          child: Text(title.isEmpty ? d.row.title : title, style: t.title),
        ),
        if (d.summary.subline != null) ...[
          const SizedBox(height: 4),
          Text(d.summary.subline!, style: t.body.copyWith(color: c.dim)),
        ],
        if (amount != null || liters != null) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              if (amount != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AmountText(Fmt.money(amount), large: true),
                ),
              if (liters != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: AmountText(
                    Fmt.liters(liters),
                    style: t.bodyStrong.copyWith(color: c.text),
                  ),
                ),
            ],
          ),
        ],
        if (showSla || showLevels || band != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (showSla && overdue)
                Shrinkable(
                  child: StatusChip.style(
                    AknStatus.sla(ApprovalSlaState.overdue),
                  ),
                )
              else if (showSla)
                Shrinkable(
                  child: CountdownBadge(
                    deadline: d.row.dueAt!,
                    start: d.row.createdAt,
                    prefix: 'Kalan',
                  ),
                ),
              if (showLevels)
                Shrinkable(
                  child: StatusChip(
                    label: 'Kademe ${d.row.currentLevelNo}/${d.row.levelCount}',
                    tone: AknTone.neutral,
                    icon: Icons.layers_rounded,
                  ),
                ),
              if (band != null)
                Shrinkable(
                  child: StatusChip.style(
                    AknStatus.custom(band.label, tone: band.tone),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(
          [
            if (d.row.requestedByName != null)
              'Talep eden: ${d.row.requestedByName}',
            Fmt.relative(d.row.createdAt),
          ].join(' · '),
          style: t.caption.copyWith(color: c.dim),
        ),
      ],
    );
  }
}

/// Sonuçlanmış talebin kararı (cari görünümünde yalnızca ret gerekçesi).
class _DecisionOutcomeBanner extends StatelessWidget {
  const _DecisionOutcomeBanner({required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final when = d.decidedAt == null ? null : Fmt.dateTime(d.decidedAt);
    final who = d.customerView ? null : d.decidedByName;
    final meta = [?who, ?when].join(' · ');
    final (tone, title) = switch (d.status) {
      ApprovalStatus.approved => (
        AknTone.ok,
        d.isConditionallyApproved ? 'Koşullu onaylandı' : 'Onaylandı',
      ),
      ApprovalStatus.rejected => (AknTone.danger, 'Reddedildi'),
      ApprovalStatus.cancelled => (AknTone.neutral, 'İptal edildi'),
      _ => (AknTone.neutral, ''),
    };
    if (title.isEmpty) return const SizedBox.shrink();
    final note = d.customerView && d.status != ApprovalStatus.rejected
        ? (d.isConditionallyApproved
              ? ApprovalsCopy.conditionalText(d.type)
              : null)
        : d.decisionNote;
    final message = [if (meta.isNotEmpty) meta, ?note].join('\n');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknBanner(
        tone: tone,
        title: title,
        message: message.isEmpty ? title : message,
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: const [
          SkeletonBox(height: 180, radius: 24),
          SizedBox(height: 16),
          SkeletonCard(lines: 4, leading: false, margin: EdgeInsets.zero),
          SizedBox(height: 12),
          SkeletonCard(lines: 3, leading: false, margin: EdgeInsets.zero),
          SizedBox(height: 12),
          SkeletonCard(margin: EdgeInsets.zero),
        ],
      ),
    );
  }
}
