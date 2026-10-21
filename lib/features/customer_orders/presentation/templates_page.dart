import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/turkish_text.dart';
import '../application/loadable.dart';
import '../application/templates_controller.dart';
import '../copy.dart';
import '../data/form_models.dart';
import 'widgets/common.dart';

/// Şablonlarım rotası (spec C.4 derin bağlantı).
const templatesRoute = '/templates';

/// Şablonlarım (spec A.4; tasarım v2 §7.7): ledger satırları (ad, satırlar, son kullanım),
/// "Kullan" (`/orders/new?fromTemplate=`) ve sil.
class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(templatesProvider);
    final policy = ref.watch(accessPolicyProvider);
    final canUse = policy.can(Pg.customerCreateOrder, Perm.create);
    final canSee = policy.can(Pg.customerCreateOrder);

    Widget body;
    if (!canSee) {
      body = const Center(
        child: EmptyState(
          title: OrdersCopy.forbidden,
          message: OrdersCopy.forbiddenMessage,
          illustration: AknIllustration.locked,
        ),
      );
    } else if (s.isFirstLoad) {
      body = const SkeletonList(itemCount: 3, lines: 2, leading: true);
    } else if (s.showError) {
      body = Center(
        child: SingleChildScrollView(
          child: FailureView(
            failure: s.error!,
            onRetry: () => ref.read(templatesProvider.notifier).refresh(),
          ),
        ),
      );
    } else {
      final items = s.data ?? const <TemplateListItem>[];
      body = PullToRefresh(
        onRefresh: () => ref.read(templatesProvider.notifier).refresh(),
        child: items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 48),
                  EmptyState(
                    title: 'Henüz şablonunuz yok',
                    message:
                        'Sipariş verirken Özet adımında “Şablon olarak kaydet”i açın ya da '
                        'bir siparişin ⋯ menüsünden şablon olarak kaydedin.',
                    illustration: AknIllustration.orders,
                    actionLabel: canUse ? OrdersCopy.newOrder : null,
                    onAction: canUse
                        ? () => context.push(AppRoutes.orderNew)
                        : null,
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
                itemCount: items.length + 1,
                separatorBuilder: (context, i) => i == 0
                    ? const SizedBox.shrink()
                    : const ContentWidth(child: AknLedgerDivider()),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return LastUpdatedNote(
                      updatedAt: s.updatedAt,
                      fromCache: s.fromCache,
                    );
                  }
                  final tpl = items[i - 1];
                  return ContentWidth(
                    child: _TemplateRow(item: tpl, canUse: canUse),
                  );
                },
              ),
      );
    }
    return AppScaffold(
      title: OrdersCopy.templates,
      largeTitle: false,
      showBell: false,
      refreshing: s.refreshing,
      body: body,
    );
  }
}

class _TemplateRow extends ConsumerWidget {
  const _TemplateRow({required this.item, required this.canUse});

  final TemplateListItem item;
  final bool canUse;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmSheet(
      context,
      title: 'Şablon silinsin mi?',
      message:
          '“${item.name}” şablonu silinecek. Verilmiş siparişler etkilenmez.',
      confirmLabel: 'Sil',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(templatesProvider.notifier).delete(item.id);
      if (context.mounted) {
        AppToast.success('Şablon silindi.', context: context);
      }
      ref.read(a2DataRevisionProvider.notifier).bump();
    } on AppFailure catch (f) {
      if (context.mounted && f is! ForbiddenFailure) {
        AppToast.error(OrdersCopy.failureMessage(f), context: context);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final used = item.lastUsedAt == null
        ? 'Henüz kullanılmadı'
        : 'Son kullanım ${TurkishText.lower(Fmt.relative(item.lastUsedAt))}';
    return AknListTile(
      title: item.name,
      subtitle: '${item.subtitle}\n$used',
      subtitleMaxLines: 3,
      trailing: !canUse
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AknButton.secondary(
                  label: 'Kullan',
                  size: AknButtonSize.small,
                  semanticLabel: '${item.name} şablonuyla sipariş ver',
                  onPressed: () => context.push(
                    '${AppRoutes.orderNew}?fromTemplate=${item.id}',
                  ),
                ),
                AknIconButton(
                  icon: Icons.delete_outline_rounded,
                  semanticLabel: '${item.name} şablonunu sil',
                  color: c.dim,
                  onPressed: () => _delete(context, ref),
                ),
              ],
            ),
    );
  }
}

/// Şablon adı sayfası ("Şablon yap"). Ad dönerse kaydedilir.
Future<String?> showTemplateNameSheet(
  BuildContext context, {
  String initial = '',
}) => showAppSheet<String>(
  context: context,
  title: 'Şablon olarak kaydet',
  subtitle: 'Sonraki siparişlerde tek dokunuşla kullanın.',
  builder: (ctx) => _TemplateNameSheet(initial: initial),
);

class _TemplateNameSheet extends StatefulWidget {
  const _TemplateNameSheet({required this.initial});

  final String initial;

  @override
  State<_TemplateNameSheet> createState() => _TemplateNameSheetState();
}

class _TemplateNameSheetState extends State<_TemplateNameSheet> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final v = _name.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'Şablon adı girin.');
      return;
    }
    if (v.length > 100) {
      setState(() => _error = 'Şablon adı en çok 100 karakter olabilir.');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      AknTextField(
        controller: _name,
        label: OrdersCopy.templateName,
        maxLength: 100,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        errorText: _error,
        onSubmitted: (_) => _save(),
      ),
      const SizedBox(height: 16),
      AknButton(label: 'Kaydet', expand: true, onPressed: _save),
    ],
  );
}
