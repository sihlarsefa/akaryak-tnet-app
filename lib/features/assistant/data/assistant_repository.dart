import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import 'assistant_models.dart';

/// Asistan uçları (spec B.11, `api/v1/assistant`).
class AssistantRepository {
  AssistantRepository(this._api);

  final ApiClient _api;

  /// Sunucunun kabul ettiği en çok mesaj uzunluğu.
  static const messageMaxLength = 1000;

  /// Gönderilen geçmiş satırı sayısı (sunucu son 10'u kullanır).
  static const historyItems = 10;

  Future<AssistantDisclosure> disclosure() => _api.get(
    'assistant/disclosure',
    quiet403: true,
    parse: AssistantDisclosure.fromJson,
  );

  Future<void> consent(String version) =>
      _api.post<void>('assistant/consent', body: {'version': version});

  /// KVKK: onayı geri al (Profil > Gizlilik).
  Future<void> withdrawConsent() => _api.delete<void>('assistant/consent');

  Future<List<SuggestionGroup>> suggestions() => _api.get(
    'assistant/suggestions',
    quiet403: true,
    parse: (j) => JsonReader.parseList(j, SuggestionGroup.fromJson),
  );

  Future<ChatReply> chat({
    required String message,
    required List<ChatMessage> history,
    required String consentVersion,
  }) => _api.post(
    'assistant/chat',
    body: {
      'message': message,
      'history': [for (final m in history) m.toHistory()],
      'consentVersion': consentVersion,
    },
    parse: ChatReply.fromJson,
  );

  Future<void> feedback({
    required int chatLogId,
    required bool helpful,
    String? comment,
  }) => _api.post<void>(
    'assistant/feedback',
    body: {
      'chatLogId': chatLogId,
      'helpful': helpful,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    },
  );
}

final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => AssistantRepository(ref.watch(apiClientProvider)),
);
