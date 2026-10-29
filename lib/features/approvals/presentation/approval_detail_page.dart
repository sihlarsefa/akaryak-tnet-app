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
import '../../../core/utils/tr_time.dart';
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

/// Onay ayrıntısı (spec A.4 A5, tasarım v4 "Sade"): çubukta nesnenin türü ("Onay talebi"; kaydırınca
/// talebin adı), gövdenin ilk bloğu insan adıyla nesne başlığı ([AknObjectHeader]: tür, ad,
/// koşullar, kopyalanabilir belge numarası) ve şimdiki adım ([StageNow]: "Karar verin" + geri
/// sayım, talep eden · zaman · kademe); ekranın tek plakası (tutar sayaç gibi döner), sunucu özeti
/// ve kalemler, kendini çizen onay adımları, olay günlüğü, belgeler (açılış günlüğe yazılır);
/// bölümler sırayla yükselir. Karar rıhtımı [ActionBar.decision]: tek birincil ("Onayla", "Bilgi
/// alındı", "Bilgi gönder") ve çerçevesiz ikinciller (Reddet tehlike yazısıyla); çevrimdışıyken
/// açıklamalı kapalı çubuk. `?focus=request` talebin bloğuna kaydırıp parlatır. Cari görünümünde
/// SLA ve kademe yoktur.
class ApprovalDetailPage extends ConsumerStatefulWidget {
  const ApprovalDetailPage({
    super.key,
    required this.id,
    this.focusReply = false,
    this.focusRequest = false,
  });

  final int id;

  /// `?reply=1`: yanıt alanına odaklanır (Finans bilgisi ekranından gelindiğinde).
  final bool focusReply;

  /// `?focus=request` (v4 §3.5): talebin karar / yanıt bloğu görünür kılınır ve parlar.
  final bool focusRequest;

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
      icon: PhosphorIconsRegular.check,
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
      icon: PhosphorIconsRegular.uploadSimple,
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
        icon: PhosphorIconsFill.warning,
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

