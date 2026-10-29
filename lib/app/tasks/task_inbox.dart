import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show IconData, VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/models/models.dart';
import '../../core/push/unread_count_provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/ui/ui.dart';
import '../../core/utils/format.dart';
import '../../core/utils/tr_time.dart';
import '../../core/utils/turkish_text.dart';
import '../../features/approvals/api.dart';
import '../../features/bayi/api.dart';
import '../../features/customer_orders/api.dart';

/// The task inbox (design v4 §3.4): ONE list of what waits for the viewer,
/// which feeds the home's "Sıra sizde" card, the Onaylar badge and Onaylar ›
/// Bende — so the three counts are equal by construction (P2). The inbox
/// holds data only; the screen that shows a task supplies its action (e.g.
/// [TaskActionKind.uploadDocument] opens `showPaymentDocumentSheet`).
///
/// * Customers: [customerTasksProvider] (ordering blocked → quote decisions
///   merged with their missing payment document → orphan documents →
///   reported deliveries → company requests and finance questions from
///   approvals `scope: toMe` → the draft, neutral and last).
/// * Bayi: [bayiTaskQueuesProvider] (quotes with the most urgent order,
///   approvals = the badge, orders to plan, drivers to assign, disputes,
///   overdue payments, documents to check, finance reviews, today's Tüpraş
///   price, field forms).
/// * Merkez: [platformTasksProvider] (approvals = the badge).
/// * [taskInboxProvider] picks the viewer's inbox; [taskCountProvider] is
///   the one number.

/// What a task is about.
enum TaskKind {
  // Customer.
  orderingBlocked,
  quoteDecision,
  paymentDocument,
  deliveryAcceptance,
  companyRequest,
  financeQuestion,
  draft,
  // Bayi queues.
  quotes,
  approvals,
  plan,
  assignDriver,
  disputes,
  overduePayments,
  documentsToCheck,
  financeReviews,
  tuprasToday,
  fieldForms,
  // Merkez.
  platformApprovals,
}

/// How a task reads: the viewer's move (Pas), blocking or overdue
/// (danger), a setup gap (warn), a neutral reminder.
enum TaskTone { yourMove, danger, warn, neutral }

/// What the task's primary does; the screen supplies the action.
enum TaskActionKind {
  /// Call the bayi (ordering blocked).
  callStation,

  /// Upload the missing payment document (`showPaymentDocumentSheet`).
  uploadDocument,

  /// Open the quote to decide.
  reviewQuote,

  /// Open the reported delivery to accept it.
  acceptDelivery,

  /// Open the company request to decide.
  decideRequest,

  /// Answer a finance question.
  provideInfo,

  /// Resume the draft order.
  resumeDraft,

  /// Open the quote sheet for the order (bayi).
  giveQuote,

  /// Enter today's Tüpraş price.
  enterPrices,

  /// Open the queue's list.
  openQueue,
}

