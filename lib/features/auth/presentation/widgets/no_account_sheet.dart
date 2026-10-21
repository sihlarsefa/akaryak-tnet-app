import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../application/server_gate_controller.dart';
import '../../copy.dart';
import 'support_contacts.dart';

/// "Hesabım yok" (spec A.4 A1): hesapları bayi ya da şirket yöneticisi açar; destek kanalları
/// `app/config.support` üzerinden.
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
      children: [
        Text(AuthCopy.noAccountBody, style: t.body),
        const SizedBox(height: 16),
        const _Point(
          icon: Icons.storefront_rounded,
          text: AuthCopy.noAccountCustomer,
        ),
        const SizedBox(height: 10),
        const _Point(icon: Icons.badge_outlined, text: AuthCopy.noAccountBayi),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            AuthCopy.supportTitle,
            style: t.bodyStrong.copyWith(color: c.ink),
          ),
        ),
        const SizedBox(height: 8),
        SupportContacts(links: links, mailSubject: AuthCopy.supportMailSubject),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AknIconBox(icon: icon, tone: AknTone.brand, size: 32),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: t.bodySmall)),
      ],
    );
  }
}
