import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';
import '../../data/approval_models.dart';
import '../../shared/layout.dart';

/// Onay adımları (bayi / merkez görünümü; tasarım v3 §4–5): beyaz kartta zaman çizelgesi — kademe,
/// durum, "X adına Y", not, son tarih. Çizelge ilk görünüşte yukarıdan aşağı kendini çizer; sıra
/// izleyicideyse güncel düğüm turuncudur ve nefes alır.
class ApprovalStepsTimeline extends StatelessWidget {
  const ApprovalStepsTimeline({super.key, required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final multi = detail.steps.length > 1;
    final yourMove =
        detail.row.canDecide && detail.row.status == ApprovalStatus.pending;
    return AknCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: StepTimeline(
        yourMove: yourMove,
        steps: adaptSteps(context, [
          for (final s in detail.steps)
            TimelineStep(
              title: multi ? '${s.levelNo}. kademe, ${s.name}' : s.name,
              subtitle: [s.displayStatusLabel, ?s.deciderText].join(', '),
              time: s.decidedAt != null
                  ? shortStamp(s.decidedAt)
                  : (s.dueAt != null && s.status == ApprovalStepStatus.pending
                        ? 'Son: ${shortStamp(s.dueAt)}'
                        : null),
              state: switch (s.status) {
                ApprovalStepStatus.approved => TimelineState.done,
                ApprovalStepStatus.pending => TimelineState.current,
                ApprovalStepStatus.rejected => TimelineState.failed,
                ApprovalStepStatus.escalated => TimelineState.warning,
                _ => TimelineState.upcoming,
              },
              content: s.note == null
                  ? null
                  : Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: context.akn.surfaceAlt,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AknRadius.md),
                        ),
                      ),
                      child: Text(
                        '“${s.note}”',
                        style: t.bodySmall.copyWith(color: context.akn.ink),
                      ),
                    ),
            ),
        ]),
      ),
    );
  }
}

/// Cari görünümünün sade süreci (web `CustomerTimeline` portu; v3: beyaz kartta kendini çizen
/// çizelge): talep, ek bilgi istek / yanıtları (yalnızca cariye yöneltilen türlerde), son durum.
/// Kademe, onaylayan adı ve SLA yoktur.
class CustomerProcessTimeline extends StatelessWidget {
  const CustomerProcessTimeline({super.key, required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context) {
    return AknCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: StepTimeline(steps: adaptSteps(context, customerSteps(detail))),
    );
  }

  static List<TimelineStep> customerSteps(ApprovalDetail d) {
    final steps = <TimelineStep>[
      TimelineStep(
        title: 'Talep oluşturuldu',
        subtitle: d.row.requestedByName,
        time: shortStamp(d.row.createdAt),
        state: TimelineState.done,
        icon: PhosphorIconsRegular.plus,
      ),
    ];
    if (d.isCustomerAddressed) {
      final info = d.events
          .where(
            (e) =>
                e.eventType == ApprovalEventType.infoRequested ||
                e.eventType == ApprovalEventType.infoProvided,
          )
          .toList();
      for (final e in info) {
        if (e.eventType == ApprovalEventType.infoRequested) {
          steps.add(
            TimelineStep(
              title: 'Ek bilgi istendi',
              time: shortStamp(e.occurredAt),
              state: TimelineState.done,
              icon: PhosphorIconsFill.chatCircleDots,
            ),
          );
        } else {
          final mine = e.userName != null;
          steps.add(
            TimelineStep(
              title: mine ? 'Yanıt verildi' : 'Bayi yanıt verdi',
              subtitle: mine ? e.userName : null,
              time: shortStamp(e.occurredAt),
              state: TimelineState.done,
              icon: PhosphorIconsRegular.arrowBendUpLeft,
            ),
          );
        }
      }
    }
    final finishedAt =
        d.decidedAt ?? (d.events.isEmpty ? null : d.events.last.occurredAt);
    switch (d.status) {
      case ApprovalStatus.pending:
        steps.add(
          TimelineStep(
            title: 'Bayi değerlendirmesi',
            subtitle: ApprovalsCopy.customerStatus(d),
            state: TimelineState.current,
            icon: PhosphorIconsRegular.hourglassHigh,
          ),
        );
      case ApprovalStatus.infoRequested:
        steps.add(
          TimelineStep(
            title: ApprovalsCopy.customerStatus(d),
            state: TimelineState.current,
            icon: PhosphorIconsFill.chatCircleDots,
          ),
        );
      case ApprovalStatus.approved:
        final conditional = d.isConditionallyApproved;
        steps.add(
          TimelineStep(
            title: conditional ? 'Koşullu onaylandı' : 'Onaylandı',
            subtitle: conditional
                ? ApprovalsCopy.conditionalText(d.type)
                : null,
            time: shortStamp(finishedAt),
            state: TimelineState.done,
            icon: PhosphorIconsRegular.check,
          ),
        );
      case ApprovalStatus.rejected:
        steps.add(
          TimelineStep(
            title: 'Reddedildi',
            subtitle: d.decisionNote,
            time: shortStamp(finishedAt),
            state: TimelineState.failed,
            icon: PhosphorIconsRegular.x,
          ),
        );
      default:
        steps.add(
          TimelineStep(
            title: 'Talep kapatıldı',
            time: shortStamp(finishedAt),
            state: TimelineState.upcoming,
            icon: PhosphorIconsRegular.prohibit,
          ),
        );
    }
    return steps;
  }
}

