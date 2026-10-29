import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'animated_number.dart';
import 'buttons.dart';
import 'cards.dart' show OnHero;
import 'rolling_figure.dart';
import 'status_widgets.dart';

/// How a task reads (design v4 §4): the viewer's move (Pas), something
/// blocking or overdue (danger), a setup gap (warn), or a neutral reminder
/// (a draft).
enum AknTaskTone { yourMove, danger, warn, neutral }

/// One thing that waits for the viewer — the UI data of the "Sıra sizde"
/// card and of Onaylar › Bende (v4 §3.4). The app's task inbox builds these;
/// the screen that shows them supplies the actions.
@immutable
class AknTask {
  const AknTask({
    required this.id,
    required this.title,
    this.subtitle,
    this.icon = PhosphorIconsRegular.circleDashed,
    this.tone = AknTaskTone.yourMove,
    this.figure,
    this.amount,
    this.deadline,
    this.time,
    this.actionLabel,
    this.onAction,
    this.onActionAsync,
    this.caption,
    this.note,
    this.onTap,
    this.counts = true,
    this.semanticLabel,
  });

  /// Stable id (folds and pops follow it).
  final Object id;

  /// The imperative ("Teklifi onaylayın") or the queue ("Kararınızı
  /// bekleyen 9 talep · 2'si gecikti").
  final String title;

  /// "bayi · ürün litre · yer".
  final String? subtitle;
  final IconData icon;
  final AknTaskTone tone;

  /// The lead's figure ("338.800,00 ₺"), amountLarge 28/34; it rolls once
  /// per session.
  final String? figure;

  /// A row's amount on the right (15/20 700).
  final String? amount;

  /// The countdown's deadline (a [CountdownBadge] on the viewer's move).
  final DateTime? deadline;

  /// A time instead of a countdown ("bugün 17:17").
  final String? time;

  /// The lead's one primary ("Çek görselini yükle", "Teklif ver").
  final String? actionLabel;
  final VoidCallback? onAction;
  final Future<void> Function()? onActionAsync;

  /// Under the primary (13/18 dim): "Yükledikten sonra onaylayabilirsiniz".
  final String? caption;

  /// A row note with a warn dot ("Önce çek görselini yükleyin").
  final String? note;

  /// Opens the task's page (rows, and the lead's title).
  final VoidCallback? onTap;

  /// False for reminders that do not count (the draft).
  final bool counts;
  final String? semanticLabel;

  bool get hasAction =>
      actionLabel != null && (onAction != null || onActionAsync != null);
}

/// "Sıra sizde", the hero of every home (design v4 §4, §3.3): the child of
/// `AknBandOverlap`, on the plate (`plateDecoration(raised: true)`, r26),
/// padding 20/16/20/12.
///
/// * Header (min 40): "Sıra sizde" 17/22 700 with the [total] in a soft Pas
///   pill that pops (and counts) when it changes. Bayi: the [legend] "●
///   sizin sıranız" on the right, then the [overview] (the pipeline) over a
///   hairline.
/// * The lead task ([tasks] first): a 40 dp r12 tile (brandSoft + Pas glyph,
///   danger for overdue or blocking, warn for setup) whose halo breathes —
///   the home's one focus loop; the title 15/20 700 with the countdown (or
///   time) on the right; the subline 14/20 dim; the [AknTask.figure] in
///   amountLarge 28/34 (rolls once per session); THE one primary (medium
///   48, full width) and an optional caption.
/// * At most [maxRows] more rows ([AknTaskRow], hairlines inset 52), then
///   "Tümünü gör (n) ›" when [total] exceeds the tasks shown ([onSeeAll]).
/// * Calm (no tasks): one 64 dp row — ok tile, "Bekleyen işiniz yok", the
///   role sentence ([calm]).
/// * Motion (§6): rows stagger in 55 ms apart, the pill pops, the figure
///   rolls; a finished task stamps its check, folds away and the next one
///   slides up 12 dp; after the last one the card fades through to calm.
/// * Screen readers: the header reads "Sıra sizde, 3 iş"; every row is one
///   button. The card reflows at 2.0× text with nothing cut.
class AknTaskCard extends StatefulWidget {
  const AknTaskCard({
    super.key,
    required this.tasks,
    this.total,
    this.overview,
    this.legend = false,
    this.onSeeAll,
    this.calm,
    this.title = 'Sıra sizde',
    this.calmTitle = 'Bekleyen işiniz yok',
    this.maxRows = 2,
    this.showCount = true,
  });

