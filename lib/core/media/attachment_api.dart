import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/attachment.dart';
import '../models/enums.dart';
import '../models/json.dart';
import '../network/api_client.dart';
import '../network/idempotency.dart';
import '../network/network_providers.dart';
import '../utils/turkish_text.dart';

/// Belge ekleri (`api/v1/attachments`, spec B.5). PDF, JPG, PNG; HEIC önceden JPEG'e çevrilir
/// (`ImageCapture`). Yükleme Idempotency-Key taşır: aynı anahtarla tekrar sunucuda ikinci ek oluşturmaz.
class AttachmentApi {
  AttachmentApi(this.api);

  final ApiClient api;

  /// Dosya yükler. [onProgress] 0..1. [idempotencyKey] verilmezse yeni üretilir (tekrar denemede
  /// aynı anahtarı vermek için çağıran saklamalıdır).
  Future<AttachmentUploadResult> upload({
    required AttachmentOwnerType ownerType,
    required int ownerId,
    required AttachmentKind kind,
    required String filePath,
    String? fileName,
    String? contentType,
    String? note,
    String? replaces,
    String? idempotencyKey,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final name = fileName ?? p.basename(filePath);
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: name,
        contentType: _mediaType(contentType ?? _guessType(name)),
      ),
      'ownerType': '${ownerType.code}',
      'ownerId': '$ownerId',
      'kind': '${kind.code}',
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'replaces': ?replaces,
    });
    return _upload(form, idempotencyKey, onProgress, cancelToken);
  }

  /// Bayttan yükler (ör. imza PNG'si).
  Future<AttachmentUploadResult> uploadBytes({
    required AttachmentOwnerType ownerType,
    required int ownerId,
    required AttachmentKind kind,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    String? note,
    String? idempotencyKey,
    void Function(double progress)? onProgress,
  }) {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: _mediaType(contentType),
      ),
      'ownerType': '${ownerType.code}',
      'ownerId': '$ownerId',
      'kind': '${kind.code}',
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return _upload(form, idempotencyKey, onProgress, null);
  }

  Future<AttachmentUploadResult> _upload(
    FormData form,
    String? key,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  ) => api.upload(
    'attachments',
    form: form,
    idempotencyKey: key ?? newIdempotencyKey(),
    cancelToken: cancelToken,
    onProgress: onProgress == null
        ? null
        : (sent, total) => onProgress(total <= 0 ? 0 : sent / total),
    parse: AttachmentUploadResult.fromJson,
  );

  /// Kaydın ekleri. [includeHistory] silinmiş/eski sürümleri de getirir.
  Future<List<Attachment>> list(
    AttachmentOwnerType ownerType,
    int ownerId, {
    bool includeHistory = false,
  }) => api.get(
    'attachments',
    query: {
      'ownerType': ownerType.code,
      'ownerId': ownerId,
      'includeHistory': includeHistory,
    },
    parse: (j) => JsonReader.parseList(j, Attachment.fromJson),
  );

  /// İçerik yolu (Dio köküne göre). [approvalId] verilirse görüntüleme onay kaydına yazılır.
  static String contentPath(
    String publicId, {
    int? approvalId,
    bool download = false,
  }) {
    final q = <String>[
      if (approvalId != null) 'approvalId=$approvalId',
      if (download) 'download=true',
    ];
    return 'attachments/${Uri.encodeComponent(publicId)}/content${q.isEmpty ? '' : '?${q.join('&')}'}';
  }

  /// İçeriği indirir (görüntüleyici, paylaş).
  Future<Uint8List> content(String publicId, {int? approvalId}) => api.bytes(
    'attachments/${Uri.encodeComponent(publicId)}/content',
    query: {'approvalId': approvalId},
  );

  Future<void> delete(String publicId) =>
      api.delete<void>('attachments/${Uri.encodeComponent(publicId)}');

  static String _guessType(String name) =>
      switch (p.extension(name).asciiLower) {
        '.pdf' => 'application/pdf',
        '.png' => 'image/png',
        _ => 'image/jpeg',
      };

  static DioMediaType _mediaType(String type) {
    final parts = type.split('/');
    return DioMediaType(
      parts.first,
      parts.length > 1 ? parts[1] : 'octet-stream',
    );
  }
}

final attachmentApiProvider = Provider<AttachmentApi>(
  (ref) => AttachmentApi(ref.watch(apiClientProvider)),
);
