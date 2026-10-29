import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/dispatch_controller.dart';
import '../../data/dispatch_models.dart';
import '../widgets/bayi_widgets.dart';

/// Şoför seçimi: uygulama hesabı ([account]) ya da hesabı olmayan şoförün adı ([name]).
@immutable
class DriverChoice {
  const DriverChoice.account(StationDriver this.account) : name = null;
  const DriverChoice.manual(String this.name) : account = null;

  final StationDriver? account;
  final String? name;

  String get displayName => account?.displayName ?? name ?? '';
  bool get isAccount => account != null;
}

/// Şoför seçim sayfası (spec A.4 "driver picker"): telefon, "uygulamada" rozeti, açık sevkiyat sayısı;
/// [allowManual] ile hesabı olmayan şoför adı da yazılabilir (yalnızca planlamada).
Future<DriverChoice?> showDriverPicker(
  BuildContext context, {
  DriverChoice? selected,
  bool allowManual = true,
  String title = 'Şoför seçin',
}) => showAppSheet<DriverChoice>(
  context: context,
  title: title,
  subtitle: 'Uygulamayı kullanan şoför teslimatı kendi telefonundan yönetir.',
  builder: (_) => _DriverPicker(selected: selected, allowManual: allowManual),
);

class _DriverPicker extends ConsumerStatefulWidget {
  const _DriverPicker({this.selected, required this.allowManual});

  final DriverChoice? selected;
  final bool allowManual;

  @override
  ConsumerState<_DriverPicker> createState() => _DriverPickerState();
}

class _DriverPickerState extends ConsumerState<_DriverPicker> {
  String _query = '';
  late final TextEditingController _manual = TextEditingController(
    text: widget.selected?.name ?? '',
  );

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _pick(DriverChoice c) => Navigator.of(context).pop(c);

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final drivers = ref.watch(stationDriversProvider);
    final suggestions = ref.watch(boardSuggestionsProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SearchField(
          hint: 'Ad ya da telefon',
          onChanged: (q) => setState(() => _query = q),
        ),
        const SizedBox(height: 12),
        drivers.when(
          loading: () => const SkeletonList(
            itemCount: 3,
            leading: true,
            padding: EdgeInsets.zero,
            shrinkWrap: true,
          ),
          error: (e, _) => FailureView(
            failure: AppFailure.from(e),
            compact: true,
            onRetry: () => ref.invalidate(stationDriversProvider),
          ),
          data: (list) {
            final rows = [
              for (final d in list)
                if (TurkishText.matches(d.displayName, _query) ||
                    TurkishText.matches(d.phone, _query))
                  d,
            ];
            if (rows.isEmpty) {
              return EmptyState(
                compact: true,
                title: list.isEmpty ? 'Şoför hesabı yok' : 'Eşleşen şoför yok',
                message: list.isEmpty
                    ? 'Bayinizde Şoför rolüyle tanımlı personel bulunmuyor.'
                    : 'Adı ya da telefon numarasını kontrol edin.',
                illustration: AknIllustration.search,
              );
            }
            // Şoförler art arda süzülerek gelir.
            return StaggerScope(
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    StaggerItem(
                      index: i,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 1,
                              indent: 64,
                              color: context.akn.lineSoft,
                            ),
                          DriverPickerRow(
                            driver: rows[i],
                            selected:
                                widget.selected?.account?.userId ==
                                rows[i].userId,
                            onTap: () => _pick(DriverChoice.account(rows[i])),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (widget.allowManual) ...[
          const SizedBox(height: 20),
          Text(
            'Uygulama hesabı olmayan şoför',
            style: t.bodyStrong.copyWith(color: context.akn.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'Bu şoförün teslimatlarını yola çıkar ve teslim bildir ile siz yönetirsiniz.',
            style: t.bodySmall.copyWith(color: context.akn.dim),
          ),
          const SizedBox(height: 8),
          AknTextField(
            controller: _manual,
            label: 'Şoför adı',
            textCapitalization: TextCapitalization.words,
            maxLength: 150,
            onChanged: (_) => setState(() {}),
          ),
          if (suggestions != null && suggestions.drivers.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final s in suggestions.drivers.take(6))
                  AknChip(
                    label: s.value,
                    selected: _manual.text.trim() == s.value,
                    onTap: () => setState(() => _manual.text = s.value),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          AknButton.secondary(
            label: 'Bu adla devam et',
            expand: true,
            onPressed: _manual.text.trim().length < 2
                ? null
                : () => _pick(DriverChoice.manual(_manual.text.trim())),
          ),
        ],
      ],
    );
  }
}

/// Şoför satırı (tasarım v3): baş harf yuvarlağı, ad, telefon; açık sevkiyat yükü küçük bir yük
/// çubuğu olarak (dilimler sırayla dolar); rol ("Şoför" / "Personel") ve "uygulamada" çipi; seçili
/// satır turuncu yumuşak zeminde, Pas onay işaretiyle. Basınca Beton zemin ve hafif küçülme.
class DriverPickerRow extends StatelessWidget {
  const DriverPickerRow({
    super.key,
    required this.driver,
    required this.selected,
    required this.onTap,
  });

  final StationDriver driver;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = driver;
    final t = context.aknText;
    final c = context.akn;
    final load = d.activeShipments == 0
        ? 'Açık sevkiyatı yok'
        : '${d.activeShipments} açık sevkiyat';
    final semantic = [
      d.displayName,
      if (d.phone != null) Fmt.phone(d.phone),
      load,
      d.isDriverRole ? 'Şoför' : 'Personel',
      if (d.hasActiveDevice) 'uygulamada',
      if (selected) 'seçili',
    ].join(', ');
    return Semantics(
      button: true,
      selected: selected,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: PressScale(
        child: InkWell(
          onTap: () {
            AknHaptics.selection();
            onTap();
          },
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceAlt,
          borderRadius: BorderRadius.circular(AknRadius.md),
          child: AnimatedContainer(
            duration: AknMotion.of(context, AknMotion.base),
            curve: AknMotion.standard,
            decoration: BoxDecoration(
              color: selected ? c.brandSoft : c.brandSoft.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(AknRadius.md),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AknAvatar(name: d.displayName, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            d.displayName,
                            style: t.headline.copyWith(color: c.ink),
                          ),
                          Text(
                            d.isDriverRole ? 'Şoför' : 'Personel',
                            style: t.label.copyWith(color: c.dim),
                          ),
                        ],
                      ),
                      if (d.phone != null)
                        Text(
                          Fmt.phone(d.phone),
                          style: t.bodySmall.copyWith(color: c.dim),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _LoadBar(count: d.activeShipments),
                          Text(load, style: t.label.copyWith(color: c.ink)),
                          if (d.hasActiveDevice) const InAppBadge(),
                        ],
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: FadeUp(
                      offset: 0,
                      scale: 0.4,
                      curve: AknMotion.pop,
                      child: Icon(
                        PhosphorIconsFill.checkCircle,
                        size: 24,
                        color: c.brandInk,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Şoförün açık sevkiyat yükü: 4 dilimli küçük çubuk (her açık sevkiyat bir mürekkep dilim).
class _LoadBar extends StatelessWidget {
  const _LoadBar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    const slots = 4;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < slots; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            // Dolu dilimler sırayla belirir.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: i < count ? 1 : 0),
              duration: AknMotion.of(
                context,
                Duration(milliseconds: 260 + 90 * i),
              ),
              curve: AknMotion.standard,
              builder: (context, v, _) => Container(
                width: 14,
                height: 6,
                decoration: BoxDecoration(
                  color: Color.lerp(c.chartTrack, c.ink, v),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
