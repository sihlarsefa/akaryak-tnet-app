import 'package:flutter/foundation.dart';

import '../utils/turkish_text.dart';
import 'enums.dart';
import 'json.dart';

/// Belge eki (`AttachmentDto`). Tarihler UTC. URL'lerde yalnızca [publicId] kullanılır.
@immutable
class Attachment {
  const Attachment({
    required this.publicId,
    required this.ownerType,
    required this.ownerId,
    required this.kind,
    this.kindLabelFromServer,
    required this.fileName,
    required this.contentType,
    this.sizeBytes = 0,
    this.version = 1,
    this.previousVersionPublicId,
    this.note,
    this.uploadedByName,
    this.createdAt,
    this.isActive = true,
    this.canDelete = false,
    this.stationId,
    this.customerId,
  });

  factory Attachment.fromJson(JsonReader r) => Attachment(
    publicId: r.str('publicId'),
    ownerType: r.enumOf('ownerType', AttachmentOwnerType.fromCode),
    ownerId: r.integer('ownerId'),
    kind: r.enumOf('kind', AttachmentKind.fromCode),
    kindLabelFromServer: r.nonEmpty('kindLabel'),
    fileName: r.str('fileName'),
    contentType: r.str('contentType'),
    sizeBytes: r.integer('sizeBytes'),
    version: r.integer('version', 1),
    previousVersionPublicId: r.nonEmpty('previousVersionPublicId'),
    note: r.nonEmpty('note'),
    uploadedByName: r.nonEmpty('uploadedByName'),
    createdAt: r.dateUtc('createdAt'),
    isActive: r.boolean('isActive', true),
    canDelete: r.boolean('canDelete'),
    stationId: r.intOrNull('stationId'),
    customerId: r.intOrNull('customerId'),
  );

  final String publicId;
  final AttachmentOwnerType ownerType;
  final int ownerId;
  final AttachmentKind kind;
  final String? kindLabelFromServer;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final int version;
  final String? previousVersionPublicId;
  final String? note;
  final String? uploadedByName;
  final DateTime? createdAt;
  final bool isActive;
  final bool canDelete;
  final int? stationId;
  final int? customerId;

  String get kindLabel => kindLabelFromServer ?? kind.label;
  bool get isImage => contentType.asciiLower.startsWith('image/');
  bool get isPdf => contentType.asciiLower == 'application/pdf';
}

/// Yükleme sonucu. Aynı bayide aynı içerik varsa [isDuplicate] (uyarı; engellemez).
@immutable
class AttachmentUploadResult {
  const AttachmentUploadResult({
    required this.attachment,
    this.isDuplicate = false,
    this.duplicates = const [],
  });

  factory AttachmentUploadResult.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return AttachmentUploadResult(
      attachment: Attachment.fromJson(r.obj('attachment')),
      isDuplicate: r.boolean('isDuplicate'),
      duplicates: List.unmodifiable(r.list('duplicates', Attachment.fromJson)),
    );
  }

  final Attachment attachment;
  final bool isDuplicate;
  final List<Attachment> duplicates;
}