  /// In the inbox's order; the first is the lead.
  final List<AknTask> tasks;

  /// The count in the pill (= the Onaylar badge = Bende); defaults to the
  /// counting tasks.
  final int? total;

  /// Bayi: the pipeline, under the header. With it the header shows no
  /// count pill (the pipeline and the queue rows carry the numbers, so the
  /// card never shows a second, different number) and the footer reads
  /// "Tüm işler ›".
  final Widget? overview;

  /// False: no count pill in the header and no number in the footer (queue
  /// cards, whose rows each carry their own count).
  final bool showCount;

  /// Bayi: "● sizin sıranız" on the right of the header.
  final bool legend;
  final VoidCallback? onSeeAll;

  /// The calm row's role sentence ("Yeni sipariş için + tuşuna dokunun.").
  final String? calm;
  final String title;
  final String calmTitle;

  /// Rows under the lead (2).
  final int maxRows;

  /// The count the card shows for [tasks] and [total].
  static int countOf(List<AknTask> tasks, int? total) =>
      total ?? tasks.where((t) => t.counts).length;

  @override
  State<AknTaskCard> createState() => _AknTaskCardState();
}

class _AknTaskCardState extends State<AknTaskCard> {
  /// Tasks that left the card and are folding away, by id: their old slot
  /// and the task as last shown.
  final Map<Object, (int, AknTask)> _leaving = {};

  List<AknTask> _visible(AknTaskCard w) =>
      w.tasks.take(1 + w.maxRows).toList(growable: false);

  @override
  void didUpdateWidget(AknTaskCard old) {
    super.didUpdateWidget(old);
    final now = {for (final t in widget.tasks) t.id};
    final before = _visible(old);
    for (var i = 0; i < before.length; i++) {
      final t = before[i];
      if (!now.contains(t.id) && !_leaving.containsKey(t.id)) {
        _leaving[t.id] = (i, t);
      }
    }
    _leaving.removeWhere((id, _) => now.contains(id));
  }

  void _folded(Object id) {
    if (!mounted) return;
    setState(() => _leaving.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final w = widget;
    final visible = _visible(w);
    final count = AknTaskCard.countOf(w.tasks, w.total);
    final numbered = w.showCount && w.overview == null;
    final calm = visible.isEmpty && _leaving.isEmpty;

    // Slots: the visible tasks, with the leaving ones kept in their old
    // place while they fold (a leaving lead keeps the lead's look).
    final slots = <(AknTask, bool, int)>[
      for (var i = 0; i < visible.length; i++) (visible[i], false, i),
    ];
    final leaving = _leaving.entries.toList()
      ..sort((a, b) => a.value.$1.compareTo(b.value.$1));
    for (final e in leaving) {
      final at = math.min(e.value.$1, slots.length);
      slots.insert(at, (e.value.$2, true, e.value.$1));
    }

    final children = <Widget>[];
    var liveLead = false;
    var row = 0;
    for (final (task, done, oldIndex) in slots) {
      final lead = done ? oldIndex == 0 : !liveLead;
      if (!done && lead) liveLead = true;
      if (lead) {
        children.add(
          AknTaskFold(
            key: ValueKey(('lead', task.id)),
            done: done,
            onFolded: () => _folded(task.id),
            child: StaggerItem(
              index: 0,
              // The next lead slides up 12 dp into place.
              child: FadeUp(
                offset: 12,
                child: _LeadTask(task: task, done: done),
              ),
            ),
          ),
        );
        continue;
      }
      row++;
      children.add(
        AknTaskFold(
          key: ValueKey(('row', task.id)),
          done: done,
          onFolded: () => _folded(task.id),
          child: StaggerItem(
            index: row,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Hairline(indent: 52),
                AknTaskRow(task: task, done: done, onCard: true),
              ],
            ),
          ),
        ),
      );
    }
    final shown = visible.length;
    final more =
        (numbered ? count > shown : w.tasks.length > shown) &&
        w.onSeeAll != null;