/// One thing that waits (v4 §3.4): data only.
@immutable
class TaskItem {
  const TaskItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.route,
    this.orderId,
    this.subtitle,
    this.figure,
    this.deadline,
    this.tone = TaskTone.yourMove,
    this.focus,
    this.actionKind,
    this.actionLabel,
    this.caption,
    this.counts = true,
    this.count = 1,
    this.overdue = 0,
    this.amount,
    this.time,
    this.note,
    this.documentKind,
    this.createdAt,
    this.external = false,
  });

  /// Stable id ("quote-12002", "approvals").
  final String id;
  final TaskKind kind;

  /// The order it is about (merges and focus).
  final int? orderId;

  /// The imperative ("Teklifi onaylayın") or the queue ("Kararınızı
  /// bekleyen 9 talep").
  final String title;

  /// "Demir Petrol · Motorin 8.000 L · Tuzla Şantiye".
  final String? subtitle;

  /// The lead's figure ("338.800,00 ₺").
  final String? figure;

  /// When it expires (countdown).
  final DateTime? deadline;
  final TaskTone tone;

  /// Where the task opens (`/orders/12002`).
  final String route;

  /// `?focus=` block on the target page (quote, documents, delivery,
  /// request).
  final String? focus;
  final TaskActionKind? actionKind;

  /// The primary's label ("Çek görselini yükle", "Teklif ver").
  final String? actionLabel;

  /// Under the primary ("Yükledikten sonra onaylayabilirsiniz").
  final String? caption;

  /// False for reminders that do not count (the draft).
  final bool counts;

  /// Items in a queue (bayi: 9 approvals); 1 for a single task.
  final int count;

  /// Overdue items in the queue.
  final int overdue;

  /// A row's amount ("1.263.000,00 ₺").
  final String? amount;

  /// A time instead of a countdown ("bugün 17:17").
  final String? time;

  /// A row note ("Önce çek görselini yükleyin").
  final String? note;

  /// The missing payment document's kind ([TaskActionKind.uploadDocument]).
  final AttachmentKind? documentKind;

  /// When it arrived (overdue sort: oldest first).
  final DateTime? createdAt;

  /// The action opens outside the app (today's Tüpraş price is entered on
  /// the web portal): the card marks it with ↗ ([AknTask.external], v4 B15).
  final bool external;

  /// [route] with `?focus=` when set.
  String get location {
    final f = focus;
    if (f == null) return route;
    final uri = Uri.parse(route);
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'focus': f})
        .toString();
  }

  /// Blocks everything else (ordering blocked).
  bool get blocking => kind == TaskKind.orderingBlocked;

  /// The card's look for this task, with the screen's actions.
  AknTask toAknTask({
    VoidCallback? onTap,
    VoidCallback? onAction,
    Future<void> Function()? onActionAsync,
    IconData? icon,
  }) => AknTask(
    id: id,
    title: title,
    subtitle: subtitle,
    icon: icon ?? glyph,
    tone: switch (tone) {
      TaskTone.yourMove => AknTaskTone.yourMove,
      TaskTone.danger => AknTaskTone.danger,
      TaskTone.warn => AknTaskTone.warn,
      TaskTone.neutral => AknTaskTone.neutral,
    },
    figure: figure,
    amount: amount,
    deadline: deadline,
    time: time,
    actionLabel: actionLabel,
    onAction: onAction,
    onActionAsync: onActionAsync,
    caption: caption,
    note: note,
    onTap: onTap,
    counts: counts,
    external: external,
  );

  /// This task's glyph: a finance question answered with a document shows
  /// the upload glyph, like the document it asks for.
  IconData get glyph => kind == TaskKind.financeQuestion && documentKind != null
      ? PhosphorIconsRegular.fileArrowUp
      : iconOf(kind);

  /// The glyph of a task kind.
  static IconData iconOf(TaskKind kind) => switch (kind) {
    TaskKind.orderingBlocked => PhosphorIconsRegular.prohibit,
    TaskKind.quoteDecision => PhosphorIconsRegular.invoice,
    TaskKind.paymentDocument => PhosphorIconsRegular.fileArrowUp,
    TaskKind.deliveryAcceptance => PhosphorIconsRegular.truck,
    TaskKind.companyRequest => PhosphorIconsRegular.checkCircle,
    TaskKind.financeQuestion => PhosphorIconsRegular.question,
    TaskKind.draft => PhosphorIconsRegular.notePencil,
    TaskKind.quotes => PhosphorIconsRegular.invoice,
    TaskKind.approvals ||
    TaskKind.platformApprovals => PhosphorIconsRegular.checkCircle,
    TaskKind.plan => PhosphorIconsRegular.calendarPlus,
    TaskKind.assignDriver => PhosphorIconsRegular.steeringWheel,
    TaskKind.disputes => PhosphorIconsRegular.warningCircle,
    TaskKind.overduePayments => PhosphorIconsRegular.wallet,
    TaskKind.documentsToCheck => PhosphorIconsRegular.files,
    TaskKind.financeReviews => PhosphorIconsRegular.bank,
    TaskKind.tuprasToday => PhosphorIconsRegular.gasPump,
    TaskKind.fieldForms => PhosphorIconsRegular.filePlus,
  };

  @override
  String toString() => 'TaskItem($id, $title)';
}

/// The viewer's tasks, in order.
@immutable
class TaskInbox {
  const TaskInbox({this.items = const [], this.loading = false});

  static const empty = TaskInbox();

  final List<TaskItem> items;

  /// Still loading the first data (the home shows a skeleton).
  final bool loading;

  /// The one number (v4 P2): the counting tasks. Customer: the home's
  /// count = the Onaylar badge = Bende's length.
  int get count => items.where((t) => t.counts).length;

  bool get isEmpty => items.isEmpty;

  /// The task for [kind] (queues), or null.
  TaskItem? of(TaskKind kind) {
    for (final t in items) {
      if (t.kind == kind) return t;
    }
    return null;
  }

  /// The viewer's next task, other than the one at [except] (the page whose
  /// task is done or was handled by someone else): the first counting task,
  /// else null. "Sıradaki işiniz ›" opens it (v4 §3.5.3). A task done on the
  /// web portal ([TaskItem.external], today's Tüpraş price) is never "next":
  /// its route only shows the home.
  TaskItem? next({String? except}) {
    final skip = except == null ? null : taskPath(except);
    for (final t in items) {
      if (!t.counts || t.external) continue;
      if (skip != null && taskPath(t.route) == skip) continue;
      return t;
    }
    return null;
  }
}

/// The path of an app location ("/orders/12002?focus=quote" →
/// "/orders/12002").
String taskPath(String location) {
  final uri = Uri.tryParse(location.trim());
  return uri == null || uri.path.isEmpty ? location.trim() : uri.path;
}

/// The label of the link to the viewer's next task (v4 §3.5.3).
const nextTaskLabel = 'Sıradaki işiniz';

/// The inbox sort (v4 §3.4): blocking → a deadline within 60 min → overdue
/// (oldest first) → the nearest deadline → the bigger count; ties keep the
/// given order; neutral reminders always last.
List<TaskItem> sortTasks(List<TaskItem> items, {DateTime? now}) {
  final at = now ?? TrTime.now();
  int rank(TaskItem t) {
    if (t.tone == TaskTone.neutral) return 9;
    if (t.blocking) return 0;
    final d = t.deadline;
    if (d != null && d.difference(at) <= const Duration(minutes: 60)) {
      return 1;
    }
    if (t.overdue > 0 || t.tone == TaskTone.danger) return 2;
    if (d != null) return 3;
    return 4;
  }

  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final ra = rank(a.$2);
    final rb = rank(b.$2);
    if (ra != rb) return ra.compareTo(rb);
    switch (ra) {
      case 1 || 3:
        final c = a.$2.deadline!.compareTo(b.$2.deadline!);
        if (c != 0) return c;
      case 2:
        final ca = a.$2.createdAt;
        final cb = b.$2.createdAt;
        if (ca != null && cb != null) {
          final c = ca.compareTo(cb);
          if (c != 0) return c;
        }
      case 4:
        final c = b.$2.count.compareTo(a.$2.count);
        if (c != 0) return c;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, t) in indexed) t];
}

