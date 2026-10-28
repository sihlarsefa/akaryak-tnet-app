import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_number.dart';
import '../../application/cm_access.dart';
import '../../application/delivery_points_controller.dart';
import '../../copy.dart';
import '../../data/delivery_point.dart';
import '../../data/turkey_locations.dart';
import '../../data/window_time.dart';
import '../cm_widgets.dart';
import 'location_section.dart';
import 'search_picker.dart';

/// Teslimat noktası ekle / düzenle (`POST|PUT customers/me/delivery-points`). İl / ilçe listeden seçilir,
/// teslim saatleri `TimeSpan` olarak gider (24:00 = `1.00:00:00`), konum isteğe bağlıdır.
class DeliveryPointEditPage extends ConsumerWidget {
  const DeliveryPointEditPage({super.key, this.pointId});

  /// Boşsa yeni nokta.
  final int? pointId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = pointId;
    if (id == null) return const _EditForm(initial: null);
    final fromList = ref
        .watch(deliveryPointsControllerProvider)
        .points
        .where((p) => p.id == id)
        .firstOrNull;
    if (fromList != null) return _EditForm(initial: fromList);
    final async = ref.watch(deliveryPointProvider(id));
    return async.when(
      data: (p) => _EditForm(initial: p),
      loading: () => const AppScaffold(
        title: 'Teslimat noktası',
        body: LoadingView(message: 'Yükleniyor'),
      ),
      error: (e, _) => AppScaffold(
        title: 'Teslimat noktası',
        body: CmFailureView(
          failure: AppFailure.from(e),
          onRetry: () => ref.invalidate(deliveryPointProvider(id)),
        ),
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.initial});

  final DeliveryPoint? initial;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final DeliveryPointDraft _original = widget.initial == null
      ? const DeliveryPointDraft()
      : DeliveryPointDraft.of(widget.initial!);

  late final _name = TextEditingController(text: _original.name);
  late final _address = TextEditingController(text: _original.address);
  late final _contactName = TextEditingController(
    text: _original.contactName ?? '',
  );
  late final _contactPhone = TextEditingController(
    text: _original.contactPhone ?? '',
  );
  late final _notes = TextEditingController(text: _original.accessNotes ?? '');
  late final _tank = TextEditingController(
    text: _original.tankCapacityLiters == null
        ? ''
        : Fmt.number(_original.tankCapacityLiters, maxFraction: 3),
  );
  late String _city = _original.city;
  late String _district = _original.district;
  late WindowTime? _start = _original.windowStart;
  late WindowTime? _end = _original.windowEnd;
  late PickedLocation? _location =
      _original.latitude == null || _original.longitude == null
      ? null
      : PickedLocation(_original.latitude!, _original.longitude!);

  final _form = GlobalKey<FormState>();
  bool _saving = false;
  bool _submitted = false;
  String? _error;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    for (final c in [
      _name,
      _address,
      _contactName,
      _contactPhone,
      _notes,
      _tank,
    ]) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _contactName,
      _contactPhone,
      _notes,
      _tank,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  DeliveryPointDraft get _draft => DeliveryPointDraft(
    id: widget.initial?.id ?? 0,
    name: _name.text,
    city: _city,
    district: _district,
    address: _address.text,
    latitude: _location?.latitude,
    longitude: _location?.longitude,
    contactName: _contactName.text,
    contactPhone: _contactPhone.text,
    windowStart: _start,
    windowEnd: _end,
    tankCapacityLiters: TrNumber.parse(_tank.text),
    accessNotes: _notes.text,
  );

  bool get _dirty {
    final a = _draft.toJson();
    final b = _original.toJson();
    return a.toString() != b.toString();
  }

  Future<void> _pickCity() async {
    final v = await showSearchPicker(
      context,
      title: 'İl seçin',
      options: turkeyProvinces,
      selected: _city.isEmpty ? null : _city,
      hint: 'İl ara',
    );
    if (v == null || v == _city) return;
    setState(() {
      _city = v;
      final districts = turkeyDistrictsByProvince[v] ?? const <String>[];
      if (!districts.contains(_district)) _district = '';
    });
  }

