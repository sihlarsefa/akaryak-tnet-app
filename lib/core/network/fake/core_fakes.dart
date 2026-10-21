import 'dart:convert';
import 'dart:typed_data';

import '../../auth/permissions.dart';
import '../../models/enums.dart';
import '../../models/json.dart';
import '../../models/me_access.dart';
import '../../utils/turkish_text.dart';
import '../../utils/validators.dart';
import 'fake_auth.dart';
import 'fake_personas.dart';
import 'fake_server.dart';
import 'fake_world.dart';

/// Çekirdek sahte uçlar (M0a): kimlik (`auth/*`), cihaz, `me/access`, `me/deletion-request`,
/// `app/config`, `notifications/unread-count` ve belge ekleri (`attachments`).
/// Özellikler aynı yolu kendi `<f>_fake.dart` dosyalarında yeniden kaydederek ezebilir.
void registerCoreFakes(FakeServer s) {
  // ------------------------------------------------------------------ Kimlik (spec B.3)
  s.post('auth/login', (req) {
    final r = req.json;
    final p = findFakePersona(r.str('userNameOrEmail'));
    if (p == null || r.str('password') != FakeAuth.password) {
      throw FakeResponse.problem(
        401,
        'unauthorized',
        'Kullanıcı adı veya şifre hatalı.',
      );
    }
    final device = r.map('device');
    final deviceId = JsonReader(device).str('deviceId', 'fake-device');
    if (p.requiresTwoFactor) {
      final c = s.auth.createChallenge(p, purpose: 1, deviceId: deviceId);
      return {
        'status': 'twoFactorRequired',
        'tokens': null,
        'challenge': _challenge(c, p),
      };
    }
    return {
      'status': 'ok',
      'tokens': s.auth.issueTokens(p, deviceId: deviceId, device: device),
      'challenge': null,
    };
  }, anonymous: true);

  s.post('auth/otp/send', (req) {
    final r = req.json;
    final phone = Validators.normalizePhone(r.str('phone'));
    if (phone == null) {
      throw FakeResponse.validation({
        'phone': ['Geçerli bir cep telefonu girin (5XX XXX XX XX).'],
      });
    }
    FakePersona? match;
    for (final p in fakePersonas) {
      if ('90${p.phone}' == phone && p.persona != Persona.platform) match = p;
    }
    final deviceId = JsonReader(r.map('device')).str('deviceId', 'fake-device');
    final c = s.auth.createChallenge(match, purpose: 2, deviceId: deviceId);
    // Eşleşme olmasa da aynı biçim (numara ifşa edilmez).
    final ten = phone.substring(2);
    return {
      'challengeId': c.id,
      'maskedPhone': '0${ten.substring(0, 3)} *** ** ${ten.substring(8)}',
      'expiresInSeconds': 300,
      'resendInSeconds': 60,
    };
  }, anonymous: true);

  s.post('auth/verify', (req) {
    final r = req.json;
    final result = s.auth.verify(r.str('challengeId'), r.str('code'));
    if (result.persona == null) {
      throw FakeResponse.business(result.error ?? 'Kod hatalı.');
    }
    final device = r.map('device');
    final deviceId = JsonReader(device).str('deviceId', 'fake-device');
    return {
      'status': 'ok',
      'tokens': s.auth.issueTokens(
        result.persona!,
        deviceId: deviceId,
        device: device,
      ),
      'challenge': null,
    };
  }, anonymous: true);

  s.post('auth/refresh', (req) {
    final r = req.json;
    final tokens = s.auth.rotate(r.str('refreshToken'), r.str('deviceId'));
    if (tokens == null) {
      throw FakeResponse.problem(
        401,
        'unauthorized',
        'Oturumunuz sona erdi. Lütfen yeniden giriş yapın.',
      );
    }
    return {'status': 'ok', 'tokens': tokens, 'challenge': null};
  }, anonymous: true);

  s.post('auth/logout', (req) {
    final p = req.requireUser();
    final all = req.json.boolean('allDevices');
    if (all) {
      s.auth.revokeAll(p.key);
    } else {
      s.auth.revokeDevice(p.key, req.header('x-device-id') ?? 'fake-device');
    }
    return FakeResponse.noContent();
  });

  // Erişim belirteci dolmuşken çıkış (spec B.3): her zaman 204.
  s.post('auth/revoke', (req) {
    final r = req.json;
    s.auth.revokeByRefresh(r.str('refreshToken'), r.str('deviceId'));
    return FakeResponse.noContent();
  }, anonymous: true);

  s.get('auth/sessions', (req) {
    final p = req.requireUser();
    final current = req.header('x-device-id');
    final list =
        s.auth.sessions[p.key]?.values.where((d) => !d.revoked).toList() ??
        const [];
    return [
      for (final d in list)
        {
          'deviceId': d.deviceId,
          'platform': d.platform,
          'model': d.model,
          'appVersion': d.appVersion,
          'lastSeenAt': d.lastSeenAt.toIso8601String(),
          'current': d.deviceId == current,
        },
    ];
  });

  s.delete('auth/sessions/{deviceId}', (req) {
    s.auth.revokeDevice(req.requireUser().key, req.params['deviceId']!);
    return FakeResponse.noContent();
  });

  s.put('devices/current', (req) {
    final p = req.requireUser();
    final deviceId = req.header('x-device-id');
    if (deviceId == null) {
      throw FakeResponse.validation(const {}, 'X-Device-Id başlığı gerekli.');
    }
    final session = s.auth.sessions[p.key]?[deviceId];
    if (session != null) {
      session.pushToken = req.json.nonEmpty('pushToken');
      session.pushEnabled = req.json.boolean('pushEnabled', true);
      session.lastSeenAt = DateTime.now().toUtc();
    }
    return FakeResponse.noContent();
  });

  // ------------------------------------------------------------------ Hesap
  s.get('me/access', (req) => s.world.meAccess(req.requireUser()));

  s.post('me/deletion-request', (req) {
    req.requireUser();
    return FakeResponse.accepted({
      'message':
          'Hesap silme talebiniz alındı. Merkez ekibi talebinizi inceleyip sizinle iletişime geçecek.',
    });
  });

  s.get('app/config', (req) => fakeAppConfig(), anonymous: true);

  // ------------------------------------------------------------------ Rozetler
  s.get('notifications/unread-count', (req) {
    final p = req.requireUser();
    return {
      'notifications': s.world.unreadNotifications(p.userId),
      'approvals': _canSeeApprovals(p) ? s.world.approvalsWaitingFor(p) : 0,
    };
  });

  // ------------------------------------------------------------------ Belge ekleri (spec B.5)
  s.post('attachments', (req) {
    final p = req.requireUser();
    final form = req.multipart;
    final file = form?.file('file');
    if (form == null || file == null) {
      throw FakeResponse.validation({
        'file': ['Dosya seçin.'],
      });
    }
    final type = file.contentType.asciiLower;
    if (!(type == 'application/pdf' ||
        type == 'image/jpeg' ||
        type == 'image/png')) {
      throw FakeResponse.business(
        'Yalnızca PDF, JPG ve PNG dosyaları yüklenebilir.',
      );
    }
    if (file.bytes.length > 25 * 1024 * 1024) {
      throw FakeResponse.business('Dosya en fazla 25 MB olabilir.');
    }
    final dto = fakeAttachment(
      s.world,
      ownerType: int.tryParse(form.fields['ownerType'] ?? '') ?? 1,
      ownerId: int.tryParse(form.fields['ownerId'] ?? '') ?? 0,
      kind: int.tryParse(form.fields['kind'] ?? '') ?? 99,
      fileName: file.fileName,
      contentType: type,
      bytes: file.bytes,
      note: form.fields['note'],
      uploadedBy: p,
    );
    s.world.notifyAttachmentUploaded(dto, p);
    return {
      'attachment': dto,
      'isDuplicate': false,
      'duplicates': const <Object>[],
    };
  });

  s.get('attachments', (req) {
    req.requireUser();
    final ownerType = req.queryInt('ownerType');
    final ownerId = req.queryInt('ownerId');
    final history = req.queryBool('includeHistory') ?? false;
    return [
      for (final a in s.world.attachments)
        if (a['ownerType'] == ownerType &&
            a['ownerId'] == ownerId &&
            (history || a['isActive'] == true))
          a,
    ];
  });

  s.get('attachments/{publicId}/content', (req) {
    req.requireUser();
    final id = req.params['publicId']!;
    final meta = s.world.attachments
        .where((a) => a['publicId'] == id)
        .firstOrNull;
    final bytes = s.world.attachmentBytes[id];
    if (meta == null || bytes == null) {
      throw FakeResponse.notFound('Belge bulunamadı.');
    }
    return FakeBinary(
      bytes,
      contentType: meta['contentType'] as String,
      fileName: meta['fileName'] as String?,
    );
  });

  s.delete('attachments/{publicId}', (req) {
    req.requireUser();
    final meta = s.world.attachments
        .where((a) => a['publicId'] == req.params['publicId'])
        .firstOrNull;
    if (meta == null) throw FakeResponse.notFound('Belge bulunamadı.');
    meta['isActive'] = false;
    return FakeResponse.noContent();
  });
}