  /// v4 karar rıhtımı (çevrimiçi; tasarım v4 §4 [ActionBar.decision]): şimdi atılabilecek tek
  /// birincil adım ve çerçevesiz ikinciller (Reddet tehlike yazısıyla, en sağda). Yapılacak bir şey
  /// yoksa null.
  Widget? _decisionDock(ApprovalDetail d, int? forwardLeadId) {
    AknButton reject() => AknButton.danger(
      label: d.modeLabel(ApprovalDecision.reject),
      onPressed: () => unawaited(_decide(ApprovalDecision.reject)),
    );
    if (d.canProvideInfo && d.infoRequest != null) {
      return ActionBar.decision(
        primary: AknButton(
          label: ApprovalsCopy.sendInfo,
          icon: PhosphorIconsRegular.arrowBendUpLeft,
          loading: _replying,
          onPressed: () => unawaited(_sendReply(d)),
        ),
      );
    }
    if (d.canResumeInfo) {
      return ActionBar.decision(
        primary: AknButton(
          label: ApprovalsCopy.infoReceived,
          icon: PhosphorIconsRegular.check,
          onPressed: () => unawaited(_resume()),
        ),
        caption: ApprovalsCopy.infoReceivedCaption,
        secondaries: [if (d.can(ApprovalDecision.reject)) reject()],
      );
    }
    final forward = forwardLeadId == null
        ? null
        : () => unawaited(_forward(forwardLeadId));
    if (d.modes.isEmpty) {
      return forward == null
          ? null
          : ActionBar.decision(
              primary: AknButton(
                label: 'Merkeze ilet',
                icon: PhosphorIconsRegular.uploadSimple,
                onPressed: forward,
              ),
            );
    }
    final others = [
      for (final m in const [
        ApprovalDecision.requestInfo,
        ApprovalDecision.conditionalApprove,
      ])
        if (d.can(m)) m,
    ];
    final AknButton primary;
    if (d.can(ApprovalDecision.approve)) {
      primary = AknButton(
        label: d.modeLabel(ApprovalDecision.approve),
        onPressed: () => unawaited(_decide(ApprovalDecision.approve)),
      );
    } else if (forward != null) {
      primary = AknButton(label: 'Merkeze ilet', onPressed: forward);
    } else if (others.isNotEmpty) {
      final m = others.removeAt(0);
      primary = AknButton(
        label: d.modeLabel(m),
        onPressed: () => unawaited(_decide(m)),
      );
    } else {
      // Yalnızca ret: birincil turuncu "Reddet" olmaz; eski çubuk (tehlike düğmesi).
      return DecisionBar(detail: d, onDecision: _decide);
    }
    final moreForward = forward != null && d.can(ApprovalDecision.approve);
    final secondaries = <AknButton>[];
    // Büyük yazıda satıra en çok iki ikincil sığar: diğer kararlar "Diğer"de.
    if (others.isNotEmpty && !isLargeText(context)) {
      final m = others.removeAt(0);
      secondaries.add(
        AknButton.ghost(
          label: d.modeLabel(m),
          onPressed: () => unawaited(_decide(m)),
        ),
      );
    }
    if (others.isNotEmpty || moreForward) {
      final rest = [...others];
      secondaries.add(
        AknButton.ghost(
          label: 'Diğer',
          semanticLabel: [
            'Diğer kararlar',
            ...rest.map(d.modeLabel),
            if (moreForward) 'Merkeze ilet',
          ].join(', '),
          onPressed: () => unawaited(
            showMoreDecisions(
              context,
              detail: d,
              modes: rest,
              onDecision: _decide,
              onForward: moreForward ? forward : null,
            ),
          ),
        ),
      );
    }
    if (d.can(ApprovalDecision.reject)) secondaries.add(reject());
    return ActionBar.decision(primary: primary, secondaries: secondaries);
  }

