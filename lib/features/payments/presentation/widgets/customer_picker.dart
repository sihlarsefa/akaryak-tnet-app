import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../application/payments_providers.dart';
import '../../data/payment_models.dart';

/// Cari seçimi sonucu.
sealed class CustomerPick {
  const CustomerPick();
}

final class CustomerPicked extends CustomerPick {
  const CustomerPicked(this.customer);
  final CustomerOption customer;
}

/// "Tüm cariler" (süzgeç kalkar).
final class CustomerCleared extends CustomerPick {
  const CustomerCleared();
}

/// Cari süzgeci sayfası (bayinin carileri, aramalı). Vazgeçilirse null.
Future<CustomerPick?> showCustomerPicker(
  BuildContext context, {
  CustomerOption? current,
}) => showAppSheet<CustomerPick>(
  context: context,
  title: 'Cari seçin',
  scrollable: false,
  builder: (_) => _CustomerPicker(current: current),
);

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker({this.current});

  final CustomerOption? current;

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(paymentCustomersProvider(_q));
    final t = context.aknText;
    final c = context.akn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(
          hint: 'Cari ünvanı ara',
          autofocus: false,
          onChanged: (q) => setState(() => _q = q.trim()),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: async.when(
            loading: () => const SizedBox(height: 120, child: LoadingView()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                AppFailure.from(e) is ForbiddenFailure
                    ? 'Cari listesini görme yetkiniz yok. Aramayla süzebilirsiniz.'
                    : 'Cariler yüklenemedi. Bağlantınızı kontrol edip sayfayı yeniden açın.',
                style: t.bodySmall.copyWith(color: c.dim),
                textAlign: TextAlign.center,
              ),
            ),
            data: (list) {
              const pad = EdgeInsets.symmetric(vertical: 10);
              // Seçili cari: Pas onay işareti "pop" ile belirir.
              Widget check(bool on) => on
                  ? FadeUp(
                      offset: 0,
                      scale: 0.4,
                      curve: AknMotion.pop,
                      child: Icon(
                        PhosphorIconsFill.checkCircle,
                        color: c.brandInk,
                        size: 22,
                      ),
                    )
                  : const SizedBox(width: 22);
              final rows = <Widget>[
                AknListTile(
                  leadingIcon: PhosphorIconsRegular.usersThree,
                  title: 'Tüm cariler',
                  padding: pad,
                  trailing: check(widget.current == null),
                  onTap: () =>
                      Navigator.of(context).pop(const CustomerCleared()),
                ),
                for (final o in list)
                  AknListTile(
                    leading: AknAvatar(name: o.title, size: 36),
                    title: o.title,
                    subtitle: o.city,
                    padding: pad,
                    trailing: check(widget.current == o),
                    onTap: () => Navigator.of(context).pop(CustomerPicked(o)),
                  ),
              ];
              return StaggerScope(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      StaggerItem(
                        index: i,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (i > 0) const AknLedgerDivider(indent: 0),
                            rows[i],
                          ],
                        ),
                      ),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Aramaya uyan cari yok. Ünvanın bir bölümünü yazmayı deneyin.',
                          style: t.bodySmall.copyWith(color: c.dim),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