    final header = _Header(
      title: w.title,
      count: numbered ? count : 0,
      legend: w.legend,
    );
    final body = calm
        ? Column(
            key: const ValueKey('calm'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (w.overview != null) ...[
                header,
                const SizedBox(height: 10),
                w.overview!,
                const SizedBox(height: 12),
                const _Hairline(),
              ],
              _CalmRow(title: w.calmTitle, sentence: w.calm),
            ],
          )
        : Column(
            key: const ValueKey('tasks'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (w.overview != null) ...[
                const SizedBox(height: 10),
                w.overview!,
                const SizedBox(height: 12),
                const _Hairline(),
              ],
              const SizedBox(height: 12),
              ...children,
              if (more) ...[
                const _Hairline(),
                _SeeAll(count: numbered ? count : null, onTap: w.onSeeAll!),
              ] else
                const SizedBox(height: 4),
            ],
          );
    return DecoratedBox(
      decoration: c.plateDecoration(raised: true),
      child: ClipRRect(
        borderRadius: AknRadius.plate,
        child: Material(
          type: MaterialType.transparency,
          // The row tiles and the press fill keep the page's neutral well
          // (read here, before the plate palette maps it to the warm
          // `deltaFill`), so the hero's rows look like Bende's and only the
          // lead tile is orange (§4; no brown slabs at night).
          child: _TaskWell(
            color: c.surfaceAlt,
            child: OnHero(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  calm ? 12 : 16,
                  20,
                  calm ? 12 : 8,
                ),
                child: StaggerScope(
                  child: FadeThroughSwitcher(
                    duration: AknMotion.slow,
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The neutral well of the page under the hero card (its tiles and press
/// fill); absent outside the card.
class _TaskWell extends InheritedWidget {
  const _TaskWell({required this.color, required super.child});

  final Color color;

  /// The well for task tiles at [context]: the page's when inside the
  /// card, else the palette's own `surfaceAlt`.
  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TaskWell>()?.color ??
      context.akn.surfaceAlt;

  @override
  bool updateShouldNotify(_TaskWell old) => old.color != color;
}

/// The header: "Sıra sizde" + the count pill (+ the bayi legend).
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.count,
    required this.legend,
  });

  final String title;
  final int count;
  final bool legend;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          // The title takes the row, so the legend sits on the right (§4).
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                header: true,
                label: count > 0 ? '$title, $count iş' : title,
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        textScaler: scaler,
                        style: t.headline.copyWith(
                          fontSize: 17,
                          height: 22 / 17,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 8),
                      _CountPill(count: count, textScaler: scaler),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (legend) ...[
            const SizedBox(width: 12),
            ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.brandFill,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'sizin sıranız',
                    textScaler: scaler,
                    style: t.caption.copyWith(color: c.dim),
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

/// The count pill: min 24, `brandSoft`, Pas 12/16 800 tabular; it pops and
/// counts when the number changes.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.textScaler});

  final int count;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.captionStrong.copyWith(
      color: c.brandInk,
      fontWeight: FontWeight.w800,
      fontFeatures: AknNumerals.tabular,
    );
    return TweenAnimationBuilder<double>(
      key: ValueKey(count),
      tween: Tween<double>(begin: 0.7, end: 1),
      duration: AknMotion.of(context, const Duration(milliseconds: 360)),
      curve: AknMotion.pop,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.brandSoft,
          borderRadius: AknRadius.pillAll,
        ),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: AnimatedNumber(
            value: count,
            from: count,
            style: style,
            semanticsLabel: '$count',
          ),
        ),
      ),
    );
  }
}

/// The lead task block.
class _LeadTask extends StatelessWidget {
  const _LeadTask({required this.task, required this.done});

  final AknTask task;
  final bool done;

  /// Figures that already rolled this session (rolls once per session).
  static final Set<Object> _rolled = <Object>{};

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    // Inline beside the title the countdown is compact ("⏱ 2 sa 59 dk", §5
    // wireframes), so the title keeps room on 360 dp phones; on its own line
    // (text ≥ 1.3×) it reads "… kaldı".
    final right = _TaskTime.of(task, compact: !large);
    final title = Text(
      task.title,
      maxLines: large ? null : 2,
      overflow: large ? null : TextOverflow.ellipsis,
      style: t.bodyStrong.copyWith(
        height: 20 / 15,
        fontWeight: FontWeight.w700,
        color: c.ink,
      ),
    );
    final sub = task.subtitle;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (large || right == null)
          title
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 10),
              right,
            ],
          ),
        if (large && right != null) ...[
          const SizedBox(height: 4),
          Align(alignment: AlignmentDirectional.centerStart, child: right),
        ],
        if (sub != null && sub.isNotEmpty) ...[
          const SizedBox(height: 2),
          // Facts stay whole: the line breaks only after a "·" ("Demir
          // Petrol · Motorin 8.000 L ·" / "Tuzla Şantiye").
          Text(
            _unbroken(sub),
            semanticsLabel: sub,
            style: t.bodySmall.copyWith(color: c.dim),
          ),
        ],
      ],
    );
    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TaskTile(task: task, size: 40, done: done, halo: !done),
        const SizedBox(width: 12),
        Expanded(child: texts),
      ],
    );
    final open = task.onTap;
    final figure = task.figure;
    final firstRoll = figure != null && _rolled.add(('lead', task.id, figure));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (open == null)
          head
        else
          Semantics(
            button: true,
            label: task.semanticLabel ?? _spoken(task),
            excludeSemantics: true,
            onTap: open,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AknHaptics.selection();
                open();
              },
              child: head,
            ),
          ),
        if (figure != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 52),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: RollingText(
                TextSpan(
                  text: figure,
                  style: t.amountLarge.copyWith(color: c.ink),
                ),
                animate: firstRoll,
                delay: const Duration(milliseconds: 260),
              ),
            ),
          ),
        ],
        if (task.hasAction) ...[
          const SizedBox(height: 12),
          AknButton(
            label: task.actionLabel!,
            onPressed: task.onAction,
            onPressedAsync: task.onAction == null ? task.onActionAsync : null,
            size: AknButtonSize.medium,
            expand: true,
            celebrate: true,
          ),
          if (task.caption != null && task.caption!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              task.caption!,
              textAlign: TextAlign.center,
              style: t.label.copyWith(
                fontWeight: FontWeight.w500,
                color: c.dim,
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

/// A " · " line whose short facts do not break inside: their spaces and the
/// space before each "·" become no-break spaces. A plain sentence (one
/// fact) and long facts wrap as usual.
String _unbroken(String line) {
  final facts = line.split(' · ');
  if (facts.length < 2) return line;
  return facts
      .map((f) {
        final t = f.trim();
        return t.length <= 24 ? t.replaceAll(' ', ' ') : t;
      })
      .join(' · ');
}

/// "Teklifi onaylayın, Demir Petrol · Motorin 8.000 L, 338.800,00 ₺".
String _spoken(AknTask t) => [
  t.title,
  if (t.subtitle != null && t.subtitle!.isNotEmpty) t.subtitle!,
  if (t.figure != null) t.figure!,
  if (t.amount != null) t.amount!,
  if (t.time != null) t.time!,
  if (t.note != null) t.note!,
].join(', ');

/// The countdown (on the viewer's move) or the time of a task.
class _TaskTime extends StatelessWidget {
  const _TaskTime({required this.task, required this.compact});

  final AknTask task;
  final bool compact;

  static Widget? of(AknTask task, {required bool compact}) {
    if (task.deadline == null && (task.time == null || task.time!.isEmpty)) {
      return null;
    }
    return _TaskTime(task: task, compact: compact);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final d = task.deadline;
    if (d != null) {
      return CountdownBadge(
        deadline: d,
        yourMove: task.tone == AknTaskTone.yourMove,
        compact: compact,
        subject: 'Süre',
      );
    }
    return Text(
      task.time!,
      style: (compact ? t.label : t.bodySmall).copyWith(
        fontWeight: FontWeight.w500,
        color: task.tone == AknTaskTone.danger ? c.danger.fg : c.dim,
        fontFeatures: AknNumerals.tabular,
      ),
    );
  }
}

/// A task row (design v4 §4): ≥ 56 dp, a 36 dp neutral tile (danger
/// tinted), the title 15/20 600 (one line; wraps at large text), the
/// subline 13/18 dim, an optional [AknTask.note] with a warn dot; on the
/// right the amount (15/20 700) over the countdown or time, then a 16 dp
/// caret. Press: 0.985 + a `surfaceAlt` fill. One button node. Used by the
/// "Sıra sizde" card and by Onaylar › Bende (in a ledger).
class AknTaskRow extends StatefulWidget {
  const AknTaskRow({
    super.key,
    required this.task,
    this.done = false,
    this.onCard = false,
    this.padding,
  });

  final AknTask task;

  /// The task is done: the tile stamps its check (the fold is the
  /// parent's).
  final bool done;

  /// Inside the "Sıra sizde" card (no side padding of its own).
  final bool onCard;
  final EdgeInsetsGeometry? padding;

  @override
  State<AknTaskRow> createState() => _AknTaskRowState();
}

class _AknTaskRowState extends State<AknTaskRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final task = widget.task;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final reduced = AknMotion.reduced(context);
    final time = _TaskTime.of(task, compact: true);
    final amount = task.amount;
    final right = <Widget>[
      if (amount != null)
        Text(
          amount,
          maxLines: 1,
          softWrap: false,
          style: t.bodyStrong.copyWith(
            height: 20 / 15,
            fontWeight: FontWeight.w700,
            color: c.ink,
            fontFeatures: AknNumerals.tabular,
          ),
        ),
      ?time,
    ];
    final note = task.note;
    final noteLine = note == null || note.isEmpty
        ? null
        : Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: c.warn.solid,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(note, style: t.label.copyWith(color: c.ink)),
              ),
            ],
          );
    // On the card a row keeps one line each (the card stays short); in a
    // ledger (Bende) the title and the subline may take two lines, so the
    // verb and the numbers are never cut — but a row stays within three
    // lines (§9 08b): with a note under it, the subline keeps one. A
    // subline that does not fit drops its trailing facts whole ("Motorin
    // 12.000 L · Pendik…" → "Motorin 12.000 L").
    final titleLines = large ? null : (widget.onCard ? 1 : 2);
    final subLines = large ? null : (widget.onCard || noteLine != null ? 1 : 2);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          task.title,
          maxLines: titleLines,
          overflow: large ? null : TextOverflow.ellipsis,
          style: t.bodyStrong.copyWith(height: 20 / 15, color: c.ink),
        ),
        if (task.subtitle != null && task.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          AknFactLine(
            task.subtitle!,
            maxLines: subLines,
            style: t.label.copyWith(fontWeight: FontWeight.w400, color: c.dim),
          ),
        ],
        if (large && noteLine != null) ...[const SizedBox(height: 4), noteLine],
        if (large && right.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 12, runSpacing: 2, children: right),
        ],
      ],
    );
    final content = Row(
      children: [
        Expanded(child: texts),
        if (!large && right.isNotEmpty) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: right,
          ),
        ],
      ],
    );
    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _TaskTile(task: task, size: 36, done: widget.done, halo: false),
        const SizedBox(width: 16),
        Expanded(child: content),
        if (task.onTap != null) ...[
          const SizedBox(width: 6),
          Icon(PhosphorIconsRegular.caretRight, size: 16, color: c.dim),
        ],
      ],
    );
    // The note runs under the whole row (from the text's start to the
    // caret), so it stays on one line and the row keeps 3 lines (§9 08b).
    if (!large && noteLine != null) {
      row = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 52),
            child: noteLine,
          ),
        ],
      );
    }
    final pad =
        widget.padding ??
        (widget.onCard
            ? const EdgeInsets.symmetric(vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 10));
    final interactive = task.onTap != null;
    final well = _TaskWell.of(context);
    Widget body = AnimatedContainer(
      duration: AknMotion.of(
        context,
        _pressed ? AknMotion.press : AknMotion.pressOut,
      ),
      curve: AknMotion.standard,
      constraints: const BoxConstraints(minHeight: 56),
      padding: pad,
      decoration: BoxDecoration(
        color: _pressed ? well : well.withValues(alpha: 0),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: row,
    );
    if (interactive) {
      body = AnimatedScale(
        scale: _pressed && !reduced ? 0.985 : 1,
        duration: _pressed ? AknMotion.press : AknMotion.pressOut,
        curve: _pressed ? AknMotion.standard : AknMotion.spring,
        child: Listener(
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AknHaptics.selection();
              task.onTap!();
            },
            child: body,
          ),
        ),
      );
    }
    return Semantics(
      button: interactive,
      label: task.semanticLabel ?? _spoken(task),
      excludeSemantics: true,
      onTap: task.onTap,
      child: body,
    );
  }
}