/// Olay günlüğü (bayi / merkez görünümü; tasarım v3): beyaz kartta son olaylar — her olayın simgesi
/// yumuşak dairede, satırlar arasında içeriden ince çizgi; "Tüm olaylar" ile yumuşakça genişler.
class ApprovalEventsLog extends StatefulWidget {
  const ApprovalEventsLog({super.key, required this.detail, this.onOpenFile});

  final ApprovalDetail detail;

  /// Olaydaki belgeye dokunulunca (belge ayrıntıdaysa açılır).
  final void Function(String publicId)? onOpenFile;

  @override
  State<ApprovalEventsLog> createState() => _ApprovalEventsLogState();
}

class _ApprovalEventsLogState extends State<ApprovalEventsLog> {
  bool _all = false;

  static IconData _icon(ApprovalEventType t) => switch (t) {
    ApprovalEventType.created => PhosphorIconsRegular.plusCircle,
    ApprovalEventType.viewed => PhosphorIconsRegular.eye,
    ApprovalEventType.attachmentViewed => PhosphorIconsRegular.paperclip,
    ApprovalEventType.approved ||
    ApprovalEventType.preApproved => PhosphorIconsRegular.checkCircle,
    ApprovalEventType.conditionallyApproved => PhosphorIconsRegular.listChecks,
    ApprovalEventType.rejected => PhosphorIconsRegular.xCircle,
    ApprovalEventType.infoRequested => PhosphorIconsRegular.chatCircleDots,
    ApprovalEventType.infoProvided => PhosphorIconsRegular.arrowBendUpLeft,
    ApprovalEventType.reminded => PhosphorIconsRegular.bellRinging,
    ApprovalEventType.escalated => PhosphorIconsRegular.trendUp,
    ApprovalEventType.delegated => PhosphorIconsRegular.shareNetwork,
    ApprovalEventType.cancelled => PhosphorIconsRegular.prohibit,
    ApprovalEventType.reopened => PhosphorIconsRegular.arrowCounterClockwise,
    ApprovalEventType.levelsUpdated => PhosphorIconsRegular.stack,
    ApprovalEventType.unknown => PhosphorIconsRegular.circle,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final events = widget.detail.events.reversed.toList();
    final shown = _all ? events : events.take(4).toList();
    return AknCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: AknAnimatedSize(
        alignment: Alignment.topCenter,
        duration: AknMotion.slow,
        curve: AknMotion.emphasizedCurve,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const AknLedgerDivider(indent: 0),
              _EventRow(
                event: shown[i],
                icon: _icon(shown[i].eventType),
                onOpenFile: widget.onOpenFile,
              ),
            ],
            if (events.length > 4)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AknInlineLink(
                    label: _all
                        ? 'Daha az göster'
                        : 'Tüm olaylar (${events.length})',
                    onTap: () => setState(() => _all = !_all),
                  ),
                ),
              ),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Henüz olay yok.',
                  style: t.bodySmall.copyWith(color: c.dim),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.icon, this.onOpenFile});

  final ApprovalEvent event;
  final IconData icon;
  final void Function(String publicId)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final e = event;
    final file = e.attachmentPublicId;
    final large = isLargeText(context);
    final when = TurkishText.lower(Fmt.relative(e.occurredAt));
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: c.ink),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    e.displayLabel,
                    style: t.bodyStrong.copyWith(color: c.ink),
                  ),
                ),
                if (large) Text(when, style: t.caption.copyWith(color: c.dim)),
                if (e.actorText != null)
                  Text(e.actorText!, style: t.bodySmall.copyWith(color: c.dim)),
                if (e.note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    TurkishText.commaList(e.note!),
                    style: t.bodySmall.copyWith(color: c.ink),
                  ),
                ],
                if (e.attachmentFileName != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsRegular.paperclip,
                        size: 14,
                        color: c.dim,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(e.attachmentFileName!, style: t.caption),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!large) ...[
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                when,
                style: t.caption.copyWith(
                  color: c.dim,
                  fontFeatures: AknNumerals.tabular,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final label = [
      e.displayLabel,
      ?e.actorText,
      ?e.note,
      ?e.attachmentFileName,
      Fmt.relative(e.occurredAt),
    ].join(', ');
    if (file != null && onOpenFile != null) {
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: () {
            AknHaptics.selection();
            onOpenFile!(file);
          },
          borderRadius: const BorderRadius.all(Radius.circular(AknRadius.md)),
          child: row,
        ),
      );
    }
    return Semantics(label: label, excludeSemantics: true, child: row);
  }
}
