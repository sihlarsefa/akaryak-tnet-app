import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/approval_models.dart';
import '../../shared/layout.dart';

/// Onay adımları (bayi / merkez görünümü): kademe, durum, "X adına Y", not, son tarih.
class ApprovalStepsTimeline extends StatelessWidget {
  const ApprovalStepsTimeline({super.key, required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final multi = detail.steps.length > 1;
    return AknCard(
      child: StepTimeline(
        steps: adaptSteps(context, [
          for (final s in detail.steps)
            TimelineStep(
              title: multi ? '${s.levelNo}. kademe · ${s.name}' : s.name,
              subtitle: [s.displayStatusLabel, ?s.deciderText].join(' · '),
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
                  : Text('“${s.note}”', style: t.bodySmall),
            ),
        ]),
      ),
    );
  }
}

/// Cari görünümünün sade süreci (web `CustomerTimeline` portu): talep, ek bilgi istek / yanıtları
/// (yalnızca cariye yöneltilen türlerde), son durum. Kademe, onaylayan adı ve SLA yoktur.
class CustomerProcessTimeline extends StatelessWidget {
  const CustomerProcessTimeline({super.key, required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context) {
    return AknCard(
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
        icon: Icons.add_rounded,
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
              icon: Icons.contact_support_rounded,
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
              icon: Icons.reply_rounded,
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
            icon: Icons.hourglass_top_rounded,
          ),
        );
      case ApprovalStatus.infoRequested:
        steps.add(
          TimelineStep(
            title: ApprovalsCopy.customerStatus(d),
            state: TimelineState.current,
            icon: Icons.contact_support_rounded,
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
            icon: Icons.check_rounded,
          ),
        );
      case ApprovalStatus.rejected:
        steps.add(
          TimelineStep(
            title: 'Reddedildi',
            subtitle: d.decisionNote,
            time: shortStamp(finishedAt),
            state: TimelineState.failed,
            icon: Icons.close_rounded,
          ),
        );
      default:
        steps.add(
          TimelineStep(
            title: 'Talep kapatıldı',
            time: shortStamp(finishedAt),
            state: TimelineState.upcoming,
            icon: Icons.block_rounded,
          ),
        );
    }
    return steps;
  }
}

/// Olay günlüğü (bayi / merkez görünümü): son olaylar, "Tüm olaylar" ile genişler.
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
    ApprovalEventType.created => Icons.add_circle_outline_rounded,
    ApprovalEventType.viewed => Icons.visibility_outlined,
    ApprovalEventType.attachmentViewed => Icons.attach_file_rounded,
    ApprovalEventType.approved ||
    ApprovalEventType.preApproved => Icons.check_circle_outline_rounded,
    ApprovalEventType.conditionallyApproved => Icons.rule_rounded,
    ApprovalEventType.rejected => Icons.cancel_outlined,
    ApprovalEventType.infoRequested => Icons.contact_support_outlined,
    ApprovalEventType.infoProvided => Icons.reply_rounded,
    ApprovalEventType.reminded => Icons.notifications_active_outlined,
    ApprovalEventType.escalated => Icons.trending_up_rounded,
    ApprovalEventType.delegated => Icons.share_rounded,
    ApprovalEventType.cancelled => Icons.block_rounded,
    ApprovalEventType.reopened => Icons.restart_alt_rounded,
    ApprovalEventType.levelsUpdated => Icons.layers_rounded,
    ApprovalEventType.unknown => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final events = widget.detail.events.reversed.toList();
    final shown = _all ? events : events.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AknCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.lineSoft),
                _EventRow(
                  event: shown[i],
                  icon: _icon(shown[i].eventType),
                  onOpenFile: widget.onOpenFile,
                ),
              ],
            ],
          ),
        ),
        if (events.length > 4)
          Align(
            alignment: Alignment.centerLeft,
            child: AknButton.ghost(
              label: _all ? 'Daha az göster' : 'Tüm olaylar (${events.length})',
              icon: _all
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              onPressed: () => setState(() => _all = !_all),
            ),
          ),
        if (events.isEmpty) Text('Henüz olay yok.', style: t.bodySmall),
      ],
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
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: c.dim),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.displayLabel,
                  style: t.bodyStrong.copyWith(fontSize: 14),
                ),
                if (large) Text(Fmt.relative(e.occurredAt), style: t.caption),
                if (e.actorText != null) Text(e.actorText!, style: t.bodySmall),
                if (e.note != null) ...[
                  const SizedBox(height: 2),
                  Text(e.note!, style: t.body.copyWith(fontSize: 14)),
                ],
                if (e.attachmentFileName != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_file_rounded, size: 14, color: c.dim),
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
            Text(Fmt.relative(e.occurredAt), style: t.caption),
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
        child: InkWell(onTap: () => onOpenFile!(file), child: row),
      );
    }
    return Semantics(label: label, excludeSemantics: true, child: row);
  }
}