/// A " · "-separated line of facts ("Motorin 12.000 L · Pendik Lojistik
/// Merkezi") that keeps every fact it shows whole: when the line does not fit
/// in [maxLines], its trailing facts are dropped ("Motorin 12.000 L")
/// instead of cutting one mid-word; only a first fact that is too long on
/// its own ends in "…". [maxLines] null: the line wraps freely.
class AknFactLine extends StatelessWidget {
  const AknFactLine(this.text, {super.key, required this.style, this.maxLines});

  final String text;
  final TextStyle style;
  final int? maxLines;

  static const String _sep = ' · ';

  @override
  Widget build(BuildContext context) {
    final lines = maxLines;
    final facts = text.split(_sep);
    if (lines == null) return Text(text, style: style);
    if (facts.length == 1) {
      return Text(
        text,
        style: style,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final full = DefaultTextStyle.of(context).style.merge(style);
        var shown = facts.first;
        for (var n = facts.length; n >= 1; n--) {
          final candidate = facts.take(n).join(_sep);
          final painter = TextPainter(
            text: TextSpan(text: candidate, style: full),
            textDirection: direction,
            textScaler: scaler,
            maxLines: lines,
          )..layout(maxWidth: constraints.maxWidth);
          final fits = !painter.didExceedMaxLines;
          painter.dispose();
          if (fits) {
            shown = candidate;
            break;
          }
        }
        return Text(
          shown,
          style: style,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          semanticsLabel: text,
        );
      },
    );
  }
}

