import 'package:flutter/foundation.dart';

import 'json.dart';

/// Sunucunun açtığı özellikler (`AppConfigDto.features`).
@immutable
class AppFeatures {
  const AppFeatures({
    this.otpLogin = false,
    this.assistant = false,
    this.weather = false,
    this.payments = true,
    this.push = false,
    this.orderExpiry = false,
    this.deliveryPhotoRequired = false,
    this.deliverySignatureRequired = false,
    this.deliveryGpsRequired = false,
  });

  factory AppFeatures.fromJson(JsonReader r) => AppFeatures(
    otpLogin: r.boolean('otpLogin'),
    assistant: r.boolean('assistant'),
    weather: r.boolean('weather'),
    payments: r.boolean('payments', true),
    push: r.boolean('push'),
    orderExpiry: r.boolean('orderExpiry'),
    deliveryPhotoRequired: r.boolean('deliveryPhotoRequired'),
    deliverySignatureRequired: r.boolean('deliverySignatureRequired'),
    deliveryGpsRequired: r.boolean('deliveryGpsRequired'),
  );

  /// "Telefonla giriş" sekmesi.
  final bool otpLogin;

  /// Asistan sekmesi ve ana sayfa düğmesi.
  final bool assistant;

  /// Hava durumu kartları.
  final bool weather;

  /// Ödeme yöntemi seçimi.
  final bool payments;

  /// Sunucuda push gönderimi açık.
  final bool push;

  /// Teklif süre dolumu açık: geri sayım ve "gün sonunda kapanır" metni (spec A.4 A2).
  final bool orderExpiry;
  final bool deliveryPhotoRequired;
  final bool deliverySignatureRequired;
  final bool deliveryGpsRequired;

  JsonMap toJson() => {
    'otpLogin': otpLogin,
    'assistant': assistant,
    'weather': weather,
    'payments': payments,
    'push': push,
    'orderExpiry': orderExpiry,
    'deliveryPhotoRequired': deliveryPhotoRequired,
    'deliverySignatureRequired': deliverySignatureRequired,
    'deliveryGpsRequired': deliveryGpsRequired,
  };
}

/// Destek kanalları.
@immutable
class SupportInfo {
  const SupportInfo({this.phone, this.whatsapp, this.email, this.url});

  factory SupportInfo.fromJson(JsonReader r) => SupportInfo(
    phone: r.nonEmpty('phone'),
    whatsapp: r.nonEmpty('whatsapp'),
    email: r.nonEmpty('email'),
    url: r.nonEmpty('url'),
  );

  final String? phone;
  final String? whatsapp;
  final String? email;

  /// Destek sayfası (API'nin `/legal/support` sayfası).
  final String? url;

  bool get isEmpty =>
      phone == null && whatsapp == null && email == null && url == null;

  JsonMap toJson() => {
    'phone': phone,
    'whatsapp': whatsapp,
    'email': email,
    'url': url,
  };
}

/// Yasal metin bağlantıları.
@immutable
class LegalLinks {
  const LegalLinks({
    this.privacyUrl,
    this.kvkkUrl,
    this.termsUrl,
    this.accountDeletionUrl,
  });

  factory LegalLinks.fromJson(JsonReader r) => LegalLinks(
    privacyUrl: r.nonEmpty('privacyUrl'),
    kvkkUrl: r.nonEmpty('kvkkUrl'),
    termsUrl: r.nonEmpty('termsUrl'),
    accountDeletionUrl: r.nonEmpty('accountDeletionUrl'),
  );

  final String? privacyUrl;
  final String? kvkkUrl;
  final String? termsUrl;

  /// Hesap silme bilgi sayfası (mağaza kuralı).
  final String? accountDeletionUrl;

  JsonMap toJson() => {
    'privacyUrl': privacyUrl,
    'kvkkUrl': kvkkUrl,
    'termsUrl': termsUrl,
    'accountDeletionUrl': accountDeletionUrl,
  };
}

/// Bakım bildirimi (`Maintenance:Active` / `Maintenance:Message`).
@immutable
class MaintenanceInfo {
  const MaintenanceInfo({this.active = false, this.message});

  factory MaintenanceInfo.fromJson(JsonReader r) => MaintenanceInfo(
    active: r.boolean('active'),
    message: r.nonEmpty('message'),
  );

  final bool active;

  /// Sunucunun Türkçe metni (boşsa uygulamanın varsayılanı).
  final String? message;

  JsonMap toJson() => {'active': active, 'message': message};
}

