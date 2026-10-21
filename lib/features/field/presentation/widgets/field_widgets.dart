import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/media/attachment_gallery.dart';
import '../../../../core/models/attachment.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/offline/outbox_op.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';
import '../../data/field_models.dart';
import '../../data/field_outbox.dart';
import '../../data/lead_models.dart';

/// Bant çipi (renk + ikon + metin; tek başına renk değil).
class FieldBandChip extends StatelessWidget {
  const FieldBandChip({super.key, required this.band, this.small = false});

  final FieldBand band;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final base = AknStatus.band(band.key, label: band.label);
    final tone = band.tone.isEmpty
        ? base.tone
        : AknStatus.toneFromKey(band.tone);
    return StatusChip(
      label: base.label,
      tone: tone == AknTone.neutral && base.tone != AknTone.neutral
          ? base.tone
          : tone,
      icon: base.icon,
      size: small ? StatusChipSize.small : StatusChipSize.medium,
    );
  }
}

/// Konum doğruluğu çipi ("±12 m"; 50 m üstü ya da yaklaşık konum uyarı tonunda).
class AccuracyChip extends StatelessWidget {
  const AccuracyChip({
    super.key,
    required this.meters,
    this.approximate = false,
  });

  final double? meters;
  final bool approximate;

  @override
  Widget build(BuildContext context) {
    final m = meters;
    final low = approximate || m == null || m > 50;
    final text = approximate
        ? 'Yaklaşık konum'
        : m == null
        ? 'Doğruluk bilinmiyor'
        : '±${Fmt.number(m, maxFraction: m < 10 ? 1 : 0)} m';
    return StatusChip(
      label: text,
      tone: low ? AknTone.warn : AknTone.ok,
      icon: low ? Icons.gps_not_fixed_rounded : Icons.gps_fixed_rounded,
      size: StatusChipSize.small,
    );
  }
}

/// Sunucudaki belgeler: normal yazıda küçük resim ızgarası, büyük yazıda satır listesi (ızgara hücresi
/// sabit yükseklikte; 2× yazıda dosya adı sığmaz — spec C.7).
class FieldDocumentList extends StatelessWidget {
  const FieldDocumentList({
    super.key,
    required this.attachments,
    this.onDelete,
  });

  final List<Attachment> attachments;
  final void Function(Attachment attachment)? onDelete;

  void _open(BuildContext context, int index) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => AttachmentViewerPage(
            attachments: attachments,
            initialIndex: index,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    if (!fieldLargeText(context)) {
      return AttachmentGallery(attachments: attachments, onDelete: onDelete);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < attachments.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AttachmentTile(
              fileName: attachments[i].fileName,
              kindLabel: attachments[i].kindLabel,
              sizeBytes: attachments[i].sizeBytes,
              contentType: attachments[i].contentType,
              subtitle: attachments[i].uploadedByName,
              // Büyük yazıda "Görüntüle" satıra sığmaz; kısa fiil.
              actionLabel: 'Aç',
              onTap: () => _open(context, i),
              onDelete: onDelete != null && attachments[i].canDelete
                  ? () => onDelete!(attachments[i])
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Büyük yazı (≥ 1,3×): yan yana öğeler alt alta dizilir (spec C.7; 360 dp'de taşma olmaz).
bool fieldLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) / 10 >= 1.3;

/// Başlık + sağdaki öğe (durum çipi, tutar, düğme): normal yazıda yan yana, büyük yazıda alt alta.
class FieldTitleRow extends StatelessWidget {
  const FieldTitleRow({
    super.key,
    required this.title,
    this.trailing,
    this.gap = 8,
  });

  final Widget title;
  final Widget? trailing;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final tr = trailing;
    if (tr == null) return title;
    if (fieldLargeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 4), tr],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        SizedBox(width: gap),
        tr,
      ],
    );
  }
}