/// A task's tile: the lead's 40 dp r12 (brandSoft + Pas glyph; danger for
/// overdue or blocking; warn for setup) with the breathing halo — the
/// home's focus loop — or a row's 36 dp neutral tile (danger tinted). A
/// done task stamps an ok check (1.06 → 1).
class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.size,
    required this.done,
    required this.halo,
  });

  final AknTask task;
  final double size;
  final bool done;
  final bool halo;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final lead = size >= 40;
    final ToneColors? tone = switch (task.tone) {
      AknTaskTone.danger => c.danger,
      AknTaskTone.warn => lead ? c.warn : null,
      _ => null,
    };
    final yourMove = lead && task.tone == AknTaskTone.yourMove;
    final fill = done
        ? c.ok.bg
        : tone?.bg ?? (yourMove ? c.brandSoft : _TaskWell.of(context));
    final ink = done ? c.ok.fg : tone?.fg ?? (yourMove ? c.brandInk : c.ink);
    final glyph = Icon(
      done ? PhosphorIconsBold.check : task.icon,
      size: lead ? 22 : 20,
      color: ink,
    );
    Widget tile = AnimatedContainer(
      duration: AknMotion.of(context, AknMotion.taskStamp),
      curve: AknMotion.standard,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: done
          ? TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 1.25, end: 1),
              duration: AknMotion.of(context, AknMotion.taskStamp),
              curve: AknMotion.pop,
              builder: (context, s, child) =>
                  Transform.scale(scale: s, child: child),
              child: glyph,
            )
          : glyph,
    );
    if (halo && yourMove) {
      // The home's one focus loop: the lead tile's halo breathes.
      tile = AknAmbient(
        period: AknMotion.breathe,
        reverse: true,
        role: AknAmbientRole.focus,
        child: tile,
        builder: (context, b, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: b <= 0
                ? null
                : [
                    BoxShadow(
                      color: c.brandFill.withValues(alpha: 0.22 * b),
                      blurRadius: 10 + 8 * b,
                      spreadRadius: 1 + 2 * b,
                    ),
                  ],
          ),
          child: child,
        ),
      );
    }
    return ExcludeSemantics(child: tile);
  }
}