  /// Çevrimdışı (spec C.4a): açıklamalı, kapalı çubuk.
  Widget? _offlineBar(ApprovalDetail d, int? forwardLeadId) {
    if (d.canProvideInfo && d.infoRequest != null) {
      return _BarColumn(
        offline: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Çevrimdışısınız; yanıt için bağlantı gerekli.',
                style: context.aknText.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            const AknButton(
              label: ApprovalsCopy.sendInfo,
              icon: PhosphorIconsRegular.arrowBendUpLeft,
              expand: true,
              size: AknButtonSize.large,
              onPressed: null,
            ),
          ],
        ),
      );
    }
    if (d.canResumeInfo) {
      return _BarColumn(
        offline: true,
        child: Row(
          children: [
            if (d.can(ApprovalDecision.reject)) ...[
              Expanded(
                child: AknButton.secondary(
                  label: d.modeLabel(ApprovalDecision.reject),
                  icon: PhosphorIconsRegular.x,
                  expand: true,
                  onPressed: null,
                ),
              ),
              const SizedBox(width: 12),
            ],
            const Expanded(
              flex: 2,
              child: AknButton(
                label: ApprovalsCopy.infoReceived,
                icon: PhosphorIconsRegular.check,
                expand: true,
                onPressed: null,
              ),
            ),
          ],
        ),
      );
    }
    if (d.modes.isNotEmpty) {
      return DecisionBar(
        detail: d,
        onDecision: _decide,
        onForward: forwardLeadId == null ? null : () => _forward(forwardLeadId),
      );
    }
    if (forwardLeadId != null) {
      return const _BarColumn(
        offline: true,
        child: AknButton(
          label: 'Merkeze ilet',
          icon: PhosphorIconsRegular.uploadSimple,
          expand: true,
          onPressed: null,
        ),
      );
    }
    return null;
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
            // Başarı anı: çizilen onay, parçacık patlaması ve başarı titreşimi (ResultView).
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
        title: ApprovalsCopy.detailTitle,
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
    // "Merkeze ilet": approve.finance.lead ile, talep finans onayı beklerken (Submitted /
    // InReview). Sunucunun ön kayıt bilgisi okunabiliyorsa onun `canForwardToHq` kuralı geçerlidir.
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
    // v4: çevrimiçi karar rıhtımı (tek birincil, çerçevesiz ikinciller); çevrimdışıyken
    // açıklamalı, kapalı çubuk (spec C.4a).
    final actionBar = online
        ? _decisionDock(d, canForward ? leadId : null)
        : _offlineBar(d, canForward ? leadId : null);

    final readouts = plateReadoutsFor(d);
    final usedFacts = {for (final r in readouts) r.label};
    final facts = [
      for (final f in d.summary.facts)
        if (!usedFacts.contains(f.label)) f,
    ];
    final replying = d.canProvideInfo && d.infoRequest != null;
    // `?focus=request`: talebin bloğu — yanıt beklenen ek bilgi kartı, yoksa talebin plakası.
    Widget focusable(Widget child, {required bool target}) => target
        ? AknFocusFlash(
            active: widget.focusRequest,
            borderRadius: AknRadius.plate,
            child: child,
          )
        : child;
    final names = approvalNames(d);
    final children = <Widget>[
      _Header(detail: d, names: names),
      // Sonuç ve "sıra sizde" blokları plakadan önce: ne oldu, ne yapmalı.
      _DecisionOutcomeBanner(detail: d),
      if (CompanyRequestOutcome.applies(d)) CompanyRequestOutcome(detail: d),
      if (replying)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: focusable(
            target: true,
            InfoReplyCard(
              detail: d,
              note: _reply,
              noteFocus: _replyFocus,
              noteError: _replyError,
            ),
          ),
        )
      else if (d.canResumeInfo && d.infoRequest != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: InfoWaitingCard(detail: d),
        ),
      focusable(
        target: !replying,
        _ApprovalPlate(detail: d, readouts: readouts),
      ),
      if (d.modes.isEmpty && d.decisionHint != null && !d.canProvideInfo)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: AknBanner(
            tone: AknTone.neutral,
            icon: PhosphorIconsRegular.info,
            message: d.decisionHint!,
          ),
        ),
      if (d.onBehalfOfName != null && d.modes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: AknBanner(
            tone: AknTone.info,
            icon: PhosphorIconsRegular.shareNetwork,
            message: '${d.onBehalfOfName} ${ApprovalsCopy.behalfNote}',
          ),
        ),
      if (lead?.isForwardedToHq ?? false)
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: AknBanner(
            tone: AknTone.info,
            icon: PhosphorIconsRegular.uploadSimple,
            message: 'Talep merkez onayına iletildi.',
          ),
        ),
      WarningBanners(warnings: d.summary.warnings),
      if (facts.isNotEmpty)
        DetailSection(
          title: 'Özet',
          child: FactsCard(facts: facts),
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
      title: ApprovalsCopy.detailTitle,
      collapsedTitle: names.title,
      refreshing: s.refreshing,
      actionBar: actionBar,
      body: PullToRefresh(
        onRefresh: _ctrl.refresh,
        // Ayrıntı sınırlı uzunlukta: hepsi kurulur (başlıktaki durum ve süreç kaydırınca da ağaçta
        // kalır, ekran okuyucu tüm sayfayı görür). Bölümler sırayla yükselir; durumları korunur.
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: StaggerScope(
            key: ValueKey(d.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: a5Staggered(children),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alt çubuk içeriği: yüksekliği içeriğe göre (genişletilmiş düğme alt çubukta tüm yüksekliği
/// kaplamasın), çevrimdışıyken açıklama satırıyla; ilk belirişte aşağıdan yükselir.
class _BarColumn extends StatelessWidget {
  const _BarColumn({required this.child, required this.offline});

  final Widget child;
  final bool offline;

  @override
  Widget build(BuildContext context) => A5FadeUp(
    offset: 16,
    duration: AknMotion.stagger,
    curve: AknMotion.emphasizedCurve,
    child: Column(
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
    ),
  );
}

/// Talebin insan adı ve kodu (v4 §3.2, P4): başlık sunucu başlığının kod olmayan parçaları
/// ("Körfez Nakliyat ve Ticaret", "Burak Yılmaz"), yoksa karşı taraf; kod (SSF-, SIP-, TLP-) yalnızca
/// kopyalanabilir alt yazı.
({String title, String? code}) approvalNames(ApprovalDetail d) {
  bool isCode(String p) =>
      RegExp(r'^[A-ZÇĞİÖŞÜ]{2,5}-[\d-]+$').hasMatch(p) ||
      RegExp(r'#\d+').hasMatch(p);
  final parts = [
    for (final p in d.summary.headline.split(' · '))
      if (p.trim().isNotEmpty) p.trim(),
  ];
  final human = [
    for (final p in parts)
      if (!isCode(p)) p,
  ].join(', ');
  final code =
      d.row.subjectNumber ??
      [
        for (final p in parts)
          if (isCode(p)) p,
      ].firstOrNull;
  final counterpart = d.customerView
      ? (d.type == ApprovalType.companyOrderRequest
            ? d.row.requestedByName
            : d.row.stationTitle)
      : d.row.customerTitle;
  final title = human.isNotEmpty
      ? human
      : (counterpart ?? d.row.requestedByName ?? d.row.title);
  return (title: title.isEmpty ? ApprovalsCopy.detailTitle : title, code: code);
}

/// Ayrıntının ilk bloğu (tasarım v4 §4 [AknObjectHeader] + [StageNow]): türün adı, talebin insan
/// adı (28/34 800), sunucunun alt satırı ve kopyalanabilir kod; altında şimdiki adım — izleyiciye
/// göre tek cümle ("Karar verin", Pas; "Onay bekleniyor") ve bayi görünümünde son tarih geri sayımı,
/// ardından talep eden · zaman · kademe.
class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.names});

  final ApprovalDetail detail;
  final ({String title, String? code}) names;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final lamp = approvalRowLamp(
      d.row,
      customerSide: d.customerView,
      canProvideInfo: d.canProvideInfo,
    );
    final now = DateTime.now().toUtc();
    final overdue =
        d.row.slaState == ApprovalSlaState.overdue ||
        (d.row.dueAt != null && d.row.dueAt!.isBefore(now));
    final showSla = !d.customerView && d.isOpen && d.row.dueAt != null;
    final levels = !d.customerView && d.isOpen && d.row.hasLevels
        ? 'kademe ${d.row.currentLevelNo}/${d.row.levelCount}'
        : null;
    final requester = d.row.requestedByName;
    final meta = [
      if (requester != null) 'Talep eden $requester',
      whenStamp(d.row.createdAt),
      ?levels,
    ].join(' · ');
    final subline = d.summary.subline;
    // Şimdiki adım tek cümle (v4 §3.2 emir kipi): karar verebilene "Karar verin", yanıt verecek
    // olana "Bilgi gönderin"; onaylayan yanıt beklerken "Yanıt bekleniyor"; diğerlerine lamba.
    final (sentence, yourMove) = d.modes.isNotEmpty
        ? (ApprovalsCopy.decideNext, true)
        : d.canProvideInfo
        ? (ApprovalsCopy.replyNext, true)
        : d.canResumeInfo
        ? (ApprovalsCopy.groupWaiting, false)
        : (lamp.label, lamp.yourMove);
    final Widget? trailing;
    if (showSla && overdue && d.row.dueAt != null) {
      trailing = Text(
        '${overdueShort(now.difference(d.row.dueAt!))} gecikti',
        style: context.aknText.label.copyWith(
          fontWeight: FontWeight.w600,
          color: context.akn.danger.fg,
          fontFeatures: AknNumerals.tabular,
        ),
      );
    } else if (showSla) {
      trailing = CountdownBadge(
        deadline: d.row.dueAt!,
        start: d.row.createdAt,
        yourMove: yourMove,
        compact: true,
        subject: 'Karar süresi',
      );
    } else {
      trailing = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.5,
          child: AknObjectHeader(
            overline: ApprovalsCopy.typeName(d.type),
            title: names.title,
            line: subline == null || subline.isEmpty ? null : subline,
            caption: names.code,
            // Uzun basınca kopyalama 18 dp'lik bir hedef olurdu (C.7: en az 48 dp); kod Özet'te de.
            copyCaption: false,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          // Büyük yazıda geri sayım cümlenin yanına sığmaz (çekirdek StageNow satırı kaydırmaz):
          // cümlenin altına iner.
          child: isLargeText(context) && trailing != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StageNow(
                      sentence: sentence,
                      yourMove: yourMove,
                      detail: meta.isEmpty ? null : meta,
                    ),
                    const SizedBox(height: 4),
                    trailing,
                  ],
                )
              : StageNow(
                  sentence: sentence,
                  yourMove: yourMove,
                  trailing: trailing,
                  detail: meta.isEmpty ? null : meta,
                ),
        ),
      ],
    );
  }
}