// ───────────────────────────── Customer ─────────────────────────────

/// An order's line: the party by its short name ([taskCompanyName]), the
/// product before its litres and the place (v4 P4: one word order
/// everywhere). The bayi reads "Körfez Nakliyat · Motorin 10.000 L" (who
/// ordered comes first); the customer reads "Motorin 8.000 L · Tuzla Şantiye
/// · Demir Petrol" ([partyLast]: the order itself first, so a row that has
/// room for one fact still says which order it is). The words inside each
/// fact are bound with no-break spaces ([Fmt.whole]), so a wrapped line
/// breaks only at " · " ("Tuzla Şantiye" never splits; v4 A17).
String _orderLine({
  String? station,
  String? product,
  double? liters,
  String? place,
  bool partyLast = false,
}) {
  final party = taskCompanyName(station);
  return _facts([
    if (!partyLast) party,
    [
      if (product != null && product.isNotEmpty) product,
      if (liters != null && liters > 0) Fmt.liters(liters),
    ].join(' '),
    ?place,
    if (partyLast) party,
  ]);
}

/// A task line of facts joined by " · ", each fact kept whole ([Fmt.whole]).
String _facts(List<String> facts) => [
  for (final f in facts)
    if (f.trim().isNotEmpty) Fmt.whole(f),
].join(' · ');

/// A company's short name in task lines: the words before the legal and
/// sector suffixes ("Demir Petrol Akaryakıt Ltd. Şti." → "Demir Petrol").
/// The hero and Onaylar › Bende read the same words because the inbox
/// writes them (P2).
String taskCompanyName(String? title) => TurkishText.shortCompany(title);

/// A task's money: "1.263.000 ₺" when there are no kuruş ("1.263.000,50 ₺"
/// otherwise), so the row's right column fits a 360 dp phone and the hero
/// and Bende print the same figure.
String _money(double v) => Fmt.money(v).replaceFirst(RegExp(r',00(?= ₺$)'), '');

/// What a company request asks for, product before litres ("Motorin 30.000
/// L"), from the row's summary — "30.000 L Motorin · Pendik …" or the
/// server's "Motorin (Euro 5) · 14.000 L · tahmini …" — else its litres. A
/// request for several products (the server's "Motorin, Kalorifer Yakıtı ·
/// 30.000 L · …") reads "30.000 L · 2 ürün": the line never names one
/// product for a mixed request (v4 B11).
List<String> _requestFacts(ApprovalRow a) {
  final parts = [
    for (final p in (a.summary ?? '').split(' · '))
      if (p.trim().isNotEmpty) p.trim(),
  ];
  final litres = RegExp(r'^\d[\d.]*(?:,\d+)? L$');
  final litresFirst = RegExp(r'^(\d[\d.]*(?:,\d+)? L) (.+)$');
  if (parts.isNotEmpty) {
    final m = litresFirst.firstMatch(parts.first);
    if (m != null) return ['${m.group(2)} ${m.group(1)}'];
    if (parts.length > 1 && litres.hasMatch(parts[1])) {
      final products = [
        for (final p in parts.first.split(','))
          if (p.trim().isNotEmpty) p.trim(),
      ];
      if (products.length > 1) {
        return [parts[1], '${products.length} ürün'];
      }
      return ['${parts.first} ${parts[1]}'];
    }
  }
  return [if (a.liters != null) Fmt.liters(a.liters)];
}

/// The dashboard row of [orderId] (decisions, then orders at the bayi).
DashboardOrderRow? _orderOf(CustomerDashboard dash, int? orderId) {
  if (orderId == null) return null;
  for (final r in [...dash.pendingDecisions, ...dash.awaitingStation]) {
    if (r.orderId == orderId) return r;
  }
  return null;
}

/// What the bayi asks for, as the object of "istiyor" ("Bayiniz bu
/// siparişin çek görselini istiyor").
String _askedFor(AttachmentKind kind) => switch (kind) {
  AttachmentKind.chequeImage => 'çek görselini',
  AttachmentKind.promissoryNoteImage => 'senet görselini',
  AttachmentKind.transferReceipt => 'dekontunu',
  AttachmentKind.posSlip => 'POS slibini',
  _ => 'ödeme belgesini',
};

/// The order a finance question is about (the approval's subject), or null.
int? _questionOrder(ApprovalRow a) =>
    a.subjectType == 'Order' && a.subjectId > 0 ? a.subjectId : null;

/// A company request or a finance question the viewer must answer.
bool _isFinanceQuestion(ApprovalRow a) =>
    a.type != ApprovalType.companyOrderRequest ||
    a.status == ApprovalStatus.infoRequested;