/// The calm row: an ok tile, "Bekleyen işiniz yok" and the role sentence.
class _CalmRow extends StatelessWidget {
  const _CalmRow({required this.title, required this.sentence});

  final String title;
  final String? sentence;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final s = sentence;
    return Semantics(
      container: true,
      label: [title, ?s].join('. '),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.ok.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(PhosphorIconsBold.check, size: 20, color: c.ok.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: t.bodyStrong.copyWith(height: 20 / 15, color: c.ink),
                  ),
                  if (s != null && s.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      s,
                      style: t.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: c.dim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Tümünü gör (n) ›" (14/20 600 ink), a 48 dp target; "Tüm işler ›" on a
/// queue card (no [count]: its rows carry the numbers).
class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.count, required this.onTap});

  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = count;
    final label = n == null ? 'Tüm işler' : 'Tümünü gör ($n)';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AknHaptics.selection();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: t.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              Icon(PhosphorIconsRegular.caretRight, size: 16, color: c.ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plate hairline, inset [indent] from the start.
class _Hairline extends StatelessWidget {
  const _Hairline({this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: indent),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: context.akn.plateLine),
    ),
  );
}

/// The first-run hint (design v4 §4): replaces the first-order tip, the role
/// tip and the assistant card on the homes, first session only. A white r20
/// card with a hairline, "Nasıl çalışır", three [steps] on 24 dp `brandSoft`
/// discs, the closing line "Sizi bekleyen her iş en üstte, Sıra sizde
/// kartında." and the actions: a small primary ([primaryLabel], e.g. "İlk
/// siparişinizi verin" for users with no orders) and the ghost "Anladım"
/// ([onDismiss]). The caller keeps one prefs key per user.
class AknFirstRunHint extends StatelessWidget {
  const AknFirstRunHint({
    super.key,
    required this.steps,
    required this.onDismiss,
    this.primaryLabel,
    this.onPrimary,
    this.title = 'Nasıl çalışır',
    this.footer = 'Sizi bekleyen her iş en üstte, Sıra sizde kartında.',
    this.margin = const EdgeInsets.fromLTRB(20, 16, 20, 0),
  });

