import 'dart:io';

import '../../../core/media/attachment_api.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/offline/outbox_runner.dart';
import '../../../core/utils/format.dart';
import 'deliver_draft.dart';
import 'driver_models.dart';

/// Şoför bekleyen işlemleri (spec C.4): `driver.start`, `driver.deliver`.
///
/// Gövdeler kullanıcı onayladığı anda kurulur (cihaz saati ve konum dahil) ve olduğu gibi saklanır;
/// tekrar denemeler aynı Idempotency-Key ve aynı gövdeyle gider, sunucu işlemi ikinci kez yapmaz.
/// Teslimde önce fotoğraflar ve imza yüklenir (her biri kendi kalıcı alt anahtarıyla), kimlikleri
/// gövdeye yazılır, sonra `deliver` çağrılır. Bekleyen bir yola çıkış varsa teslim ona bağlanır
/// (`dependsOn`): yola çıkış gitmeden teslim gönderilmez.
abstract final class DriverOutbox {
  static const start = 'driver.start';
  static const deliver = 'driver.deliver';

  static bool isDriverOp(OutboxOp op) => op.type == start || op.type == deliver;

  static int? shipmentIdOf(OutboxOp op) =>
      JsonReader(op.payload).intOrNull('shipmentId');

  // ------------------------------------------------------------------ Gövdeler

  /// `POST driver/shipments/{id}/start` gövdesi + kayıt bilgisi.
  static JsonMap startPayload({
    required int shipmentId,
    required String code,
    required DateTime deviceTime,
    DriverPosition? position,
  }) => {
    'shipmentId': shipmentId,
    'code': code,
    'body': {
      'deviceTime': deviceTime.toUtc().toIso8601String(),
      ...?position?.toRequest(),
    },
    if (position != null) 'position': position.toJson(),
  };

  /// `POST driver/shipments/{id}/deliver` gövdesi (fotoğraf ve imza kimlikleri gönderimde eklenir).
  static JsonMap deliverPayload({
    required DeliverDraft draft,
    required double liters,
    required DateTime deviceTime,
    DriverPosition? position,
  }) {
    final recipient = draft.recipientName.trim();
    final note = draft.note.trim();
    final waiver = draft.waiver;
    return {
      'shipmentId': draft.shipmentId,
      'code': draft.code,
      'body': {
        'deliveredLiters': double.parse(liters.toStringAsFixed(3)),
        'deliveryDocumentNo': draft.documentNo.trim(),
        if (recipient.isNotEmpty) 'recipientName': recipient,
        if (note.isNotEmpty) 'note': note,
        'deviceTime': deviceTime.toUtc().toIso8601String(),
        ...?position?.toRequest(),
        if (waiver != null) 'signatureWaiver': waiver.toJson(),
      },
      'photos': [for (final p in draft.photos) p.toJson()],
      if (waiver == null && draft.hasSignature)
        'signature': {
          ...jsonEntry('path', draft.signaturePath),
          ...jsonEntry('publicId', draft.signaturePublicId),
        },
      if (draft.correction) 'correction': true,
      if (position != null) 'position': position.toJson(),
    };
  }

  /// Reddedilen teslim işleminden düzeltme taslağı ("Düzelt"): girilen değerler ve dosyalar korunur.
  static DeliverDraft draftFromDeliverOp(OutboxOp op, {DateTime? now}) {
    final r = JsonReader(op.payload);
    final body = r.obj('body');
    final sig = r.objOrNull('signature');
    final waiver = body.objOrNull('signatureWaiver');
    final liters = body.decOrNull('deliveredLiters');
    return DeliverDraft(
      shipmentId: r.integer('shipmentId'),
      code: r.str('code'),
      step: DeliverStep.summary,
      litersText: liters == null ? '' : litersToText(liters),
      documentNo: body.str('deliveryDocumentNo'),
      recipientName: body.str('recipientName'),
      note: body.str('note'),
      photos: List.unmodifiable(r.list('photos', DraftPhoto.fromJson)),
      signaturePath: sig?.nonEmpty('path'),
      signaturePublicId: sig?.nonEmpty('publicId'),
      waiver: waiver == null ? null : SignatureWaiver.fromJson(waiver),
      correction: r.boolean('correction'),
      fixOpId: op.id,
      savedAt: (now ?? DateTime.now()).toUtc(),
    );
  }