/// The customer's tasks (v4 §3.4), in the inbox's order.
final customerTasksProvider = Provider.autoDispose<TaskInbox>((ref) {
  final policy = ref.watch(accessPolicyProvider);
  if (!policy.isCustomer) return TaskInbox.empty;
  final state = ref.watch(customerHomeProvider);
  final home = state.data;
  // One rule for "the customer decides" (v4 round 2): the hero, the badge,
  // Bende, Siparişler and the order page read the same predicate.
  final canDecide = policy.customerDecides;
  final approvalsOn = policy.can(Pg.customerApprovals);
  final approvals = approvalsOn
      ? ref.watch(approvalsListProvider(const ApprovalsQuery()))
      : null;
  final canCreate = policy.can(Pg.customerCreateOrder, Perm.create);
  final draft = canCreate ? ref.watch(draftSummaryProvider).valueOrNull : null;
  if (home == null) {
    return TaskInbox(loading: state.isFirstLoad);
  }
  return TaskInbox(
    items: buildCustomerTasks(
      home: home,
      canDecide: canDecide,
      approvals: approvals?.items ?? const [],
      draft: draft,
    ),
  );
});

/// Pure: the customer's tasks from the home, the approvals rows (`scope:
/// toMe`, page 1) and the draft (tests call it directly).
List<TaskItem> buildCustomerTasks({
  required CustomerHomeData home,
  required bool canDecide,
  List<ApprovalRow> approvals = const [],
  DraftSummary? draft,
  DateTime? now,
}) {
  final at = now ?? TrTime.now();
  final dash = home.dashboard;
  final items = <TaskItem>[];
  // With a single bayi its name is the same on every line: the lines say the
  // order instead ("Motorin 8.000 L · Tuzla Şantiye"; P4, say it once).
  final oneBayi = home.stations.length <= 1;

  // 1. Ordering blocked.
  if (!home.canOrder && home.hasStations) {
    final reason = home.ordering?.blockReason;
    items.add(
      TaskItem(
        id: 'ordering-blocked',
        kind: TaskKind.orderingBlocked,
        title: 'Şu an sipariş veremiyorsunuz',
        subtitle: reason ?? 'Bayinizle görüşerek açabilirsiniz.',
        tone: TaskTone.danger,
        route: home.ordering?.infoRequested ?? false
            ? AppRoutes.financeInfo
            : AppRoutes.limits,
        actionKind: TaskActionKind.callStation,
        actionLabel: 'Bayinizi arayın',
      ),
    );
  }

  // 2. Quote decisions, merged with their missing payment document.
  final docs = home.pendingPaymentDocuments;
  final decided = <int>{};
  // Finance questions keyed by their order: the order's missing payment
  // document merges into the question (one task, one count), so an order
  // never shows up twice (§3.4).
  final asked = <int>{
    for (final a in approvals)
      if (_isFinanceQuestion(a)) ?_questionOrder(a),
  };
  if (canDecide) {
    for (final row in dash.pendingDecisions) {
      // Held by the bayi's finance: not the customer's move.
      if (row.financeStatus == OrderFinanceStatus.pending ||
          row.status != OrderStatus.awaitingApproval) {
        continue;
      }
      decided.add(row.orderId);
      final doc = docs.where((d) => d.orderId == row.orderId).firstOrNull;
      final left = row.remaining(now: DateTime.now().toUtc());
      final deadline = dash.expiryEnabled && row.msLeft > 0
          ? at.add(left)
          : null;
      items.add(
        TaskItem(
          id: 'quote-${row.orderId}',
          kind: TaskKind.quoteDecision,
          orderId: row.orderId,
          title: 'Teklifi onaylayın',
          subtitle: _orderLine(
            station: oneBayi ? null : row.stationTitle,
            product: row.productName,
            liters: row.quantityLiters,
            place: row.deliveryPointName ?? row.deliveryCity,
            partyLast: true,
          ),
          figure: row.latestTotalAmountTry == null
              ? null
              : _money(row.latestTotalAmountTry!),
          amount: row.latestTotalAmountTry == null
              ? null
              : _money(row.latestTotalAmountTry!),
          deadline: deadline,
          route: AppRoutes.order(row.orderId),
          focus: doc == null ? 'quote' : 'documents',
          actionKind: doc == null
              ? TaskActionKind.reviewQuote
              : TaskActionKind.uploadDocument,
          actionLabel: doc == null
              ? 'Teklifi incele'
              : AknStatus.uploadAction(doc.kind),
          caption: doc == null
              ? null
              : 'Yükledikten sonra teklifi onaylayabilirsiniz',
          note: doc == null
              ? null
              : 'Önce ${_lowerFirst(AknStatus.uploadPhrase(doc.kind))}',
          documentKind: doc?.kind,
          createdAt: row.updatedAt ?? row.createdAt,
        ),
      );
    }
  }

  // 3. Orphan documents (no decision or finance question carries them),
  // named by their order ("Motorin 12.000 L · Pendik Lojistik Merkezi") so
  // they never read like the lead's own upload. They belong to whoever
  // decides the quote: for a requester the company-wide list is not their
  // move (v4 round 2).
  for (final d in docs) {
    if (!canDecide) break;
    if (decided.contains(d.orderId) || asked.contains(d.orderId)) continue;
    final order = _orderOf(dash, d.orderId);
    items.add(
      TaskItem(
        id: 'document-${d.orderId}-${d.kind.code}',
        kind: TaskKind.paymentDocument,
        orderId: d.orderId,
        title: AknStatus.uploadPhrase(d.kind),
        subtitle: order == null
            ? _orderLine(station: d.stationTitle)
            : _orderLine(
                product: order.productName,
                liters: order.quantityLiters,
                place: order.deliveryPointName ?? order.deliveryCity,
              ),
        route: AppRoutes.order(d.orderId),
        focus: 'documents',
        actionKind: TaskActionKind.uploadDocument,
        actionLabel: AknStatus.uploadAction(d.kind),
        documentKind: d.kind,
      ),
    );
  }

  // 4. Reported deliveries.
  if (canDecide) {
    for (final s in dash.shipments) {
      if (s.status != ShipmentStatus.reported) continue;
      items.add(
        TaskItem(
          id: 'delivery-${s.shipmentId}',
          kind: TaskKind.deliveryAcceptance,
          orderId: s.orderId,
          title: 'Teslimatı onaylayın',
          // The litres are the row's amount: the line does not say them
          // twice (P4).
          subtitle: _orderLine(
            station: oneBayi ? null : s.stationTitle,
            product: s.productName,
            place: s.deliveryPointName ?? s.deliveryCity,
            partyLast: true,
          ),
          amount: Fmt.liters(s.deliveredLiters ?? s.plannedLiters),
          time: s.deliveredAt == null ? null : Fmt.relative(s.deliveredAt),
          route: AppRoutes.shipment(s.shipmentId),
          focus: 'delivery',
          actionKind: TaskActionKind.acceptDelivery,
          actionLabel: 'Teslimatı onayla',
          createdAt: s.deliveredAt ?? s.updatedAt,
        ),
      );
    }
  }

  // 5. Company requests and finance questions (approvals `scope: toMe`,
  // page 1, deduplicated by id).
  final seen = <int>{};
  var financeQuestion = false;
  for (final a in approvals) {
    if (!seen.add(a.id)) continue;
    if (!_isFinanceQuestion(a)) {
      // "Talebi onaylayın" · "Burak Yılmaz · Motorin 30.000 L": the verb
      // first, the requester and what they ask for under it.
      final who = a.requestedByName?.trim() ?? '';
      items.add(
        TaskItem(
          id: 'request-${a.id}',
          kind: TaskKind.companyRequest,
          title: 'Talebi onaylayın',
          subtitle: _facts([who, ..._requestFacts(a)]),
          amount: a.amount == null ? null : _money(a.amount!),
          time: a.createdAt == null ? null : Fmt.relative(a.createdAt),
          deadline: a.dueAt,
          route: AppRoutes.approval(a.id),
          focus: 'request',
          actionKind: TaskActionKind.decideRequest,
          actionLabel: 'Talebi incele',
          createdAt: a.createdAt,
        ),
      );
      continue;
    }
    financeQuestion = true;
    final orderId = _questionOrder(a);
    // The order's missing payment document IS the answer the bayi waits
    // for: one task that names the order and uploads it.
    final doc = orderId == null || decided.contains(orderId)
        ? null
        : docs.where((d) => d.orderId == orderId).firstOrNull;
    final asker = taskCompanyName(a.stationTitle);
    if (doc != null) {
      final order = _orderOf(dash, orderId);
      items.add(
        TaskItem(
          id: 'info-${a.id}',
          kind: TaskKind.financeQuestion,
          orderId: orderId,
          title: AknStatus.uploadPhrase(doc.kind),
          // The order by its product, litres and place; the note says who
          // asks (the title already says what): one fact once (v4 round 2).
          subtitle: order == null
              ? _orderLine(
                  station: a.stationTitle,
                  liters: a.liters,
                  partyLast: true,
                )
              : _orderLine(
                  product: order.productName,
                  liters: order.quantityLiters,
                  place: order.deliveryPointName ?? order.deliveryCity,
                ),
          note: asker.isEmpty
              ? 'Bayiniz bu siparişin ${_askedFor(doc.kind)} istiyor'
              : '$asker istiyor',
          // The row carries when the request was opened, not when the bayi
          // asked for the document: no time rather than a wrong one.
          route: AppRoutes.approval(a.id),
          focus: 'request',
          actionKind: TaskActionKind.provideInfo,
          actionLabel: AknStatus.uploadAction(doc.kind),
          documentKind: doc.kind,
          createdAt: a.createdAt,
        ),
      );
      continue;
    }
    items.add(
      TaskItem(
        id: 'info-${a.id}',
        kind: TaskKind.financeQuestion,
        orderId: orderId,
        title: 'Bilgi gönderin',
        subtitle: asker.isEmpty ? 'Bayiniz bilgi istiyor' : '$asker soruyor',
        time: a.createdAt == null ? null : Fmt.relative(a.createdAt),
        route: AppRoutes.approval(a.id),
        focus: 'request',
        actionKind: TaskActionKind.provideInfo,
        actionLabel: 'Bilgi gönder',
        createdAt: a.createdAt,
      ),
    );
  }
  // The finance card's own question (Finans bilgisi) when the approvals
  // list does not carry it.
  if (!financeQuestion && home.financeInfoRequests > 0 && home.canOrder) {
    final asker = taskCompanyName(home.stationTitle);
    items.add(
      TaskItem(
        id: 'finance-info',
        kind: TaskKind.financeQuestion,
        title: 'Bilgi gönderin',
        subtitle: asker.isEmpty
            ? 'Bayiniz bilgi istiyor'
            : '$asker bilgi istiyor',
        route: AppRoutes.financeInfo,
        actionKind: TaskActionKind.provideInfo,
        actionLabel: 'Bilgi gönder',
      ),
    );
  }

  // 6. The draft: neutral, always last, not counted.
  final sorted = sortTasks(items, now: at);
  if (draft != null && !draft.pendingSubmission) {
    sorted.add(
      TaskItem(
        id: 'draft',
        kind: TaskKind.draft,
        title: 'Yarım kalan siparişiniz',
        subtitle: _facts([
          if (draft.lineCount > 0) '${draft.lineCount} ürün',
          if (draft.totalLiters > 0) Fmt.liters(draft.totalLiters),
        ]),
        tone: TaskTone.neutral,
        route: AppRoutes.orderNew,
        actionKind: TaskActionKind.resumeDraft,
        actionLabel: 'Siparişe devam edin',
        counts: false,
      ),
    );
  }
  return sorted;
}