bool _canSeeApprovals(FakePersona p) =>
    p.persona == Persona.platform ||
    p.can(Pg.stationApprovals) ||
    p.can(Pg.customerApprovals);

JsonMap _challenge(FakeChallenge c, FakePersona p) => {
  'challengeId': c.id,
  'maskedPhone': p.phoneMasked,
  'expiresInSeconds': 300,
  'resendInSeconds': 60,
};

/// Sahte `AppConfigDto`.
JsonMap fakeAppConfig() => {
  'minBuild': 1,
  'latestBuild': 1,
  'storeUrl': null,
  'updateTitle': null,
  'updateMessage': null,
  'features': {
    'otpLogin': true,
    'assistant': true,
    'weather': true,
    'payments': true,
    'push': false,
    'deliveryPhotoRequired': true,
    'deliverySignatureRequired': true,
    'deliveryGpsRequired': false,
  },
  'support': {
    'phone': '08500000000',
    'whatsapp': '908500000000',
    'email': 'destek@akaryakitnet.local',
  },
  'legal': {
    'privacyUrl': 'https://akaryakitnet.local/gizlilik',
    'kvkkUrl': 'https://akaryakitnet.local/kvkk',
    'termsUrl': 'https://akaryakitnet.local/kullanim-kosullari',
  },
  'leadKvkkVersion': '2026-10',
  'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
};

