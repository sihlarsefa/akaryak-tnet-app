import 'package:flutter/foundation.dart';

import '../../../core/env/app_env.dart';
import '../../../core/models/app_config.dart';
import '../../../core/models/json.dart';
import '../../../core/network/app_failure.dart';

/// Sunucunun uygulamayı kabul edip etmediği (spec A.4 A1 "Update" ekranı varyantları).
enum ServerGateKind {
  /// Sunucu bu sözleşmeyi konuşuyor; giriş açık.
  ok,

  /// `app/config.maintenance.active`: "Bakımdayız".
  maintenance,

  /// `app/config` 404 (eski API) ya da `contractVersion` farklı: "Sunucu güncel değil".
  outdated,

  /// Sunucuya ulaşılamadı (çevrimdışı, zaman aşımı, 5xx): engellenmez, giriş denemesi hatayı gösterir.
  unknown,
}

/// Giriş ekranındaki destek ve yasal bağlantılar (`app/config.support` ve `.legal`).
@immutable
class AuthLinks {
  const AuthLinks({
    this.supportPhone,
    this.supportWhatsapp,
    this.supportEmail,
    this.supportUrl,
    this.privacyUrl,
    this.kvkkUrl,
    this.termsUrl,
  });

  factory AuthLinks.fromConfigJson(Object? json) {
    final r = JsonReader.of(json);
    final s = r.obj('support');
    final l = r.obj('legal');
    return AuthLinks(
      supportPhone: s.nonEmpty('phone'),
      supportWhatsapp: s.nonEmpty('whatsapp'),
      supportEmail: s.nonEmpty('email'),
      supportUrl: s.nonEmpty('url'),
      privacyUrl: l.nonEmpty('privacyUrl'),
      kvkkUrl: l.nonEmpty('kvkkUrl'),
      termsUrl: l.nonEmpty('termsUrl'),
    );
  }

  /// Çekirdek [AppConfig] (önbellek ya da varsayılan) üzerinden.
  factory AuthLinks.fromConfig(AppConfig c) => AuthLinks(
    supportPhone: c.support.phone,
    supportWhatsapp: c.support.whatsapp,
    supportEmail: c.support.email,
    privacyUrl: c.legal.privacyUrl,
    kvkkUrl: c.legal.kvkkUrl,
    termsUrl: c.legal.termsUrl,
  );

  final String? supportPhone;
  final String? supportWhatsapp;
  final String? supportEmail;

  /// Destek sayfası (API'nin `/legal/support` sayfası).
  final String? supportUrl;
  final String? privacyUrl;
  final String? kvkkUrl;
  final String? termsUrl;

  bool get hasSupport =>
      supportPhone != null ||
      supportWhatsapp != null ||
      supportEmail != null ||
      supportUrl != null;

  /// Boş alanları [other]'dan doldurur.
  AuthLinks orElse(AuthLinks other) => AuthLinks(
    supportPhone: supportPhone ?? other.supportPhone,
    supportWhatsapp: supportWhatsapp ?? other.supportWhatsapp,
    supportEmail: supportEmail ?? other.supportEmail,
    supportUrl: supportUrl ?? other.supportUrl,
    privacyUrl: privacyUrl ?? other.privacyUrl,
    kvkkUrl: kvkkUrl ?? other.kvkkUrl,
    termsUrl: termsUrl ?? other.termsUrl,
  );

  /// Sunucu hiç yanıt vermediyse yasal metinler API'nin kendi `/legal/*` sayfalarına düşer (spec B.3).
  /// Sahte kipte uydurma adres üretilmez.
  AuthLinks withLegalFallback(AppEnv env) {
    if (env.isFake) return this;
    String legal(String doc) => '${env.apiBaseUrl}legal/$doc';
    return AuthLinks(
      supportPhone: supportPhone,
      supportWhatsapp: supportWhatsapp,
      supportEmail: supportEmail,
      supportUrl: supportUrl,
      privacyUrl: privacyUrl ?? legal('privacy'),
      kvkkUrl: kvkkUrl ?? legal('kvkk'),
      termsUrl: termsUrl ?? legal('terms'),
    );
  }
}

/// `app/config` yoklamasının sonucu.
@immutable
class ServerGate {
  const ServerGate(
    this.kind, {
    this.maintenanceMessage,
    this.links,
    this.otpLogin,
  });

  const ServerGate.unknown()
    : kind = ServerGateKind.unknown,
      maintenanceMessage = null,
      links = null,
      otpLogin = null;

  /// Uygulamanın konuştuğu sözleşme (`AppConfigDto.contractVersion`, spec B.3).
  static const expectedContract = 'mobile-v1';

  /// `app/config` gövdesinden. Sözleşme sürümü hiç yoksa (eski sahte yanıtlar) uyumlu sayılır.
  factory ServerGate.fromConfigJson(Object? json) {
    final r = JsonReader.of(json);
    final links = AuthLinks.fromConfigJson(json);
    final otp = r.objOrNull('features')?.boolOrNull('otpLogin');
    final m = r.objOrNull('maintenance');
    if (m != null && m.boolean('active')) {
      return ServerGate(
        ServerGateKind.maintenance,
        maintenanceMessage: m.nonEmpty('message'),
        links: links,
        otpLogin: otp,
      );
    }
    final contract = r.nonEmpty('contractVersion');
    if (contract != null && contract != expectedContract) {
      return ServerGate(ServerGateKind.outdated, links: links, otpLogin: otp);
    }
    return ServerGate(ServerGateKind.ok, links: links, otpLogin: otp);
  }

  /// İstek hatasından: 404 eski API demektir (mobil v1 uçları yok); diğerleri belirsiz.
  factory ServerGate.fromFailure(AppFailure failure) =>
      failure is NotFoundFailure
      ? const ServerGate(ServerGateKind.outdated)
      : const ServerGate.unknown();

  final ServerGateKind kind;

  /// Sunucunun bakım metni (boşsa uygulamanın varsayılanı).
  final String? maintenanceMessage;

  /// Yanıttan okunan bağlantılar (ulaşılamadıysa null).
  final AuthLinks? links;

  /// `features.otpLogin` (ulaşılamadıysa null: çekirdek yapılandırma kullanılır).
  final bool? otpLogin;

  /// Giriş ekranı yerine durum ekranı gösterilir.
  bool get blocks =>
      kind == ServerGateKind.maintenance || kind == ServerGateKind.outdated;

  @override
  bool operator ==(Object other) =>
      other is ServerGate &&
      other.kind == kind &&
      other.maintenanceMessage == maintenanceMessage &&
      other.otpLogin == otpLogin;

  @override
  int get hashCode => Object.hash(kind, maintenanceMessage, otpLogin);
}