/// Lower-cases the first letter of an imperative for a note ("Önce çek
/// görselini yükleyin").
String _lowerFirst(String s) =>
    s.isEmpty ? s : '${TurkishText.lower(s.substring(0, 1))}${s.substring(1)}';

// ─────────────────────────────── Bayi ───────────────────────────────

/// Segment counts of the bayi's orders (`GET bayi/orders/counts`): the
/// "orders to plan" queue. Null when the viewer cannot plan.
final bayiOrderCountsProvider = FutureProvider.autoDispose<BayiOrderCounts?>((
  ref,
) async {
  final policy = ref.watch(accessPolicyProvider);
  if (!policy.isBayi || !policy.can(Pg.stationShipmentBoard, Perm.edit)) {
    return null;
  }
  // Re-read whenever the home refreshes.
  ref.watch(bayiHomeProvider.select((s) => s.updatedAt));
  try {
    return await ref.read(bayiRepositoryProvider).orderCounts();
  } on Object {
    return null;
  }
});

/// The bayi's queues (v4 §3.4) from the home and the Onaylar badge.
final bayiTaskQueuesProvider = Provider.autoDispose<TaskInbox>((ref) {
  final policy = ref.watch(accessPolicyProvider);
  if (!policy.isBayi) return TaskInbox.empty;
  final state = ref.watch(bayiHomeProvider);
  final data = state.data;
  final badge = ref.watch(unreadCountProvider.select((u) => u.approvals));
  final counts = ref.watch(bayiOrderCountsProvider).valueOrNull;
  if (data == null) return TaskInbox(loading: state.loading);
  final canPlan = policy.can(Pg.stationShipmentBoard, Perm.edit);
  return TaskInbox(
    items: buildBayiTasks(
      data: data,
      approvalsBadge: policy.isApprover ? badge : 0,
      toPlan: counts?.of(BayiOrderSegment.toPlan) ?? 0,
      // Quoting is the create grant, not seeing the desk (v4 round 2): a
      // viewer or finance never gets a quote task, nor "Sıradaki işiniz" on
      // an order they cannot quote.
      canQuote: policy.quotesOrders,
      canPlan: canPlan,
      // Disputes are a task only for who can act on a shipment (plan or
      // edit it); a read-only viewer is told nothing is theirs to do.
      canResolve:
          canPlan ||
          (policy.can(Pg.stationShipments, Perm.edit) &&
              !policy.hasCap(Caps.shipmentOwnOnly)),
    ),
  );
});