  /// `7950.5` → `7950,5` (tuş takımı metni; binlik ayırıcı yok).
  static String litersToText(double liters) {
    final s = Fmt.number(liters, maxFraction: 3).replaceAll('.', '');
    return s;
  }

  /// Kullanıcıya gösterilen ad ("SVK-00005002 teslimatı").
  static String startLabel(String code) => '$code yola çıkış';
  static String deliverLabel(String code) => '$code teslimatı';

  // ------------------------------------------------------------------ İşleyiciler

  /// İşleyiciler. [onServerDetail] sunucunun döndürdüğü güncel ayrıntıyı alır (önbellek + listeler).
  static Map<String, OutboxHandler> handlers({
    required void Function(int shipmentId, JsonMap detail) onServerDetail,
    bool Function(String path)? fileExists,
  }) {
    final exists = fileExists ?? (String p) => File(p).existsSync();
    return {
      start: (op, ctx) async {
        final r = JsonReader(ctx.payload);
        final id = r.integer('shipmentId');
        final detail = await ctx.api.post<JsonMap>(
          'driver/shipments/$id/start',
          body: r.map('body'),
          idempotencyKey: op.idempotencyKey,
          parse: JsonReader.asMap,
        );
        onServerDetail(id, detail);
        return {
          'shipmentId': id,
          'status': JsonReader(detail).intOrNull('status'),
        };
      },
      deliver: (op, ctx) async {
        final id = JsonReader(ctx.payload).integer('shipmentId');
        final attachments = AttachmentApi(ctx.api);

        // 1. Fotoğraflar (her biri bir kez; kimlik gövdeye yazılır, tekrar denemede atlanır).
        final photos = [
          for (final p in JsonReader(ctx.payload).list('photos', (r) => r.raw))
            Map<String, dynamic>.of(p),
        ];
        for (var i = 0; i < photos.length; i++) {
          final photo = JsonReader(photos[i]);
          if (photo.nonEmpty('publicId') != null) continue;
          final path = photo.nonEmpty('path');
          if (path == null) continue;
          if (!exists(path)) {
            throw const BusinessFailure(
              'Teslim fotoğrafı telefonda bulunamadı. "Düzelt" ile fotoğrafı yeniden ekleyin.',
            );
          }
          final key = await ctx.subKey('photo:$i');
          final res = await attachments.upload(
            ownerType: AttachmentOwnerType.shipment,
            ownerId: id,
            kind: AttachmentKind.deliveryPhoto,
            filePath: path,
            fileName: 'teslimat-${i + 1}.jpg',
            contentType: 'image/jpeg',
            idempotencyKey: key,
          );
          photos[i] = {...photos[i], 'publicId': res.attachment.publicId};
          await ctx.savePayload({...ctx.payload, 'photos': photos});
        }

        // 2. İmza.
        final sigRaw = JsonReader(ctx.payload).objOrNull('signature');
        String? signatureId = sigRaw?.nonEmpty('publicId');
        final sigPath = sigRaw?.nonEmpty('path');
        if (signatureId == null && sigPath != null) {
          if (!exists(sigPath)) {
            throw const BusinessFailure(
              'İmza telefonda bulunamadı. "Düzelt" ile imzayı yeniden alın.',
            );
          }
          final key = await ctx.subKey('signature');
          final res = await attachments.upload(
            ownerType: AttachmentOwnerType.shipment,
            ownerId: id,
            kind: AttachmentKind.deliverySignature,
            filePath: sigPath,
            fileName: 'imza.png',
            contentType: 'image/png',
            idempotencyKey: key,
          );
          signatureId = res.attachment.publicId;
          await ctx.savePayload({
            ...ctx.payload,
            'signature': {...sigRaw!.raw, 'publicId': signatureId},
          });
        }

        // 3. Teslim.
        final body = <String, dynamic>{
          ...JsonReader(ctx.payload).map('body'),
          'photoIds': [
            for (final p in photos)
              if (JsonReader(p).nonEmpty('publicId') != null)
                JsonReader(p).str('publicId'),
          ],
          'signatureId': ?signatureId,
        };
        final detail = await ctx.api.post<JsonMap>(
          'driver/shipments/$id/deliver',
          body: body,
          idempotencyKey: op.idempotencyKey,
          parse: JsonReader.asMap,
        );
        onServerDetail(id, detail);
        return {
          'shipmentId': id,
          'status': JsonReader(detail).intOrNull('status'),
        };
      },
    };
  }
}