/// `GET app/config?platform=` (anonim; spec B.3 `AppConfigDto`).
@immutable
class AppConfig {
  const AppConfig({
    this.minBuild = 1,
    this.latestBuild = 1,
    this.storeUrl,
    this.updateTitle,
    this.updateMessage,
    this.features = const AppFeatures(),
    this.support = const SupportInfo(),
    this.legal = const LegalLinks(),
    this.leadKvkkVersion,
    this.assistantConsentVersion,
    this.maintenance = const MaintenanceInfo(),
    this.apiBuild,
    this.contractVersion,
    this.serverTimeUtc,
    this.fromCache = false,
  });

  /// Uygulamanın konuştuğu sözleşme (`AppConfigDto.contractVersion`, `/health/ready` "contract").
  static const expectedContract = 'mobile-v1';

  /// Sunucuya hiç ulaşılamadığında kullanılan güvenli varsayılan (özellikler kapalı).
  static const fallback = AppConfig(fromCache: true);

  factory AppConfig.fromJson(Object? json, {bool fromCache = false}) {
    final r = JsonReader.of(json);
    return AppConfig(
      minBuild: r.integer('minBuild', 1),
      latestBuild: r.integer('latestBuild', 1),
      storeUrl: r.nonEmpty('storeUrl'),
      updateTitle: r.nonEmpty('updateTitle'),
      updateMessage: r.nonEmpty('updateMessage'),
      features: AppFeatures.fromJson(r.obj('features')),
      support: SupportInfo.fromJson(r.obj('support')),
      legal: LegalLinks.fromJson(r.obj('legal')),
      leadKvkkVersion: r.nonEmpty('leadKvkkVersion'),
      assistantConsentVersion: r.nonEmpty('assistantConsentVersion'),
      maintenance: MaintenanceInfo.fromJson(r.obj('maintenance')),
      apiBuild: r.nonEmpty('apiBuild'),
      contractVersion: r.nonEmpty('contractVersion'),
      serverTimeUtc: r.dateUtc('serverTimeUtc'),
      fromCache: fromCache,
    );
  }

  final int minBuild;
  final int latestBuild;
  final String? storeUrl;
  final String? updateTitle;
  final String? updateMessage;
  final AppFeatures features;
  final SupportInfo support;
  final LegalLinks legal;
  final String? leadKvkkVersion;

  /// Asistan aydınlatma metninin sürümü (değişince onay yeniden istenir).
  final String? assistantConsentVersion;
  final MaintenanceInfo maintenance;

  /// Sunucu derlemesi (tanılama; Profil → Hakkında).
  final String? apiBuild;

  /// Sözleşme sürümü; boşsa (eski sahte yanıtlar) uyumlu sayılır.
  final String? contractVersion;
  final DateTime? serverTimeUtc;

  /// Sunucudan değil önbellekten / varsayılandan geldi.
  final bool fromCache;

  /// Bu derleme zorunlu güncelleme gerektiriyor mu.
  bool requiresUpdate(int build) => build > 0 && build < minBuild;

  /// İsteğe bağlı güncelleme var mı.
  bool hasOptionalUpdate(int build) =>
      build > 0 && build >= minBuild && build < latestBuild;

  /// Sunucu bu uygulamanın sözleşmesini konuşuyor mu.
  bool get contractMatches =>
      contractVersion == null || contractVersion == expectedContract;

  AppConfig copyWith({int? minBuild, int? latestBuild, bool? fromCache}) =>
      AppConfig(
        minBuild: minBuild ?? this.minBuild,
        latestBuild: latestBuild ?? this.latestBuild,
        storeUrl: storeUrl,
        updateTitle: updateTitle,
        updateMessage: updateMessage,
        features: features,
        support: support,
        legal: legal,
        leadKvkkVersion: leadKvkkVersion,
        assistantConsentVersion: assistantConsentVersion,
        maintenance: maintenance,
        apiBuild: apiBuild,
        contractVersion: contractVersion,
        serverTimeUtc: serverTimeUtc,
        fromCache: fromCache ?? this.fromCache,
      );

  JsonMap toJson() => {
    'minBuild': minBuild,
    'latestBuild': latestBuild,
    'storeUrl': storeUrl,
    'updateTitle': updateTitle,
    'updateMessage': updateMessage,
    'features': features.toJson(),
    'support': support.toJson(),
    'legal': legal.toJson(),
    'leadKvkkVersion': leadKvkkVersion,
    'assistantConsentVersion': assistantConsentVersion,
    'maintenance': maintenance.toJson(),
    'apiBuild': apiBuild,
    'contractVersion': contractVersion,
    'serverTimeUtc': serverTimeUtc?.toIso8601String(),
  };
}