/// Plakadaki okuma (etiket, değer, birim).
typedef ApprovalReadout = ({String label, String value, String? unit});

/// Plakanın altındaki okumalar: sunucu özetinin kısa sayısal satırlarından en çok üçü (Miktar, Kâr
/// oranı, Risk sınıfı, Talep edilen vade …). Uzun metinler okumaya girmez, Özet'te kalır.
List<ApprovalReadout> plateReadoutsFor(ApprovalDetail d) {
  const preferred = [
    'Miktar',
    'Toplam miktar',
    'Aylık ihtiyaç',
    'Kâr',
    'Kâr oranı',
    'Risk sınıfı',
    'Talep edilen vade',
    'Vade',
    'Gecikmiş bakiye',
  ];
  final hasAmount = (d.summary.amount ?? d.row.amount) != null;
  final out = <ApprovalReadout>[];
  for (final label in preferred) {
    if (out.length == 3) break;
    final f = d.summary.facts.where((f) => f.label == label).firstOrNull;
    if (f == null) continue;
    // Risk bandı plakada siyah çipte; okumada tekrarlanmaz.
    if (label == 'Risk sınıfı' && d.summary.band != null) continue;
    final v = f.value.trim();
    if (v.isEmpty || v.length > 16) continue;
    // Tutar yokken litre plakanın kendisidir; okumada tekrarlanmaz.
    if (!hasAmount && v.endsWith(' L')) continue;
    final m = RegExp(r'^([%+\-]?[\d.,]+)\s+(\S.*)$').firstMatch(v);
    if (m == null) {
      out.add((label: label, value: v, unit: null));
      continue;
    }
    // Plakada kuruş yazılmaz ("21.060 ₺").
    final number = m[2] == '₺' && m[1]!.endsWith(',00')
        ? m[1]!.substring(0, m[1]!.length - 3)
        : m[1]!;
    out.add((label: label, value: number, unit: m[2]));
  }
  return out;
}