/// Bölüm seçici: tek seçimli, yatay kayan çipler (etiketler büyük yazıda da kırpılmaz; seçili olmayan
/// etiketler AA kontrastında — spec C.7).
class FieldSectionSwitcher<T> extends StatelessWidget {
  const FieldSectionSwitcher({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<FilterOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => FilterChips<T>(
    options: options,
    selected: {value},
    allowEmpty: false,
    onChanged: (s) {
      if (s.isNotEmpty) onChanged(s.first);
    },
  );
}

/// Saha formu defter satırı (tasarım v2 §6.8): cari başlıkta, form no + litre + vade ikinci satırda,
/// tutar sağda (son hareket altında), durum lambası ve onay kademesi / finans durumu alt satırda.
/// Listede satırları [AknLedger] ya da [AknLedgerDivider] ile ayırın.
class FieldFormTile extends StatelessWidget {
  const FieldFormTile({
    super.key,
    required this.row,
    this.showRep = false,
    this.onTap,
  });

  final FieldFormRow row;
  final bool showRep;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final status = row.status.statusStyle;
    final pending = row.status == FieldOrderFormStatus.pendingApproval;
    final finance =
        row.financeStatus.isAwaitingDecision &&
        row.status != FieldOrderFormStatus.rejected &&
        row.status != FieldOrderFormStatus.cancelled;
    final level = '${FieldLevels.label(row.requiredApprovalLevel)} onayında';
    final second = [
      row.formNumber,
      Fmt.liters(row.totalLiters),
      if (row.paymentTermDays > 0) '${row.paymentTermDays} gün vade',
      if (showRep && row.salesRepresentativeName != null)
        row.salesRepresentativeName!,
    ].join(', ');
    final label = [
      row.customerTitle,
      row.formNumber,
      status.label,
      if (pending) level,
      if (finance) row.financeStatus.statusStyle.label,
      Fmt.liters(row.totalLiters),
      if (row.totalAmount > 0) Fmt.money(row.totalAmount),
      if (row.paymentTermDays > 0) '${row.paymentTermDays} gün vade',
      if (showRep && row.salesRepresentativeName != null)
        'Temsilci ${row.salesRepresentativeName}',
      fieldLowerFirst(Fmt.relative(row.lastActivity)),
    ].join(', ');
    final Widget? trailing = pending
        ? Text(level, style: t.bodySmall.copyWith(color: c.dim))
        : finance
        ? AknLamp.style(row.financeStatus.statusStyle, size: AknLampSize.small)
        : null;
    return AknListTile(
      title: row.customerTitle,
      subtitle: second,
      amount: row.totalAmount > 0 ? Fmt.money(row.totalAmount) : null,
      amountMeta: fieldLowerFirst(Fmt.relative(row.lastActivity)),
      status: AknStatusLine(lamp: AknLamp.style(status), trailing: trailing),
      semanticLabel: label,
      onTap: onTap ?? () => context.push(AppRoutes.fieldForm(row.id)),
    );
  }
}

/// Ön kayıt defter satırı: firma başlıkta, kayıt no + il + aylık litre ikinci satırda, son hareket
/// sağda, durum lambası alt satırda ("VKN sistemde kayıtlı" bilgisiyle).
class FieldLeadTile extends StatelessWidget {
  const FieldLeadTile({super.key, required this.row, this.showRep = false});

  final LeadRow row;
  final bool showRep;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final status = row.status.statusStyle;
    final second = [
      row.leadNumber,
      ?row.city,
      if ((row.monthlyLiters ?? 0) > 0) '${Fmt.liters(row.monthlyLiters)}/ay',
      if (showRep && row.salesRepName != null) row.salesRepName!,
    ].join(', ');
    final when = fieldLowerFirst(
      Fmt.relative(row.submittedAt ?? row.createdAt),
    );
    return AknListTile(
      title: row.companyTitle.isEmpty ? 'Ünvansız ön kayıt' : row.companyTitle,
      subtitle: second,
      meta: when,
      status: AknStatusLine(
        lamp: AknLamp.style(status),
        trailing: row.existsElsewhere
            ? Text(
                'VKN sistemde kayıtlı',
                style: t.bodySmall.copyWith(color: c.dim),
              )
            : null,
      ),
      semanticLabel: [
        row.companyTitle,
        row.leadNumber,
        status.label,
        ?row.city,
        if ((row.monthlyLiters ?? 0) > 0)
          'ayda ${Fmt.liters(row.monthlyLiters)}',
        if (showRep && row.salesRepName != null) row.salesRepName!,
        if (row.existsElsewhere) 'Bu VKN sistemde kayıtlı',
        when,
      ].join(', '),
      onTap: () => context.push(AppRoutes.fieldLead(row.id)),
    );
  }
}

/// Gönderilmeyi bekleyen saha işlemi satırı ("Kaydedildi, bağlantı gelince gönderilecek"): soldaki
/// simge ve lamba durumu söyler; altta "Düzelt", "Şimdi dene", "Vazgeç".
class FieldQueuedTile extends ConsumerWidget {
  const FieldQueuedTile({super.key, required this.item, this.onEdit});

  final FieldQueuedItem item;

