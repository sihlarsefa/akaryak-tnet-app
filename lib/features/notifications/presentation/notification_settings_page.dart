import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/push/push_service.dart';
import '../../../core/push/unread_count_provider.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/log.dart';
import '../application/preferences_controller.dart';
import '../copy.dart';
import '../data/notification_models.dart';

/// Bu cihazın bildirim izni (testler ezer).
final pushPermissionProvider = FutureProvider.autoDispose<PushPermission>(
  (ref) => ref.watch(pushServiceProvider).permission(),
);

/// Bildirim ayarları (spec A.4 A8 "preferences per category"; tasarım v3): cihaz izni, kategori
/// anahtarları (`PUT notifications/preferences`) simge karolu beyaz bir kartta (açık kategorinin karosu
/// turuncuya döner), test bildirimi. Bölümler açılışta sırayla belirir.
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(preferencesControllerProvider);
    // Tümü bir kez kurulur (kısa sayfa): açılıştaki sıralı giriş bir kez oynar, kaydırınca yeni bölüm
    // doğmaz.
    return AppScaffold(
      title: NotificationsCopy.settingsTitle,
      showBell: false,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Reveal(
              index: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AknSpace.page,
                  8,
                  AknSpace.page,
                  0,
                ),
                child: _DevicePushCard(),
              ),
            ),
            _Reveal(
              index: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(
                    title: NotificationsCopy.categoriesTitle,
                    subtitle: NotificationsCopy.categoriesHint,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AknSpace.page,
                    ),
                    child: _Categories(state: s),
                  ),
                ],
              ),
            ),
            const _Reveal(
              index: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title: NotificationsCopy.testTitle),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: AknSpace.page),
                    child: _TestCard(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Categories extends ConsumerWidget {
  const _Categories({required this.state});

  final PreferencesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final ctl = ref.read(preferencesControllerProvider.notifier);
    if (s.loading && s.items.isEmpty) {
      return const Shimmer(
        child: SkeletonCard(lines: 4, margin: EdgeInsets.zero),
      );
    }
    final error = s.error;
    if (error != null && s.items.isEmpty) {
      return AknCard(
        child: ErrorState(
          compact: true,
          offline: error is OfflineFailure,
          title: NotificationsCopy.prefsError,
          message: error is OfflineFailure ? null : error.message,
          onRetry: () => unawaited(ctl.reload()),
        ),
      );
    }
    final c = context.akn;
    return AknCard(
      padding: EdgeInsets.zero,
      radius: 20,
      child: ClipRRect(
        borderRadius: AknRadius.card,
        child: Column(
          children: [
            for (var i = 0; i < s.items.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 66),
                  child: Divider(height: 1, thickness: 1, color: c.lineSoft),
                ),
              _PrefTile(
                pref: s.items[i],
                busy: s.saving.contains(s.items[i].category),
                onChanged: (v) async {
                  final f = await ctl.toggle(s.items[i].category, v);
                  if (f != null) {
                    AppToast.error(
                      f is OfflineFailure
                          ? f.message
                          : NotificationsCopy.prefsSaveFailed,
                    );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrefTile extends StatelessWidget {
  const _PrefTile({
    required this.pref,
    required this.busy,
    required this.onChanged,
  });

  final NotificationPreference pref;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final description = NotificationCategory.description(pref.category);
    final on = pref.pushEnabled;
    return MergeSemantics(
      child: InkWell(
        onTap: busy
            ? null
            : () {
                AknHaptics.selection();
                onChanged(!on);
              },
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              // Açık kategorinin karosu yumuşak turuncu (renk geçişi yumuşak).
              ExcludeSemantics(
                child: AnimatedContainer(
                  duration: AknMotion.of(context, AknMotion.base),
                  curve: AknMotion.standard,
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: on ? c.brandSoft : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    NotificationCategory.icon(pref.category),
                    size: 20,
                    color: on ? c.brandInk : c.dim,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pref.label,
                      style: t.bodyStrong.copyWith(color: c.ink),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: t.bodySmall.copyWith(color: c.dim),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: pref.pushEnabled,
                onChanged: busy ? null : onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cihazın bildirim izni ve sunucunun push durumu.
class _DevicePushCard extends ConsumerWidget {
  const _DevicePushCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebase = ref.watch(firebaseAvailableProvider);
    final serverPush = ref.watch(
      appConfigProvider.select((c) => c.features.push),
    );
    if (!firebase || !serverPush) {
      return const AknBanner(
        tone: AknTone.info,
        icon: PhosphorIconsRegular.bellZ,
        title: NotificationsCopy.pushOffTitle,
        message: NotificationsCopy.pushOffMessage,
      );
    }
    final permission = ref.watch(pushPermissionProvider).valueOrNull;
    return switch (permission) {
      PushPermission.granted => const AknBanner(
        tone: AknTone.ok,
        icon: PhosphorIconsRegular.bellRinging,
        title: NotificationsCopy.pushOnTitle,
        message: NotificationsCopy.pushOnMessage,
      ),
      PushPermission.notDetermined => AknBanner(
        tone: AknTone.info,
        icon: PhosphorIconsRegular.bell,
        title: NotificationsCopy.pushAskTitle,
        message: NotificationsCopy.pushAskMessage,
        actionLabel: NotificationsCopy.pushAsk,
        onAction: () => unawaited(_ask(ref)),
      ),
      PushPermission.denied => AknBanner(
        tone: AknTone.warn,
        icon: PhosphorIconsRegular.bellSlash,
        title: NotificationsCopy.pushDeniedTitle,
        message: NotificationsCopy.pushDeniedMessage,
        actionLabel: NotificationsCopy.openSettings,
        onAction: () => unawaited(_openSettings()),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  static Future<void> _ask(WidgetRef ref) async {
    final push = ref.read(pushServiceProvider);
    final granted = await push.requestPermission();
    ref.invalidate(pushPermissionProvider);
    if (!granted) return;
    try {
      final token = await push.token();
      await ref
          .read(authRepositoryProvider)
          .registerDevice(pushToken: token, pushEnabled: token != null);
    } catch (e) {
      AppLog.debug('Cihaz kaydı güncellenemedi: $e');
    }
  }

  static Future<void> _openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      AppLog.debug('Ayarlar açılamadı: $e');
    }
  }
}

class _TestCard extends ConsumerStatefulWidget {
  const _TestCard();

  @override
  ConsumerState<_TestCard> createState() => _TestCardState();
}

class _TestCardState extends ConsumerState<_TestCard> {
  String? _result;
  AknTone _tone = AknTone.ok;

  Future<void> _send() async {
    try {
      final r = await ref
          .read(preferencesControllerProvider.notifier)
          .sendTest();
      if (!mounted) return;
      setState(() {
        _tone = r.sent > 0 ? AknTone.ok : AknTone.info;
        _result = r.sent > 0
            ? NotificationsCopy.testSent(r.sent)
            : NotificationsCopy.testInboxOnly;
      });
      unawaited(ref.read(unreadCountProvider.notifier).refresh());
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _tone = AknTone.warn;
        _result = f.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final result = _result;
    final c = context.akn;
    return AknCard(
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    PhosphorIconsRegular.bellRinging,
                    size: 20,
                    color: c.brandInk,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NotificationsCopy.testTile,
                      style: t.bodyStrong.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      NotificationsCopy.testHint,
                      style: t.bodySmall.copyWith(color: c.dim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Genişletilmiş: çekirdek AknButton'ın daraltılmış hâli eşzamansız işlemde
          // (genişliği sınırsız) kısıt geçişinde hata verir.
          AknButton.secondary(
            label: NotificationsCopy.testSend,
            icon: PhosphorIconsRegular.paperPlaneRight,
            expand: true,
            showSuccess: false,
            onPressedAsync: _send,
          ),
          AknAnimatedSize(
            alignment: Alignment.topCenter,
            child: result == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AknBanner(tone: _tone, message: result),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Bir bölümün tek seferlik girişi (tasarım v3 §5): [index] × 45 ms sonra 18 px aşağıdan kayarak gelir;
/// opaklık hızla, kayma uzun ve yumuşak tamamlanır. Ölçek yok; yapısı sabit. Azaltılmış harekette doğrudan.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  static final _move = CurveTween(curve: AknMotion.emphasizedCurve);
  static final _fade = CurveTween(
    curve: const Interval(0, 0.4, curve: Curves.easeOut),
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
      return;
    }
    _timer = Timer(Duration(milliseconds: 45 * widget.index), () {
      if (mounted) unawaited(_c.forward());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _fade.evaluate(_c),
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - _move.evaluate(_c))),
        child: child,
      ),
    ),
  );
}