/// Ekranın tek plakası (§7.13): söz konusu tutar (finans: sipariş tutarı ya da talep edilen limit;
/// şirket onayı: tahmini tutar), risk bandı siyah çipte, okumalar. Tutar da litre de yoksa plaka
/// yok.
class _ApprovalPlate extends StatelessWidget {
  const _ApprovalPlate({required this.detail, required this.readouts});

  final ApprovalDetail detail;
  final List<ApprovalReadout> readouts;

  static String _title(ApprovalType t) => switch (t) {
    ApprovalType.orderFinance => 'Sipariş tutarı',
    ApprovalType.fieldFormFinance ||
    ApprovalType.fieldOrderProfit => 'Form tutarı',
    ApprovalType.limitChange ||
    ApprovalType.customerOnboarding ||
    ApprovalType.leadFinance => 'Talep edilen limit',
    ApprovalType.companyOrderRequest => 'Tahmini tutar',
    ApprovalType.unknown => 'Tutar',
  };

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final amount = d.summary.amount ?? d.row.amount;
    final liters = d.summary.liters ?? d.row.liters;
    if (amount == null && liters == null) return const SizedBox.shrink();
    final band = d.summary.band;
    final String value;
    final String? decimals;
    final String unit;
    final String spoken;
    if (amount != null) {
      final fixed = Fmt.number(amount, minFraction: 2, maxFraction: 2);
      final comma = fixed.lastIndexOf(',');
      value = comma < 0 ? fixed : fixed.substring(0, comma);
      decimals = comma < 0 || fixed.endsWith(',00')
          ? null
          : fixed.substring(comma);
      unit = '₺';
      spoken = '${_title(d.type)} ${Fmt.money(amount)}';
    } else {
      value = Fmt.number(liters, maxFraction: 3);
      decimals = null;
      unit = 'L';
      spoken = 'Miktar ${Fmt.liters(liters)}';
    }
    return AknPlate(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      semanticLabel: spoken,
      // v4: simge kutusu yok; zaman başlıktaki şimdiki adım satırında (bir kez).
      head: PlateHead(title: amount == null ? 'Miktar' : _title(d.type)),
      figure: PlateFigure(
        value: value,
        decimals: decimals,
        unit: unit,
        semanticLabel: spoken,
      ),
      delta: band == null ? null : _BandChip(label: band.label),
      below: readouts.isEmpty
          ? null
          // Okumalar en çok 1,5× (sütunlar korunur, değer sığmazsa küçülür).
          : MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.5,
              child: PlateReadouts(
                items: [
                  for (final r in readouts)
                    PlateReadout(label: r.label, value: r.value, unit: r.unit),
                ],
              ),
            ),
    );
  }
}

