import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../application/field_access.dart';
import '../copy.dart';
import 'forms_view.dart';
import 'leads_view.dart';
import 'portfolio_view.dart';
import 'widgets/field_widgets.dart';

/// Saha sekmesinin bölümleri.
enum FieldSection {
  forms('forms'),
  pending('pending'),
  rejected('rejected'),
  leads('leads'),
  portfolio('portfolio');

  const FieldSection(this.key);
  final String key;

  static FieldSection? parse(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// `/field` (spec A.4 A6 "Saha tab by persona"):
/// - saha satış temsilcisi → Formlar · Ön kayıt · Portföy,
/// - diğer roller → "Saha ekibi": Formlar (temsilciye göre) · Onayda (kademeye göre) · Reddedilen ·
///   Ön kayıt (`lead.viewAll` ile tümü); Portföy yok,
/// - yalnızca `StationLeads:Gorur` → yalnızca ön kayıtlar.
///
/// `?tab=forms|pending|rejected|leads|portfolio` ve `?status=` derin bağlantıyla açılır.
class FieldHubPage extends ConsumerStatefulWidget {
  const FieldHubPage({super.key, this.initialTab, this.initialStatus});

  final String? initialTab;
  final String? initialStatus;

  @override
  ConsumerState<FieldHubPage> createState() => _FieldHubPageState();
}

class _FieldHubPageState extends ConsumerState<FieldHubPage> {
  FieldSection? _section;

  /// Derin bağlantıyla gelen durum süzgeci (bölüm başına bir kez uygulanır).
  final Map<FieldSection, String?> _statusFor = {};
  int _linkSeq = 0;

  @override
  void initState() {
    super.initState();
    _applyLink(widget.initialTab, widget.initialStatus);
  }

  @override
  void didUpdateWidget(covariant FieldHubPage old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab ||
        old.initialStatus != widget.initialStatus) {
      setState(() => _applyLink(widget.initialTab, widget.initialStatus));
    }
  }

  void _applyLink(String? tab, String? status) {
    final s = FieldSection.parse(tab);
    if (s == null) return;
    _section = s;
    _statusFor[s] = status;
    _linkSeq++;
  }

  List<FieldSection> _sections(FieldAccess a) => switch (a.mode) {
    FieldMode.rep => [
      FieldSection.forms,
      if (a.canSeeLeads) FieldSection.leads,
      FieldSection.portfolio,
    ],
    FieldMode.team => [
      FieldSection.forms,
      FieldSection.pending,
      FieldSection.rejected,
      if (a.canSeeLeads) FieldSection.leads,
    ],
    FieldMode.leadsOnly => [FieldSection.leads],
    FieldMode.none => const [],
  };

  String _label(FieldSection s, FieldAccess a) => switch (s) {
    FieldSection.forms => a.isRep ? FieldCopy.myForms : FieldCopy.forms,
    FieldSection.pending => FieldCopy.pending,
    FieldSection.rejected => FieldCopy.rejected,
    FieldSection.leads => a.isRep ? FieldCopy.myLeads : FieldCopy.leads,
    FieldSection.portfolio => FieldCopy.portfolio,
  };

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(fieldAccessProvider);
    final sections = _sections(access);
    if (sections.isEmpty) {
      return const AppScaffold(
        title: 'Saha',
        body: EmptyState(
          title: FieldCopy.forbiddenTitle,
          message: FieldCopy.forbiddenMessage,
          illustration: AknIllustration.field,
        ),
      );
    }
    final current = sections.contains(_section) ? _section! : sections.first;
    final add = _addAction(context, current, access);
    return AppScaffold(
      title: access.title,
      subtitle: access.mode == FieldMode.team
          ? 'Ekibin formları ve ön kayıtları'
          : null,
      actions: [?add],
      body: Column(
        children: [
          if (sections.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: FieldSectionSwitcher<FieldSection>(
                options: [
                  for (final s in sections)
                    FilterOption(value: s, label: _label(s, access)),
                ],
                value: current,
                onChanged: (s) => setState(() => _section = s),
              ),
            ),
          Expanded(
            child: FadeThroughSwitcher(
              child: KeyedSubtree(
                key: ValueKey('${current.key}-$_linkSeq'),
                child: _body(current, access),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(FieldSection s, FieldAccess a) => switch (s) {
    FieldSection.forms => FieldFormsView(
      config: a.isRep
          ? FieldFormsConfig.rep(initialStatus: _intStatus(s))
          : FieldFormsConfig.team(initialStatus: _intStatus(s)),
    ),
    FieldSection.pending => const FieldFormsView(
      config: FieldFormsConfig.pending(),
    ),
    FieldSection.rejected => const FieldFormsView(
      config: FieldFormsConfig.rejected(),
    ),
    FieldSection.leads => FieldLeadsView(
      all: !a.isRep && a.canSeeAllLeads,
      initialStatus: _statusFor[s],
    ),
    FieldSection.portfolio => const FieldPortfolioView(),
  };

  int? _intStatus(FieldSection s) => int.tryParse(_statusFor[s] ?? '');

  /// Bölümün "ekle" eylemi (tasarım v3: içeriğin üstünde yüzen düğme yok): üst çubukta küçük turuncu
  /// birincil düğme ("+ Ön kayıt", "+ Saha formu").
  Widget? _addAction(BuildContext context, FieldSection s, FieldAccess a) {
    final (label, path, show) = switch (s) {
      FieldSection.leads => (
        'Ön kayıt',
        AppRoutes.fieldLeadNew,
        a.canCreateLead,
      ),
      FieldSection.portfolio || FieldSection.forms => (
        'Saha formu',
        AppRoutes.fieldFormNew,
        // Temsilcide alt menünün orta düğmesi zaten "Saha formu": aynı eylem iki kez görünmez.
        a.canCreateForm && !a.hasCenterFormAction,
      ),
      _ => ('', '', false),
    };
    if (!show) return null;
    final spoken = label == 'Ön kayıt' ? 'Yeni ön kayıt' : 'Yeni saha formu';
    // Büyük yazıda başlıkla yan yana sığması için yalnızca simge (etiketi ekran okuyucuda).
    if (fieldLargeText(context)) {
      return AknIconButton(
        icon: PhosphorIconsRegular.plus,
        semanticLabel: spoken,
        onPressed: () => context.push(path),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: AknButton(
        label: label,
        icon: PhosphorIconsRegular.plus,
        size: AknButtonSize.small,
        semanticLabel: spoken,
        onPressed: () => context.push(path),
      ),
    );
  }
}
