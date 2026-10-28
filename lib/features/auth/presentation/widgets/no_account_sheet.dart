import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../application/server_gate_controller.dart';
import '../../copy.dart';
import 'support_contacts.dart';

/// "Hesabım yok" (spec A.4 A1; tasarım v3): hesapları bayi ya da şirket yöneticisi açar (simge karolu iki
/// madde); destek kanalları `app/config.support` üzerinden, simge karolu beyaz kartta. Bölümler sırayla
/// belirir.
Future<void> showNoAccountSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  title: AuthCopy.noAccountTitle,
  builder: (ctx) => const _NoAccountBody(),
);

class _NoAccountBody extends ConsumerWidget {
  const _NoAccountBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final links = ref.watch(authLinksProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      // v3: sayfa açılırken bölümler sırayla yukarı kayarak belirir.
      children: [
        StaggerItem(
          index: 0,
          child: Text(AuthCopy.noAccountBody, style: t.body),
        ),
        const SizedBox(height: 16),
        const StaggerItem(
          index: 1,
          child: _Point(
            icon: PhosphorIconsRegular.buildingOffice,
            text: AuthCopy.noAccountCustomer,
          ),
        ),
        const SizedBox(height: 12),
        const StaggerItem(
          index: 2,
          child: _Point(
            icon: PhosphorIconsRegular.identificationBadge,
            text: AuthCopy.noAccountBayi,
          ),
        ),
        const SizedBox(height: 20),
        StaggerItem(
          index: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  AuthCopy.supportTitle,
                  style: t.bodyStrong.copyWith(color: c.ink),
                ),
              ),
              const SizedBox(height: 8),
              SupportContacts(
                links: links,
                mailSubject: AuthCopy.supportMailSubject,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    // v3: 40 px yumuşak karo içinde simge, yanında metin.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: AknRadius.buttonSmall,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: c.ink),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(text, style: t.body.copyWith(color: c.ink)),
          ),
        ),
      ],
    );
  }
}