/// Sahte belge eki kaydı oluşturur ve içeriğini saklar (`AttachmentDto`).
JsonMap fakeAttachment(
  FakeWorld world, {
  required int ownerType,
  required int ownerId,
  required int kind,
  required String fileName,
  required String contentType,
  required Uint8List bytes,
  String? note,
  FakePersona? uploadedBy,
}) {
  final n = world.nextId('attachment', start: 1);
  final publicId =
      '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
  final dto = <String, dynamic>{
    'publicId': publicId,
    'ownerType': ownerType,
    'ownerId': ownerId,
    'stationId': uploadedBy?.stationId,
    'customerId': uploadedBy?.customerId,
    'kind': kind,
    'kindLabel': AttachmentKind.fromCode(kind).label,
    'fileName': fileName,
    'contentType': contentType,
    'sizeBytes': bytes.length,
    'sha256': base64Encode(bytes.take(16).toList()),
    'version': 1,
    'previousVersionPublicId': null,
    'note': note,
    'uploadedByUserId': uploadedBy?.userId,
    'uploadedByName': uploadedBy?.displayName,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'isActive': true,
    'canDelete': true,
    'isImage': contentType.startsWith('image/'),
    'isPdf': contentType == 'application/pdf',
  };
  world.attachments.add(dto);
  world.attachmentBytes[publicId] = bytes;
  return dto;
}