/// Karttaki risk / barem bandı: delta çipi dilinde (açık turuncu zemin, Pas yazı); uzun etiket
/// satır kaydırır, taşmaz.
class _BandChip extends StatelessWidget {
  const _BandChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        // Sahip kararı G: karttaki bant çipi delta çipi gibi (#FFF1E8 zemin, Pas yazı).
        decoration: BoxDecoration(
          color: c.deltaFill,
          borderRadius: AknRadius.tag,
        ),
        child: Text(
          label,
          style: t.bodySmall.copyWith(
            height: 20 / 14,
            fontWeight: FontWeight.w700,
            color: c.brandInk,
          ),
        ),
      ),
    );
  }
}

/// "bugün 10:05", "dün 14:20", "21 Eki 09:10".
String whenStamp(DateTime? at) {
  if (at == null) return Fmt.dash;
  final diff = TrTime.dayDiff(TrTime.now(), at);
  final time = Fmt.time(at);
  if (diff == 0) return 'bugün $time';
  if (diff == -1) return 'dün $time';
  return '${Fmt.dayMonth(at)} $time';
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
    final meta = [?who, ?when].join(', ');
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        children: const [
          SkeletonBox(height: 34, width: 240, radius: 10),
          SizedBox(height: 10),
          SkeletonBox(height: 14, width: 180, radius: 8),
          SizedBox(height: 14),
          SkeletonBox(height: 26, width: 160, radius: AknRadius.pill),
          SizedBox(height: 20),
          SkeletonBox(height: 200, radius: AknRadius.plateRadius),
          SizedBox(height: 20),
          SkeletonCard(lines: 3, margin: EdgeInsets.zero),
          SizedBox(height: 16),
          SkeletonCard(lines: 3, margin: EdgeInsets.zero),
        ],
      ),
    );
  }
}