  /// "Düzelt" (taslak sihirbazı kuyruktaki işlemle açılır).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final status = item.status;
    final (tone, icon, label) = switch (status) {
      OutboxStatus.needsAttention => (
        AknTone.danger,
        Icons.error_outline_rounded,
        FieldCopy.attentionChip,
      ),
      OutboxStatus.sending => (
        AknTone.info,
        Icons.cloud_upload_outlined,
        FieldCopy.sendingChip,
      ),
      OutboxStatus.failed => (
        AknTone.warn,
        Icons.schedule_rounded,
        item.nextAttemptAt == null
            ? 'Tekrar denenecek'
            : 'Tekrar denenecek, ${Fmt.time(item.nextAttemptAt)}',
      ),
      _ => (AknTone.warn, Icons.schedule_rounded, FieldCopy.waitingChip),
    };
    final subtitle = [
      ?item.customerTitle,
      if ((item.liters ?? 0) > 0) Fmt.liters(item.liters),
      if (item.uploadKindLabel != null) item.uploadKindLabel!,
    ].join(', ');
    final error = status == OutboxStatus.needsAttention ? item.lastError : null;
    final outbox = ref.read(fieldOutboxProvider);
    final actions = <Widget>[
      if (status == OutboxStatus.needsAttention && onEdit != null)
        AknButton.secondary(
          label: 'Düzelt',
          size: AknButtonSize.small,
          onPressed: onEdit,
        ),
      if (status == OutboxStatus.failed ||
          status == OutboxStatus.needsAttention)
        AknButton.ghost(
          label: 'Şimdi dene',
          size: AknButtonSize.small,
          onPressed: () => outbox.retry(item.op.id),
        ),
      if (status != OutboxStatus.sending)
        AknButton.ghost(
          label: 'Vazgeç',
          size: AknButtonSize.small,
          onPressed: () async {
            final ok = await showConfirmSheet(
              context,
              title: 'Bu işlemden vazgeçilsin mi?',
              message: item.isUpload
                  ? 'Belge bu cihazdan silinir ve gönderilmez.'
                  : 'Kuyruktaki taslak bu cihazdan silinir ve sunucuya gönderilmez.',
              confirmLabel: 'Vazgeç',
              cancelLabel: 'Geri dön',
              destructive: true,
            );
            if (ok) await outbox.discardChain(item.op.id);
          },
        ),
    ];
    return Padding(
      padding: AknSpace.row,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: [
              item.title,
              label,
              if (subtitle.isNotEmpty) subtitle,
              ?error,
            ].join(', '),
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 24, color: c.tone(tone).fg),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: t.headline.copyWith(color: c.ink),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: t.bodySmall.copyWith(color: c.dim),
                        ),
                      ],
                      const SizedBox(height: 8),
                      AknLamp(label: label, tone: tone),
                      if (error != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          error,
                          style: t.bodySmall.copyWith(color: c.danger.fg),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 32, top: 4),
              child: Wrap(spacing: 4, runSpacing: 4, children: actions),
            ),
        ],
      ),
    );
  }
}

/// İlk harfi Türkçe kurala göre küçültür ("Dün 14:20" → "dün 14:20").
String fieldLowerFirst(String s) {
  if (s.isEmpty) return s;
  final first = String.fromCharCode(s.runes.first);
  return TurkishText.lower(first) + s.substring(first.length);
}

/// Liste sonu: sonraki sayfa yükleniyor / yüklenemedi / bitti.
/// Liste içinde (kaydırılabilir alanın çocuğu olarak) ilk yükleme iskeleti; kendisi kaymaz.
class FieldSkeletonCards extends StatelessWidget {
  const FieldSkeletonCards({super.key, this.count = 5, this.lines = 2});

  final int count;
  final int lines;

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [for (var i = 0; i < count; i++) SkeletonCard(lines: lines)],
      ),
    ),
  );
}

class FieldListFooter extends StatelessWidget {
  const FieldListFooter({
    super.key,
    required this.loading,
    this.error,
    this.onRetry,
    this.total,
    this.shown,
  });

  final bool loading;
  final AppFailure? error;
  final VoidCallback? onRetry;
  final int? total;
  final int? shown;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: ChevronSpinner(size: 24)),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              error!.message,
              style: t.bodySmall,
              textAlign: TextAlign.center,
            ),
            AknButton.ghost(
              label: FieldCopy.retry,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      );
    }
    if (total != null && shown != null && total! > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            total == shown ? '$total kayıt' : '$shown / $total kayıt',
            style: t.caption,
          ),
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}