  /// The customer's three steps.
  static const customerSteps = [
    'Sipariş ver tuşuyla ürünü, miktarı ve teslim yerini seçin.',
    'Bayiniz teklif gönderir; uygunsa onaylayın.',
    'Aracı yolda izleyin, teslim alınca onaylayın.',
  ];

  /// The bayi's three steps.
  static const bayiSteps = [
    'Yeni siparişlere Teklifler sekmesinden fiyat verin.',
    'Müşteri onaylayınca sevkiyatı planlayın.',
    'Kararınızı bekleyen talepler Onaylar sekmesinde.',
  ];

  /// The field rep's three steps.
  static const fieldSteps = [
    'Ziyaretten sonra Yeni form ile siparişi yazın.',
    'Formu gönderin; yöneticiniz onaylar.',
    'Sonucu Saha sekmesinden izleyin.',
  ];

  final List<String> steps;
  final VoidCallback onDismiss;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String title;
  final String footer;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AknRadius.card,
          border: c.isDark ? Border.all(color: c.line) : null,
          boxShadow: c.isDark ? null : [AknShadows.hairline(c)],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: t.headline.copyWith(color: c.ink)),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.brandSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          textScaler: TextScaler.noScaling,
                          style: t.captionStrong.copyWith(
                            color: c.brandInk,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            steps[i],
                            style: t.bodySmall.copyWith(color: c.ink),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                footer,
                style: t.label.copyWith(
                  fontWeight: FontWeight.w500,
                  color: c.dim,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (primaryLabel != null && onPrimary != null)
                    AknButton(
                      label: primaryLabel!,
                      size: AknButtonSize.small,
                      onPressed: onPrimary,
                    ),
                  AknButton.ghost(
                    label: 'Anladım',
                    size: AknButtonSize.small,
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
