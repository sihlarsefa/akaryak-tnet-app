import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/models/json.dart';
import '../../../core/offline/cache_store.dart';

/// `app/config` içinde çekirdek modelin taşımadığı alanlar (spec B.3 revizyon 2): sunucu derlemesi,
/// sözleşme sürümü, destek sayfası ve hesap silme sayfası. Son kaydedilen ham yanıttan okunur; yoksa
/// boş (ekranlar yedek adresleri kullanır).
@immutable
class ConfigExtras {
  const ConfigExtras({
    this.apiBuild,
    this.contractVersion,
    this.supportUrl,
    this.accountDeletionUrl,
  });

  final String? apiBuild;
  final String? contractVersion;
  final String? supportUrl;
  final String? accountDeletionUrl;
}

final configExtrasProvider = FutureProvider.autoDispose<ConfigExtras>((
  ref,
) async {
  ref.watch(appConfigProvider);
  try {
    final e = await ref.read(cacheStoreProvider).read(CacheKeys.appConfig);
    final r = JsonReader.of(e?.value);
    return ConfigExtras(
      apiBuild: r.nonEmpty('apiBuild'),
      contractVersion: r.nonEmpty('contractVersion'),
      supportUrl: r.obj('support').nonEmpty('url'),
      accountDeletionUrl: r.obj('legal').nonEmpty('accountDeletionUrl'),
    );
  } catch (_) {
    return const ConfigExtras();
  }
});