/// Pure: the bayi's queues (tests call it directly).
List<TaskItem> buildBayiTasks({
  required BayiHomeData data,
  int approvalsBadge = 0,
  int toPlan = 0,
  bool canQuote = true,
  bool canPlan = true,
  bool canResolve = true,
  DateTime? now,
}) {
  final at = now ?? TrTime.now();
  final items = <TaskItem>[];

  // Quotes, led by the most urgent order.
  final desk = data.desk;
  if (desk != null && canQuote && desk.openForQuote > 0) {
    final pool = [...desk.expiring, ...desk.awaitingQuoteList];
    DashboardOrderRow? lead;
    for (final o in pool) {
      if (o.status != OrderStatus.awaitingQuote &&
          o.status != OrderStatus.revisionRequested) {
        continue;
      }
      if (lead == null) {
        lead = o;
        continue;
      }
      final a = o.msLeft > 0 ? o.msLeft : 1 << 52;
      final b = lead.msLeft > 0 ? lead.msLeft : 1 << 52;
      if (a < b) lead = o;
    }
    final n = desk.openForQuote;
    if (lead != null) {
      final left = lead.remaining(now: DateTime.now().toUtc());
      items.add(
        TaskItem(
          id: 'quotes',
          kind: TaskKind.quotes,
          orderId: lead.orderId,
          title: lead.status == OrderStatus.revisionRequested
              ? 'Teklifi yenileyin'
              : 'Teklif verin',
          subtitle: _orderLine(
            station: lead.customerTitle,
            product: lead.productName,
            liters: lead.quantityLiters,
          ),
          deadline: desk.expiryEnabled && lead.msLeft > 0 ? at.add(left) : null,
          route: AppRoutes.bayiOrder(lead.orderId),
          focus: 'quote',
          actionKind: TaskActionKind.giveQuote,
          actionLabel: 'Teklif ver',
          caption: n > 1 ? '$n sipariş teklif bekliyor' : null,
          count: n,
        ),
      );
    } else {
      items.add(
        TaskItem(
          id: 'quotes',
          kind: TaskKind.quotes,
          title: '$n sipariş teklif bekliyor',
          route: AppRoutes.quoteDesk,
          actionKind: TaskActionKind.openQueue,
          actionLabel: 'Teklif ver',
          count: n,
        ),
      );
    }
  }

  // Approvals: the count IS the Onaylar badge. The overdue clause is the
  // subline, so the one-line row title is never cut ("… · 1'i g…").
  if (approvalsBadge > 0) {
    final overdue = data.approvals?.overdue ?? 0;
    items.add(
      TaskItem(
        id: 'approvals',
        kind: TaskKind.approvals,
        title: 'Kararınızı bekleyen $approvalsBadge talep',
        subtitle: overdue > 0 ? "$overdue'${_si(overdue)} gecikti" : null,
        tone: overdue > 0 ? TaskTone.danger : TaskTone.yourMove,
        route: AppRoutes.approvals,
        actionKind: TaskActionKind.openQueue,
        actionLabel: 'Talepleri incele',
        count: approvalsBadge,
        overdue: overdue,
      ),
    );
  }

  final ship = data.shipments;
  if (canPlan && toPlan > 0) {
    items.add(
      TaskItem(
        id: 'plan',
        kind: TaskKind.plan,
        title: 'Planlanmayı bekleyen $toPlan sipariş',
        route: '${AppRoutes.dispatch}?lane=plan',
        actionKind: TaskActionKind.openQueue,
        actionLabel: 'Sevkiyatı planla',
        count: toPlan,
      ),
    );
  }
  if (ship != null && canPlan && ship.unassignedDriver > 0) {
    items.add(
      TaskItem(
        id: 'drivers',
        kind: TaskKind.assignDriver,
        title: 'Şoför bekleyen ${ship.unassignedDriver} sevkiyat',
        route: '${AppRoutes.dispatch}?lane=driver',
        actionKind: TaskActionKind.openQueue,
        actionLabel: 'Şoför ata',
        count: ship.unassignedDriver,
      ),
    );
  }
  if (ship != null && canResolve && ship.disputes > 0) {
    items.add(
      TaskItem(
        id: 'disputes',
        kind: TaskKind.disputes,
        title: 'İtiraz edilen ${ship.disputes} teslimat',
        tone: TaskTone.danger,
        route: '${AppRoutes.dispatch}?lane=disputed',
        actionKind: TaskActionKind.openQueue,
        actionLabel: 'İtirazları incele',
        count: ship.disputes,
        overdue: ship.disputes,
      ),
    );
  }

  final money = data.collections;
  if (money != null && money.overdueCount > 0) {
    items.add(
      TaskItem(
        id: 'overdue-payments',
        kind: TaskKind.overduePayments,
        title: 'Vadesi geçen ${money.overdueCount} ödeme',
        amount: Fmt.moneyWhole(money.overdueAmount),
        tone: TaskTone.danger,
        route: '${AppRoutes.payments}?filter=overdue',
        actionKind: TaskActionKind.openQueue,
        actionLabel: 'Tahsilatı aç',
        count: money.overdueCount,
        overdue: money.overdueCount,
      ),
    );
  }
  if (money != null && money.documentsAwaitingCheck > 0) {
    items.add(
      TaskItem(
        id: 'documents',
        kind: TaskKind.documentsToCheck,
        title: 'Kontrol bekleyen ${money.documentsAwaitingCheck} belge',
        subtitle: 'Dekont, çek ve senet görselleri',
        route: '${AppRoutes.payments}?filter=documents',
        actionKind: TaskActionKind.openQueue,
        actionLabel: 'Belgeleri incele',
        count: money.documentsAwaitingCheck,
      ),
    );
  }
  final fin = data.finance;
  if (fin != null && fin.reviewOverdue > 0) {
    items.add(
      TaskItem(
        id: 'reviews',
        kind: TaskKind.financeReviews,
        title: 'Gözden geçirilecek ${fin.reviewOverdue} cari',
        subtitle: 'Finans kartı',
        tone: TaskTone.warn,
        route: '${AppRoutes.finance}?filter=review',
        actionKind: TaskActionKind.openQueue,
        actionLabel: 'Carileri aç',
        count: fin.reviewOverdue,
      ),
    );
  }
  if (data.setup?.tuprasMissingToday ?? false) {
    items.add(
      const TaskItem(
        id: 'tupras-today',
        kind: TaskKind.tuprasToday,
        title: 'Bugünün Tüpraş fiyatını girin',
        tone: TaskTone.warn,
        route: AppRoutes.home,
        focus: 'tupras',
        actionKind: TaskActionKind.enterPrices,
        // The price is entered on the web portal: the label and the ↗ say
        // so before the browser opens (v4 B15).
        actionLabel: 'Portalda girin',
        external: true,
      ),
    );
  }
  final field = data.field;
  if (field != null && field.rejected > 0) {
    items.add(
      TaskItem(
        id: 'field-rejected',
        kind: TaskKind.fieldForms,
        title: 'Düzeltilecek ${field.rejected} form',
        tone: TaskTone.warn,
        route: '${AppRoutes.field}?segment=rejected',
        actionKind: TaskActionKind.openQueue,
        actionLabel: 'Formları aç',
        count: field.rejected,
      ),
    );
  }
  final sorted = sortTasks(items, now: at);
  if (field != null && field.drafts > 0) {
    sorted.add(
      TaskItem(
        id: 'field-drafts',
        kind: TaskKind.fieldForms,
        title: 'Taslak ${field.drafts} form',
        tone: TaskTone.neutral,
        route: '${AppRoutes.field}?segment=drafts',
        actionKind: TaskActionKind.openQueue,
        actionLabel: 'Taslakları aç',
        counts: false,
        count: field.drafts,
      ),
    );
  }
  return sorted;
}

