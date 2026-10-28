import 'dart:async';
import 'dart:math' as math;

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
      icon: low ? PhosphorIconsRegular.gps : PhosphorIconsRegular.gpsFix,
      size: StatusChipSize.small,
    );
  }
}

/// Sunucudaki belgeler: normal yazıda küçük resim ızgarası (dar kartta iki, genişte üç sütun), büyük
/// yazıda satır listesi (ızgara hücresi sabit yükseklikte; 2× yazıda dosya adı sığmaz — spec C.7).
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
      // Kartın içinde dar kalan ızgarada küçük resim etiketi sığsın: dar alanda iki sütun.
      return LayoutBuilder(
        builder: (context, cons) => AttachmentGallery(
          attachments: attachments,
          onDelete: onDelete,
          crossAxisCount: cons.maxWidth >= 330 ? 3 : 2,
        ),
      );
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

/// Saha formu satırı (tasarım v3 §4 liste satırı): cari başlıkta, form no + litre + vade ikinci
/// satırda, tutar sağda (tabular; son hareket altında), durum lambası ve onay kademesi / finans
/// durumu alt satırda. Basınca satır yumuşak kuyuya döner ve hafifçe küçülür. Listede her satırı bir
/// [FieldListCard] içine koyun (ya da satırları [AknLedger] ile kartta toplayın).
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

/// Ön kayıt satırı (tasarım v3 §4): firma başlıkta, kayıt no + il + aylık litre ikinci satırda, son
/// hareket sağda, durum lambası alt satırda ("VKN sistemde kayıtlı" bilgisiyle).
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
/// tonlu simge kutusu (gönderilirken bulut simgesi hafifçe nefes alır) ve lamba durumu söyler; altta
/// "Düzelt", "Şimdi dene", "Vazgeç".
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
        PhosphorIconsRegular.warningCircle,
        FieldCopy.attentionChip,
      ),
      OutboxStatus.sending => (
        AknTone.info,
        PhosphorIconsRegular.cloudArrowUp,
        FieldCopy.sendingChip,
      ),
      OutboxStatus.failed => (
        AknTone.warn,
        PhosphorIconsRegular.clock,
        item.nextAttemptAt == null
            ? 'Tekrar denenecek'
            : 'Tekrar denenecek, ${Fmt.time(item.nextAttemptAt)}',
      ),
      _ => (AknTone.warn, PhosphorIconsRegular.clock, FieldCopy.waitingChip),
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
                _QueueGlyph(
                  icon: icon,
                  tone: tone,
                  live: status == OutboxStatus.sending,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: t.bodyStrong.copyWith(color: c.ink),
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
              padding: const EdgeInsetsDirectional.only(start: 54, top: 8),
              child: Wrap(spacing: 4, runSpacing: 4, children: actions),
            ),
        ],
      ),
    );
  }
}

/// Bekleyen işlemin tonlu simge kutusu (40 px yumuşak kare); gönderilirken hafifçe nefes alır
/// (ortam hareketi: testlerde ve hareket azaltmada durur).
class _QueueGlyph extends StatelessWidget {
  const _QueueGlyph({
    required this.icon,
    required this.tone,
    required this.live,
  });

  final IconData icon;
  final AknTone tone;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final box = AknIconBox(icon: icon, tone: tone, size: 40, iconSize: 22);
    if (!live) return box;
    return AknAmbient(
      period: AknMotion.breathe,
      reverse: true,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, -2 * t),
        child: Opacity(opacity: 1 - 0.25 * t, child: child),
      ),
      child: box,
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
              icon: PhosphorIconsRegular.arrowClockwise,
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
          Icon(
            PhosphorIconsRegular.clockCounterClockwise,
            size: 16,
            color: c.dim,
          ),
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

