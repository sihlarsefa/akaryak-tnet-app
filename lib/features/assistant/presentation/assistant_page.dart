import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../profile/api.dart';
import '../application/assistant_chat_controller.dart';
import '../application/assistant_gate.dart';
import '../copy.dart';
import 'chat_view.dart';
import 'disclosure_view.dart';

/// Asistan (`/assistant`, spec A.6): onay yoksa yalnızca tam ekran aydınlatma metni; onay varsa sohbet.
/// Sunucu 503 derse "kullanılamıyor" durumu (girişler de gizlenir). Üstte kapat (tam ekran açıldıysa),
/// "Destek ile görüş" ve "Yeni sohbet".
class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  @override
  void initState() {
    super.initState();
    // Aydınlatma metni sürümü değiştiyse onay yeniden istenir (spec A.6).
    Future.microtask(
      () => ref.read(assistantGateProvider.notifier).revalidate(),
    );
  }

  void _close(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(assistantGateProvider);
    final canPop = Navigator.of(context).canPop();
    final hasMessages = ref.watch(
      assistantChatProvider.select((s) => s.messages.isNotEmpty),
    );
    final Widget body = switch (gate) {
      GateChecking() => const LoadingView(),
      GateNeedsConsent() => DisclosureView(
        gate: gate,
        onDecline: () => _close(context),
      ),
      GateReady() => ChatView(gate: gate),
      GateDisabled(:final message) => _Centered(
        child: EmptyState(
          title: AssistantCopy.disabledTitle,
          message: '$message ${AssistantCopy.disabledBody}',
          illustration: AknIllustration.inbox,
          actionLabel: AssistantCopy.support,
          onAction: () => unawaited(showSupportSheet(context)),
        ),
      ),
      GateError(:final failure) => _Centered(
        child: failure is OfflineFailure
            ? ErrorState(
                offline: true,
                title: AssistantCopy.offlineTitle,
                message: AssistantCopy.offlineBody,
                onRetry: () => unawaited(
                  ref.read(assistantGateProvider.notifier).recheck(),
                ),
              )
            : ErrorState(
                title: AssistantCopy.errorTitle,
                message: failure.message,
                onRetry: () => unawaited(
                  ref.read(assistantGateProvider.notifier).recheck(),
                ),
              ),
      ),
    };
    return AppScaffold(
      title: AssistantCopy.title,
      subtitle: AssistantCopy.subtitle,
      showBell: false,
      automaticallyImplyLeading: false,
      leading: canPop
          ? AknIconButton(
              icon: Icons.close_rounded,
              semanticLabel: AssistantCopy.close,
              onPressed: () => _close(context),
            )
          : null,
      actions: [
        AknIconButton(
          icon: Icons.support_agent_outlined,
          semanticLabel: AssistantCopy.support,
          onPressed: () => unawaited(showSupportSheet(context)),
        ),
        if (gate is GateReady && hasMessages)
          AknIconButton(
            icon: Icons.add_comment_outlined,
            semanticLabel: AssistantCopy.newChat,
            onPressed: () => ref.read(assistantChatProvider.notifier).clear(),
          ),
      ],
      body: AnimatedSwitcher(
        duration: AknMotion.of(context, AknMotion.base),
        switchInCurve: AknMotion.standard,
        child: KeyedSubtree(key: ValueKey(gate.runtimeType), child: body),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Center(child: SingleChildScrollView(child: child));
}
