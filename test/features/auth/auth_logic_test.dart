import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/auth_models.dart';
import 'package:akaryakitnet/core/models/problem.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/features/auth/api.dart';
import 'package:akaryakitnet/features/auth/application/auth_clock.dart';
import 'package:akaryakitnet/features/auth/application/auth_errors.dart';
import 'package:akaryakitnet/features/auth/application/biometric.dart';
import 'package:akaryakitnet/features/auth/application/link_opener.dart';
import 'package:akaryakitnet/features/auth/data/server_gate.dart';
import 'package:akaryakitnet/features/auth/presentation/code_page.dart';
import 'package:akaryakitnet/features/auth/presentation/widgets/phone_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  group('bekleme süresi yazımı (spec C.7)', () {
    test('kısa süre saniye, uzun süre dakika:saniye', () {
      expect(formatWait(const Duration(seconds: 45)), '45 sn');
      expect(formatWait(const Duration(milliseconds: 44100)), '45 sn');
      expect(formatWait(const Duration(minutes: 15)), '15:00');
      expect(formatWait(const Duration(minutes: 14, seconds: 9)), '14:09');
      expect(formatWait(const Duration(hours: 1, minutes: 5)), '1:05:00');
      expect(formatWait(Duration.zero), '0 sn');
    });

    test('ekran okuyucu için açık yazım', () {
      expect(
        spokenWait(const Duration(minutes: 14, seconds: 59)),
        '14 dakika 59 saniye',
      );
      expect(spokenWait(const Duration(seconds: 7)), '7 saniye');
      expect(spokenWait(const Duration(minutes: 2)), '2 dakika');
    });
  });

  group('sunucu kapısı (app/config)', () {
    test('uyumlu sözleşme → açık; sözleşme yoksa da açık', () {
      expect(
        ServerGate.fromConfigJson({'contractVersion': 'mobile-v1'}).kind,
        ServerGateKind.ok,
      );
      expect(ServerGate.fromConfigJson(const {}).kind, ServerGateKind.ok);
    });

    test('farklı sözleşme → "Sunucu güncel değil"', () {
      final g = ServerGate.fromConfigJson({'contractVersion': 'mobile-v2'});
      expect(g.kind, ServerGateKind.outdated);
      expect(g.blocks, isTrue);
    });

    test('bakım → "Bakımdayız" ve sunucunun metni', () {
      final g = ServerGate.fromConfigJson({
        'contractVersion': 'mobile-v1',
        'maintenance': {'active': true, 'message': 'Gece bakımı.'},
      });
      expect(g.kind, ServerGateKind.maintenance);
      expect(g.maintenanceMessage, 'Gece bakımı.');
      expect(
        ServerGate.fromConfigJson({
          'maintenance': {'active': false, 'message': 'x'},
        }).kind,
        ServerGateKind.ok,
      );
    });

    test('404 eski API demektir; bağlantı hatası engellemez', () {
      expect(
        ServerGate.fromFailure(const NotFoundFailure()).kind,
        ServerGateKind.outdated,
      );
      expect(
        ServerGate.fromFailure(const OfflineFailure()).kind,
        ServerGateKind.unknown,
      );
      expect(const ServerGate.unknown().blocks, isFalse);
    });

    test(
      'destek ve yasal bağlantılar; boşlar çekirdekten, yasal son çare /legal',
      () {
        final g = ServerGate.fromConfigJson({
          'support': {
            'phone': '0850 000 00 00',
            'url': 'https://x.test/destek',
          },
          'legal': {'kvkkUrl': 'https://x.test/kvkk'},
          'features': {'otpLogin': false},
        });
        expect(g.otpLogin, isFalse);
        final merged = g.links!.orElse(
          AuthLinks.fromConfig(
            const AppConfig(
              support: SupportInfo(email: 'destek@x.test'),
              legal: LegalLinks(privacyUrl: 'https://x.test/gizlilik'),
            ),
          ),
        );
        expect(merged.supportPhone, '0850 000 00 00');
        expect(merged.supportEmail, 'destek@x.test');
        expect(merged.supportUrl, 'https://x.test/destek');
        expect(merged.privacyUrl, 'https://x.test/gizlilik');
        final live = merged.withLegalFallback(
          const AppEnv(
            env: AknEnv.test,
            apiBaseUrl: 'http://134.149.201.54:3108/',
            apiMode: ApiMode.live,
            portalBaseUrl: 'http://134.149.201.54:3107/',
          ),
        );
        expect(live.termsUrl, 'http://134.149.201.54:3108/legal/terms');
        expect(live.kvkkUrl, 'https://x.test/kvkk');
        expect(
          merged.withLegalFallback(AppEnv.fakeForTests).termsUrl,
          isNull,
          reason: 'sahte kipte uydurma adres yok',
        );
      },
    );
  });

  group('destek bağlantıları', () {
    test('telefon, WhatsApp, e-posta, web', () {
      expect(
        SupportLinks.phone('0850 000 00 00').toString(),
        'tel:08500000000',
      );
      expect(SupportLinks.phone(' '), isNull);
      expect(
        SupportLinks.whatsapp('0532 000 00 01').toString(),
        'https://wa.me/905320000001',
      );
      expect(
        SupportLinks.whatsapp('5320000001').toString(),
        'https://wa.me/905320000001',
      );
      expect(
        SupportLinks.email(
          'destek@x.test',
          subject: 'AkaryakıtNet hesap talebi',
        ).toString(),
        'mailto:destek@x.test?subject=Akaryak%C4%B1tNet%20hesap%20talebi',
      );
      expect(SupportLinks.email('geçersiz'), isNull);
      expect(SupportLinks.web('javascript:alert(1)'), isNull);
      expect(SupportLinks.web('https://x.test/a'), isNotNull);
    });
  });

  group('hata metinleri (spec C.7)', () {
    test('401 girişte "şifre hatalı"; sunucu mesajı önce gelir', () {
      expect(
        describeAuthFailure(const UnauthorizedFailure('unauthorized')).message,
        'Kullanıcı adı veya şifre hatalı.',
      );
      expect(
        describeAuthFailure(
          const UnauthorizedFailure(
            'unauthorized',
            problem: Problem(detail: 'Hesap pasif.'),
          ),
        ).message,
        'Hesap pasif.',
      );
    });

    test('sunucu hatası: genel metin + destek kodu (ilk 8 karakter)', () {
      final info = describeAuthFailure(
        const ServerFailure(
          statusCode: 500,
          problem: Problem(code: 'server_error', traceId: '1a2b3c4d-5e6f'),
        ),
      );
      expect(info.message, startsWith('Beklenmeyen bir hata oluştu'));
      expect(info.supportCode, '1a2b3c4d');
    });

    test('503 sms_not_configured: sunucunun Türkçe açıklaması', () {
      final info = describeAuthFailure(
        const ServerFailure(
          statusCode: 503,
          problem: Problem(
            code: 'sms_not_configured',
            detail: 'SMS doğrulaması yapılandırılmadı; yöneticinize başvurun.',
          ),
        ),
      );
      expect(info.message, contains('SMS doğrulaması'));
      expect(info.supportCode, isNull);
    });

    test('doğrulama hatası alanlara dağıtılır', () {
      final info = describeAuthFailure(
        const ValidationFailure({
          'phone': ['Geçerli bir cep telefonu girin.'],
        }),
      );
      expect(info.fieldError('Phone'), 'Geçerli bir cep telefonu girin.');
      expect(info.fieldError('password'), isNull);
    });

    test('çevrimdışı ve zaman aşımı', () {
      expect(
        describeAuthFailure(const OfflineFailure()).message,
        startsWith('İnternet bağlantısı yok'),
      );
      expect(
        describeAuthFailure(const TimeoutFailure()).message,
        startsWith('Sunucu zamanında yanıt vermedi'),
      );
    });
  });

  group('telefon yazımı', () {
    TextEditingValue type(String text) => const TrMobileFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

    test('5XX XXX XX XX; 0 / 90 / +90 atılır, en fazla 10 hane', () {
      expect(type('5321234567').text, '532 123 45 67');
      expect(type('05321234567').text, '532 123 45 67');
      expect(type('+90 532 123 45 67').text, '532 123 45 67');
      expect(type('53212').text, '532 12');
      expect(type('532123456789').text, '532 123 45 67');
      expect(TrMobileFormatter.localDigits('0532 123 45 67'), '5321234567');
    });
  });

  group('güncelleme varyantları ve kod argümanı', () {
    test('rota sorgusundan varyant', () {
      expect(UpdateReason.parse('maintenance'), UpdateReason.maintenance);
      expect(UpdateReason.parse('server'), UpdateReason.server);
      expect(UpdateReason.parse('?'), isNull);
      expect(
        AuthRoutes.update(UpdateReason.maintenance),
        '/update?reason=maintenance',
      );
    });

    test('aşama 0 uyumu: yalnızca sorgu verilirse 2FA', () {
      const challenge = OtpChallenge(
        challengeId: 'c1',
        maskedPhone: '0532 *** ** 01',
        expiresInSeconds: 300,
        resendInSeconds: 60,
      );
      expect(CodePage.argsFrom(challenge)?.purpose, CodePurpose.twoFactor);
      expect(CodePage.argsFrom(null), isNull);
    });
  });

  group('biyometri', () {
    test('tür ve sonuç eşlemesi', () {
      expect(
        LocalAuthBiometricAuthenticator.kindOf(const [
          BiometricType.fingerprint,
          BiometricType.face,
        ]),
        BiometricKind.face,
      );
      expect(
        LocalAuthBiometricAuthenticator.kindOf(const [BiometricType.strong]),
        BiometricKind.generic,
      );
      expect(LocalAuthBiometricAuthenticator.kindOf(const []), isNull);
      expect(
        LocalAuthBiometricAuthenticator.outcomeOf(
          LocalAuthExceptionCode.userCanceled,
        ),
        BiometricOutcome.cancelled,
      );
      expect(
        LocalAuthBiometricAuthenticator.outcomeOf(
          LocalAuthExceptionCode.noBiometricsEnrolled,
        ),
        BiometricOutcome.unavailable,
      );
      expect(
        LocalAuthBiometricAuthenticator.outcomeOf(
          LocalAuthExceptionCode.biometricLockout,
        ),
        BiometricOutcome.lockedOut,
      );
    });

    test('platforma göre adlar', () {
      expect(
        unlockLabel(BiometricKind.face, platform: TargetPlatform.iOS),
        'Face ID ile aç',
      );
      expect(
        unlockLabel(
          BiometricKind.fingerprint,
          platform: TargetPlatform.android,
        ),
        'Parmak iziyle aç',
      );
      expect(unlockLabel(null), 'Kilidi aç');
      expect(
        biometricPhrase(BiometricKind.face, platform: TargetPlatform.iOS),
        'Face ID ile',
      );
    });
  });
}