/// The possessive suffix after a numeral, by how the number is read:
/// 1'i, 2'si, 3'ü, 4'ü, 5'i, 6'sı, 7'si, 8'i, 9'u, 10'u, 20'si, 40'ı,
/// 100'ü, 1000'i.
String _si(int n) {
  final v = n.abs();
  final ones = v % 10;
  if (ones != 0) {
    return const ['', 'i', 'si', 'ü', 'ü', 'i', 'sı', 'si', 'i', 'u'][ones];
  }
  final tens = (v ~/ 10) % 10;
  if (tens != 0) {
    return const ['', 'u', 'si', 'u', 'ı', 'si', 'ı', 'i', 'i', 'ı'][tens];
  }
  if ((v ~/ 100) % 10 != 0) return 'ü';
  return 'i';
}

/// The Turkish possessive suffix after a numeral (tests and band status
/// lines): "2'si gecikti".
String numeralPossessive(int n) => "$n'${_si(n)}";

// ─────────────────────────────── Merkez ───────────────────────────────

/// Merkez's tasks (v4 §3.3): the approvals that wait (= the badge).
final platformTasksProvider = Provider.autoDispose<TaskInbox>((ref) {
  final policy = ref.watch(accessPolicyProvider);
  if (!policy.isPlatform) return TaskInbox.empty;
  final badge = ref.watch(unreadCountProvider.select((u) => u.approvals));
  return TaskInbox(
    items: [
      if (badge > 0)
        TaskItem(
          id: 'approvals',
          kind: TaskKind.platformApprovals,
          // A plain sentence that names the count (v4 B16), like the bayi's
          // "Kararınızı bekleyen 9 talep".
          title: 'Onayınızı bekleyen $badge talep',
          subtitle: 'Bayilerden üst onaya gelen talepler',
          route: AppRoutes.approvals,
          actionKind: TaskActionKind.openQueue,
          actionLabel: 'Talepleri incele',
          count: badge,
        ),
    ],
  );
});