/// Önbellekten gösteriliyor: "Son güncelleme 14:20".
class FieldCachedNote extends StatelessWidget {
  const FieldCachedNote({super.key, required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 16, color: c.dim),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Son güncelleme ${fieldLowerFirst(Fmt.dayLabel(at))} ${Fmt.time(at)}.',
              style: t.label.copyWith(color: c.dim),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alan altı hata metni (ikon + metin).
class FieldErrorText extends StatelessWidget {
  const FieldErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m == null || m.isEmpty) return const SizedBox.shrink();
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 16, color: c.danger.fg),
            const SizedBox(width: 6),
            Expanded(
              child: Text(m, style: t.bodySmall.copyWith(color: c.danger.fg)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste durumunu (ilk yükleme, hata, boş, çevrimdışı) C.5 tarifine göre çizer.
class FieldListState extends StatelessWidget {
  const FieldListState({
    super.key,
    required this.error,
    required this.onRetry,
    required this.emptyTitle,
    this.emptyMessage,
    this.filtered = false,
    this.onClearFilters,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.illustration = AknIllustration.field,
  });

  final AppFailure? error;
  final VoidCallback onRetry;
  final String emptyTitle;
  final String? emptyMessage;
  final bool filtered;
  final VoidCallback? onClearFilters;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final AknIllustration illustration;

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e != null) {
      return switch (e) {
        OfflineFailure() => const EmptyState(
          title: FieldCopy.offlineEmptyTitle,
          message: FieldCopy.offlineEmptyMessage,
          illustration: AknIllustration.offline,
        ),
        ForbiddenFailure() => const EmptyState(
          title: FieldCopy.forbiddenTitle,
          message: FieldCopy.forbiddenMessage,
          illustration: AknIllustration.error,
        ),
        _ => ErrorState(
          message: e.message,
          onRetry: onRetry,
          traceId: switch (e.traceId) {
            final t? => t.substring(0, t.length.clamp(0, 8)),
            null => null,
          },
        ),
      };
    }
    if (filtered) {
      return EmptyState(
        title: FieldCopy.filteredEmptyTitle,
        illustration: AknIllustration.search,
        actionLabel: onClearFilters == null
            ? null
            : FieldCopy.filteredEmptyAction,
        onAction: onClearFilters,
      );
    }
    return EmptyState(
      title: emptyTitle,
      message: emptyMessage,
      illustration: illustration,
      actionLabel: emptyActionLabel,
      onAction: onEmptyAction,
    );
  }
}

/// Bilgi satırı grubu (kart içinde etiket / değer).
class FieldFacts extends StatelessWidget {
  const FieldFacts({super.key, required this.facts});

  final List<(String, String?)> facts;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final (label, value) in facts)
        if (value != null && value.trim().isNotEmpty) (label, value),
    ];
    return Column(
      children: [
        for (final (label, value) in visible)
          FactRow(
            label: label,
            value: value,
            valueStyle: context.aknText.body.copyWith(color: context.akn.ink),
          ),
      ],
    );
  }
}

/// Bölüm (tasarım v2 §4.5): başlık (`title` 20/26, sağda isteğe bağlı öğe) ve altında içerik, 20 px
/// kenar boşluğunda; kutu yok. [icon] ve [margin] API uyumu için durur (v2'de simge çizilmez).
class FieldSectionCard extends StatelessWidget {
  const FieldSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  });

  final String title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: t.title.copyWith(color: c.ink)),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Plakanın okumaları: normalde [PlateReadouts]; çok büyük yazıda (≥ 1,6×) etiket / değer satırları,
/// değer kendi sütununda küçülerek sığar (sayı hiçbir zaman bölünmez ya da taşmaz).
class FieldPlateReadouts extends StatelessWidget {
  const FieldPlateReadouts({super.key, required this.items});

  final List<PlateReadout> items;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    if (scale < 1.6) return PlateReadouts(items: items);
    final c = context.akn;
    final t = context.aknText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++)
          Semantics(
            label:
                items[i].semanticLabel ??
                '${items[i].label}: ${items[i].value}${items[i].unit == null ? '' : ' ${items[i].unit}'}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: i == 0
                  ? null
                  : BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      items[i].label,
                      style: t.label.copyWith(height: 16 / 13, color: c.dim),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text.rich(
                        TextSpan(
                          text: items[i].value,
                          style: t.number.copyWith(color: c.ink),
                          children: [
                            if (items[i].unit != null)
                              TextSpan(
                                text: ' ${items[i].unit}',
                                style: t.readoutUnit.copyWith(color: c.ink),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