/// Alan altı hata metni (uyarı simgesi + metin, tehlike tonunda). Belirince yüksekliği kayarak açılır
/// ve kısa bir sarsıntıyla (3 hızlı ±6 px) dikkat çeker; ileti değişince yeniden sarsılır. Hareket
/// azaltmada sabit.
class FieldErrorText extends StatelessWidget {
  const FieldErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final empty = m == null || m.isEmpty;
    return AknAnimatedSize(
      alignment: Alignment.topCenter,
      child: empty
          ? const SizedBox(width: double.infinity)
          : _Shake(key: ValueKey(m), child: _ErrorLine(m)),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                PhosphorIconsRegular.warningCircle,
                size: 16,
                color: c.danger.fg,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: t.bodySmall.copyWith(color: c.danger.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// İlk görünüşte üç hızlı ±6 px sarsıntı (sönerek; sonlu). Hareket azaltmada sabit.
class _Shake extends StatelessWidget {
  const _Shake({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = AknMotion.of(context, const Duration(milliseconds: 420));
    if (d == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      child: child,
      builder: (context, v, child) => Transform.translate(
        offset: Offset(6 * math.sin(v * math.pi * 6) * (1 - v), 0),
        child: Opacity(opacity: (v * 4).clamp(0.0, 1.0), child: child),
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

/// Bilgi satırı grubu (kart içinde etiket / değer; tasarım v3 §4): etiket soluk solda, değer 15/22
/// 500 mürekkep sağda (tabular); satırlar arasında kartın içinde `lineSoft` saç çizgisi (ilkinin
/// üstünde, sonuncunun altında yok). Boş değerler atlanır.
class FieldFacts extends StatelessWidget {
  const FieldFacts({super.key, required this.facts});

  final List<(String, String?)> facts;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final visible = [
      for (final (label, value) in facts)
        if (value != null && value.trim().isNotEmpty) (label, value),
    ];
    final style = context.aknText.body.copyWith(
      color: c.ink,
      fontWeight: FontWeight.w500,
      fontFeatures: AknNumerals.tabular,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) SizedBox(height: 1, child: ColoredBox(color: c.lineSoft)),
          FactRow(
            label: visible[i].$1,
            value: visible[i].$2,
            valueStyle: style,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ],
      ],
    );
  }
}

/// Gruplanmış bilgi kartı (tasarım v3 §4 "grouped fact cards"): sayfada yüzen beyaz kart — r20,
/// yumuşak kart gölgesi (koyu temada 1 px çizgi), 20 px sayfa kenarı. Kartın başında 36 px yumuşak
/// karede bölüm simgesi ([icon]; sakin kuyu, mürekkep), başlık (17/22 700) ve sağda isteğe bağlı
/// öğe; altında içerik (18 px içeride). İçerik kartta olduğunu bilir (`AknCardScope`). [margin] API
/// uyumu için durur (kart her zaman sayfa kenarına hizalanır).
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
    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          AknIconBox(icon: icon!, size: 36, iconSize: 19),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: t.headline.copyWith(color: c.ink)),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
    return AknCard(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [head, const SizedBox(height: 10), child],
      ),
    );
  }
}

/// Liste satırının kartı (tasarım v3 §4): sayfada yüzen beyaz kart (r20, kart gölgesi), sayfa
/// kenarı 20, kartlar arası 12. Satır ([child], ör. [FieldFormTile]) kartın tamamını doldurur ve
/// basınca kartın içinde yumuşak kuyuya döner.
class FieldListCard extends StatelessWidget {
  const FieldListCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(20, 6, 20, 6),
  });

  final Widget child;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) =>
      AknCard(padding: EdgeInsets.zero, margin: margin, child: child);
}

/// Girişte solarak, [offset] px yükselerek ve [scale]'den büyüyerek belirir ([delay] sonra, bir
/// kez). `FadeUp` gibidir ama hareket bitince ağacın yapısı değişmez: içindeki sayaçlar, lambalar ve
/// plaka baştan başlamaz. Hareket azaltmada hemen son hâli.
class FieldRise extends StatefulWidget {
  const FieldRise({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AknMotion.slow,
    this.offset = 12,
    this.scale = 1,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final double scale;

  @override
  State<FieldRise> createState() => _FieldRiseState();
}

class _FieldRiseState extends State<FieldRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: AknMotion.emphasizedCurve,
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay <= Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) {
      final v = _t.value;
      final s = widget.scale + (1 - widget.scale) * v;
      // Yapı her karede aynı (Opacity → Transform): bitince çocuk yeniden kurulmaz.
      return Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, widget.offset * (1 - v), 0)
            ..multiply(Matrix4.diagonal3Values(s, s, 1)),
          child: child,
        ),
      );
    },
  );
}

/// Liste öğesinin sırayla girişi ([StaggerItem]: ilk açılışta sırayla, sonra kaydırdıkça görünür
/// oldukça); öğe sabit bir anahtarın altında durur ki giriş bitince durumu (sayaçlar, lambalar,
/// yazılan alanlar) korunsun.
class FieldStaggerItem extends StatefulWidget {
  const FieldStaggerItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<FieldStaggerItem> createState() => _FieldStaggerItemState();
}

class _FieldStaggerItemState extends State<FieldStaggerItem> {
  final GlobalKey _keep = GlobalKey();

  @override
  Widget build(BuildContext context) => StaggerItem(
    index: widget.index,
    child: KeyedSubtree(key: _keep, child: widget.child),
  );
}

/// Sırayla belirerek gelen kaydırılabilir liste (sihirbaz adımları, ayrıntı sayfaları): her çocuk bir
/// [FieldStaggerItem]'dır (anahtarı olan çocuğun anahtarı öğeye taşınır ki liste yeniden dizilince
/// eşleşme korunsun). [StaggerScope] ilk açılışta sırayı oynatır; sonradan eklenen ya da kaydırınca
/// görünen öğeler hemen kayarak girer.
class FieldStaggeredList extends StatelessWidget {
  const FieldStaggeredList({
    super.key,
    required this.children,
    this.padding,
    this.controller,
    this.physics,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => StaggerScope(
    child: ListView(
      controller: controller,
      physics: physics,
      padding: padding,
      children: [
        for (var i = 0; i < children.length; i++)
          FieldStaggerItem(
            key: children[i].key == null ? null : ValueKey(children[i].key),
            index: i,
            child: children[i],
          ),
      ],
    ),
  );
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