// ─────────────────────────────── Any ───────────────────────────────

/// The signed-in viewer's inbox (customer, bayi or Merkez).
final taskInboxProvider = Provider.autoDispose<TaskInbox>((ref) {
  final policy = ref.watch(accessPolicyProvider);
  ref.watch(currentUserIdProvider);
  if (policy.isCustomer) return ref.watch(customerTasksProvider);
  if (policy.isPlatform) return ref.watch(platformTasksProvider);
  if (policy.isBayi && !policy.isDriverOnly) {
    return ref.watch(bayiTaskQueuesProvider);
  }
  return TaskInbox.empty;
});

/// The one number of the viewer's inbox (customer: hero = badge = Bende).
final taskCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(taskInboxProvider).count,
);

/// The pages whose entity waits on the viewer (v4 §3.5, §5 10), as paths:
/// the inbox's counting tasks, the bayi's orders that wait for a quote (the
/// desk's lists) and, for approvers, the requests in Bende (page 1). A
/// notification about one of them keeps its action line after it is read —
/// the action line says the move is still the viewer's, not that the
/// notification is new.
final taskWaitingPathsProvider = Provider.autoDispose<Set<String>>((ref) {
  final policy = ref.watch(accessPolicyProvider);
  final inbox = ref.watch(taskInboxProvider);
  final paths = <String>{
    for (final t in inbox.items)
      if (t.counts) taskPath(t.route),
  };
  if (policy.isBayi && !policy.isDriverOnly) {
    if (policy.quotesOrders) {
      final desk = ref.watch(bayiHomeProvider.select((s) => s.data?.desk));
      for (final o in [...?desk?.expiring, ...?desk?.awaitingQuoteList]) {
        if (o.status == OrderStatus.awaitingQuote ||
            o.status == OrderStatus.revisionRequested) {
          paths.add(AppRoutes.bayiOrder(o.orderId));
        }
      }
    }
    if (policy.isApprover && policy.can(Pg.stationApprovals)) {
      final bende = ref.watch(approvalsListProvider(const ApprovalsQuery()));
      for (final a in bende.items) {
        paths.add(AppRoutes.approval(a.id));
      }
    }
  }
  if (policy.isPlatform) {
    final bende = ref.watch(approvalsListProvider(const ApprovalsQuery()));
    for (final a in bende.items) {
      paths.add(AppRoutes.approval(a.id));
    }
  }
  return paths;
});
