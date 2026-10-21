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
                    ? 'Cari listesini görme yetkiniz yok; aramayla süzebilirsiniz.'
                    : 'Cariler yüklenemedi.',
                style: t.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            data: (list) => ListView(
              shrinkWrap: true,
              children: [
                AknListTile(
                  leadingIcon: Icons.groups_rounded,
                  title: 'Tüm cariler',
                  trailing: widget.current == null
                      ? Icon(Icons.check_rounded, color: c.brandInk)
                      : null,
                  onTap: () =>
                      Navigator.of(context).pop(const CustomerCleared()),
                ),
                for (final o in list)
                  AknListTile(
                    leading: AknAvatar(name: o.title, size: 36),
                    title: o.title,
                    subtitle: o.city,
                    trailing: widget.current == o
                        ? Icon(Icons.check_rounded, color: c.brandInk)
                        : null,
                    onTap: () => Navigator.of(context).pop(CustomerPicked(o)),
                  ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Aramaya uyan cari yok.',
                      style: t.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
