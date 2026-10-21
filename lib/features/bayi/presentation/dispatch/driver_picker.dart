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
          loading: () => const Shimmer(
            child: Column(
              children: [
                SkeletonCard(lines: 2, margin: EdgeInsets.only(bottom: 8)),
                SkeletonCard(lines: 2, margin: EdgeInsets.only(bottom: 8)),
              ],
            ),
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
                    : null,
                illustration: AknIllustration.search,
              );
            }
            return Column(
              children: [
                for (final d in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DriverCard(
                      driver: d,
                      selected: widget.selected?.account?.userId == d.userId,
                      onTap: () => _pick(DriverChoice.account(d)),
                    ),
                  ),
              ],
            );
          },
        ),
        if (widget.allowManual) ...[
          const SizedBox(height: 12),
          Text('Uygulama hesabı olmayan şoför', style: t.bodyStrong),
          const SizedBox(height: 4),
          Text(
            'Bu şoförün teslimatlarını yola çıkar ve teslim bildir ile siz yönetirsiniz.',
            style: t.bodySmall,
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
                  ActionChip(
                    label: Text(s.value),
                    onPressed: () => setState(() => _manual.text = s.value),
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

class _DriverCard extends StatelessWidget {
  const _DriverCard({
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
    final details = [
      if (d.phone != null) Fmt.phone(d.phone),
      d.activeShipments == 0
          ? 'Açık sevkiyatı yok'
          : '${d.activeShipments} açık sevkiyat',
    ].join(' · ');
    return ChoiceCard(
      title: d.displayName,
      subtitle: details,
      selected: selected,
      tag: d.isDriverRole ? 'Şoför' : 'Personel',
      leading: AknAvatar(name: d.displayName, size: 40),
      trailing: d.hasActiveDevice ? const InAppBadge() : null,
      onTap: onTap,
    );
  }
}