  Future<void> _pickDistrict() async {
    final options = turkeyDistrictsByProvince[_city] ?? const <String>[];
    final v = await showSearchPicker(
      context,
      title: _city.isEmpty ? 'İlçe seçin' : '$_city, ilçe seçin',
      options: options,
      selected: _district.isEmpty ? null : _district,
      allowCustom: true,
      hint: 'İlçe ara',
    );
    if (v != null) setState(() => _district = v);
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final initial = current == null || current.isEndOfDay
        ? TimeOfDay(hour: start ? 8 : 18, minute: 0)
        : TimeOfDay(hour: current.hour, minute: current.minute);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: start ? 'Kabul başlangıcı' : 'Kabul bitişi',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final v = WindowTime.hm(picked.hour, picked.minute);
    setState(() {
      if (start) {
        _start = v;
        _end ??= const WindowTime(18 * 60);
      } else {
        _end = v;
        _start ??= const WindowTime(8 * 60);
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!(_form.currentState?.validate() ?? true)) return;
    final draft = _draft;
    final error = draft.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(deliveryPointsControllerProvider.notifier).save(draft);
      if (!mounted) return;
      AknHaptics.success();
      AppToast.success(
        _isNew ? 'Teslimat noktası eklendi.' : 'Teslimat noktası kaydedildi.',
        context: context,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      final f = AppFailure.from(e);
      if (!mounted) return;
      if (f is BusinessFailure || f is ValidationFailure) {
        setState(() => _error = failureText(f));
      } else {
        showFailureToast(context, f);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deactivate() async {
    final p = widget.initial!;
    final ok = await showConfirmSheet(
      context,
      title: 'Noktayı pasifleştirelim mi?',
      message:
          '"${p.name}" yeni siparişlerde seçilemez. Geçmiş siparişler ve belgeler etkilenmez.',
      confirmLabel: 'Pasifleştir',
      destructive: true,
      icon: PhosphorIconsRegular.gpsSlash,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final message = await ref
          .read(deliveryPointsControllerProvider.notifier)
          .deactivate(p.id);
      if (!mounted) return;
      AppToast.success(message, context: context);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showFailureToast(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop(false);
      return;
    }
    final leave = await showConfirmSheet(
      context,
      title: CmCopy.unsaved,
      message: 'Çıkarsanız değişiklikler kaybolur.',
      confirmLabel: 'Çık',
      cancelLabel: 'Devam et',
      destructive: true,
    );
    if (leave && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(accessPolicyProvider);
    final online = ref.watch(isOnlineProvider);
    final t = context.aknText;
    final canEdit = _isNew ? policy.cmPointCreate : policy.cmPointEdit;
    final enabled = canEdit && !_saving;
    final windowText = windowLabel(_start, _end);
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AppScaffold(
        title: _isNew ? 'Yeni teslimat noktası' : 'Teslimat noktası',
        subtitle: _isNew ? null : widget.initial!.name,
        showBell: false,
        leading: IconButton(
          tooltip: 'Kapat',
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: _close,
        ),
        actionBar: canEdit
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!online)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        CmCopy.offlineAction,
                        style: t.caption,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  AknButton(
                    label: _isNew ? 'Noktayı ekle' : 'Kaydet',
                    expand: true,
                    loading: _saving,
                    onPressed: online && !_saving ? _save : null,
                  ),
                  if (!_isNew && policy.cmPointDelete) ...[
                    const SizedBox(height: 8),
                    AknButton.danger(
                      label: 'Pasifleştir',
                      size: AknButtonSize.medium,
                      expand: true,
                      onPressed: online && !_saving ? _deactivate : null,
                    ),
                  ],
                ],
              )
            : null,
        body: Form(
          key: _form,
          // Bölüm kartları birbiri ardına yükselerek gelir (v3 §5); hata bandı belirince kartlar
          // yeniden oynamaz (anahtarlı).
          child: CmRiseScope(
            child: ListView(
              padding: const EdgeInsets.only(top: 0, bottom: 24),
              children: [
                if (_error != null)
                  FadeUp(
                    key: const ValueKey('error'),
                    offset: 8,
                    child: AknBanner(
                      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      tone: AknTone.danger,
                      message: _error!,
                      onClose: () => setState(() => _error = null),
                    ),
                  ),
                CmRise(
                  key: const ValueKey('section-0'),
                  index: 0,
                  child: CmSection(
                    title: 'Nokta',
                    child: AknTextField(
                      controller: _name,
                      label: 'Nokta adı',
                      hint: 'ör. Pendik Lojistik Merkezi',
                      requiredMark: true,
                      enabled: enabled,
                      maxLength: DeliveryPointDraft.nameMaxLength,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Teslimat noktası adı zorunlu.'
                          : null,
                    ),
                  ),
                ),
                CmRise(
                  key: const ValueKey('section-1'),
                  index: 1,
                  child: CmSection(
                    title: 'Adres',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PickerField(
                          label: 'İl',
                          value: _city,
                          requiredMark: true,
                          enabled: enabled,
                          errorText: _submitted && _city.isEmpty
                              ? 'İl seçin.'
                              : null,
                          onTap: _pickCity,
                        ),
                        const SizedBox(height: 12),
                        PickerField(
                          label: 'İlçe',
                          value: _district,
                          requiredMark: true,
                          enabled: enabled && _city.isNotEmpty,
                          errorText: _submitted && _district.isEmpty
                              ? 'İlçe seçin.'
                              : null,
                          onTap: _pickDistrict,
                        ),
                        const SizedBox(height: 12),
                        AknTextField(
                          controller: _address,
                          label: 'Açık adres',
                          requiredMark: true,
                          enabled: enabled,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: DeliveryPointDraft.addressMaxLength,
                          keyboardType: TextInputType.streetAddress,
                          textCapitalization: TextCapitalization.sentences,
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Açık adres zorunlu.'
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                CmRise(
                  key: const ValueKey('section-2'),
                  index: 2,
                  child: CmSection(
                    title: 'Konum',
                    subtitle: 'Şoför noktayı bu konumla bulur (isteğe bağlı).',
                    child: LocationSection(
                      value: _location,
                      label: _name.text.trim().isEmpty
                          ? null
                          : _name.text.trim(),
                      enabled: enabled,
                      onChanged: (v) => setState(() => _location = v),
                    ),
                  ),
                ),
                CmRise(
                  key: const ValueKey('section-3'),
                  index: 3,
                  child: CmSection(
                    title: 'Teslim kabul saatleri',
                    subtitle: windowText ?? 'Belirtilmemiş (her saat)',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: PickerField(
                                label: 'Başlangıç',
                                value: _start?.label,
                                enabled: enabled,
                                icon: PhosphorIconsRegular.clock,
                                onTap: () => _pickTime(start: true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PickerField(
                                label: 'Bitiş',
                                value: _end?.label,
                                enabled: enabled,
                                icon: PhosphorIconsRegular.clock,
                                onTap: () => _pickTime(start: false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Gün sonuna kadar (24:00)'),
                          value: _end?.isEndOfDay ?? false,
                          onChanged: enabled
                              ? (v) => setState(() {
                                  _start ??= const WindowTime(8 * 60);
                                  _end = v
                                      ? WindowTime.endOfDay
                                      : const WindowTime(18 * 60);
                                })
                              : null,
                        ),
                        if (_start != null || _end != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AknButton.ghost(
                              label: 'Saat aralığını kaldır',
                              size: AknButtonSize.small,
                              onPressed: enabled
                                  ? () => setState(() {
                                      _start = null;
                                      _end = null;
                                    })
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                CmRise(
                  key: const ValueKey('section-4'),
                  index: 4,
                  child: CmSection(
                    title: 'Tank ve erişim',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LitersField(
                          label: 'Tank kapasitesi',
                          controller: _tank,
                          enabled: enabled,
                          min: 1,
                          max: DeliveryPointDraft.tankMax,
                          helper:
                              'Sipariş litresi tankı aşarsa sipariş ekranında uyarı gösterilir.',
                        ),
                        const SizedBox(height: 12),
                        AknTextField(
                          controller: _notes,
                          label: 'Erişim notu',
                          hint: 'ör. Ana kapıda güvenliğe plaka bildirin.',
                          enabled: enabled,
                          minLines: 2,
                          maxLines: 5,
                          maxLength: DeliveryPointDraft.accessNotesMaxLength,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ],
                    ),
                  ),
                ),
                CmRise(
                  key: const ValueKey('section-5'),
                  index: 5,
                  child: CmSection(
                    title: 'Yerinde sorumlu',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AknTextField(
                          controller: _contactName,
                          label: 'Ad soyad',
                          enabled: enabled,
                          maxLength: DeliveryPointDraft.contactNameMaxLength,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                        ),
                        const SizedBox(height: 12),
                        AknTextField(
                          controller: _contactPhone,
                          label: 'Telefon',
                          enabled: enabled,
                          maxLength: DeliveryPointDraft.contactPhoneMaxLength,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                        ),
                      ],
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
