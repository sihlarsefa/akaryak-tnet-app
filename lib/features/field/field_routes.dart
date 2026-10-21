import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/nav_keys.dart';
import '../../core/ui/ui.dart';
import 'application/field_access.dart';
import 'application/form_wizard_controller.dart';
import 'application/lead_wizard_controller.dart';
import 'copy.dart';
import 'presentation/field_hub_page.dart';
import 'presentation/form_detail_page.dart';
import 'presentation/form_wizard_page.dart';
import 'presentation/lead_detail_page.dart';
import 'presentation/lead_wizard_page.dart';

/// Saha rotaları (spec C.4 derin bağlantı sözleşmesi):
/// - `/field?tab=forms|pending|rejected|leads|portfolio&status=` (sekme),
/// - `/field/forms/new?customerId=&customerTitle=&op=` (sihirbaz; `op` = kuyruktaki taslak),
/// - `/field/forms/:id`, `/field/forms/:id/edit`,
/// - `/field/leads/new?op=`, `/field/leads/:id`, `/field/leads/:id/edit`.
///
/// Ayrıntı ve sihirbaz sayfaları alt menünün üstünde (kök gezgin) açılır; sihirbazlar tam ekran
/// diyalogdur (açık "Kapat"; iOS'ta kaydırarak geri çıkılmaz, kaydedilmemiş değişiklik sorulur).
List<RouteBase> fieldRoutes() => [
  GoRoute(
    path: '/field',
    builder: (context, state) => FieldHubPage(
      initialTab: state.uri.queryParameters['tab'],
      initialStatus: state.uri.queryParameters['status'],
    ),
    routes: [
      GoRoute(
        path: 'forms/new',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final q = state.uri.queryParameters;
          return MaterialPage<void>(
            key: state.pageKey,
            fullscreenDialog: true,
            child: _Guard(
              allowed: (a) => a.canCreateForm,
              child: FieldFormWizardPage(
                args: FormWizardArgs(
                  customerId: int.tryParse(q['customerId'] ?? ''),
                  customerTitle: q['customerTitle'],
                  queuedOpId: q['op'],
                ),
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: 'forms/:id/edit',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return MaterialPage<void>(
            key: state.pageKey,
            fullscreenDialog: true,
            child: _Guard(
              allowed: (a) => a.canEditForm && id != null,
              child: FieldFormWizardPage(args: FormWizardArgs(formId: id)),
            ),
          );
        },
      ),
      GoRoute(
        path: 'forms/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return _Guard(
            allowed: (a) => a.canSeeForms && id != null,
            child: FieldFormDetailPage(id: id ?? 0),
          );
        },
      ),
      GoRoute(
        path: 'leads/new',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage<void>(
          key: state.pageKey,
          fullscreenDialog: true,
          child: _Guard(
            allowed: (a) => a.canCreateLead,
            child: FieldLeadWizardPage(
              args: LeadWizardArgs(queuedOpId: state.uri.queryParameters['op']),
            ),
          ),
        ),
      ),
      GoRoute(
        path: 'leads/:id/edit',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return MaterialPage<void>(
            key: state.pageKey,
            fullscreenDialog: true,
            child: _Guard(
              allowed: (a) => a.canEditLead && id != null,
              child: FieldLeadWizardPage(args: LeadWizardArgs(leadId: id)),
            ),
          );
        },
      ),
      GoRoute(
        path: 'leads/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return _Guard(
            allowed: (a) => a.canSeeLeads && id != null,
            child: FieldLeadDetailPage(id: id ?? 0),
          );
        },
      ),
    ],
  ),
];

/// Yetkisiz açılışta (eski derin bağlantı, rol değişti) sakin bir "yetkiniz yok" ekranı.
class _Guard extends ConsumerWidget {
  const _Guard({required this.allowed, required this.child});

  final bool Function(FieldAccess access) allowed;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(fieldAccessProvider);
    if (allowed(access)) return child;
    return const AppScaffold(
      title: 'Saha',
      body: EmptyState(
        title: FieldCopy.forbiddenTitle,
        message: FieldCopy.forbiddenMessage,
        illustration: AknIllustration.locked,
      ),
    );
  }
}
