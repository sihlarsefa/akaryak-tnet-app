import 'package:flutter/foundation.dart';

import '../../../core/models/json.dart';

/// Aydınlatma metni bölümü.
@immutable
class DisclosureSection {
  const DisclosureSection({required this.title, required this.body});

  factory DisclosureSection.fromJson(JsonReader r) =>
      DisclosureSection(title: r.str('title'), body: r.str('body'));

  final String title;
  final String body;
}

/// `GET assistant/disclosure` (spec B.11 `AssistantDisclosureDto`): yapay zekâ asistanı aydınlatma
/// metni, sürümü ve kullanıcının bu sürümü kabul edip etmediği.
@immutable
class AssistantDisclosure {
  const AssistantDisclosure({
    required this.version,
    required this.title,
    required this.text,
    this.sections = const [],
    this.provider,
    this.providerCountry,
    this.retentionDays,
    this.legalUrl,
    this.accepted = false,
    this.acceptedAt,
  });

  factory AssistantDisclosure.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return AssistantDisclosure(
      version: r.str('version', '1'),
      title: r.nonEmpty('title') ?? 'Yapay zekâ asistanı aydınlatma metni',
      text: r.str('text'),
      sections: List.unmodifiable(
        r.list('sections', DisclosureSection.fromJson),
      ),
      provider: r.nonEmpty('provider'),
      providerCountry: r.nonEmpty('providerCountry'),
      retentionDays: r.intOrNull('retentionDays'),
      legalUrl: r.nonEmpty('legalUrl'),
      accepted: r.boolean('accepted'),
      acceptedAt: r.dateUtc('acceptedAt'),
    );
  }

  final String version;
  final String title;

  /// Düz metin (bölümler boş satırla ayrılır; ilk satır başlık).
  final String text;
  final List<DisclosureSection> sections;
  final String? provider;
  final String? providerCountry;
  final int? retentionDays;

  /// Tam metin sayfası (`/legal/ai`).
  final String? legalUrl;
  final bool accepted;
  final DateTime? acceptedAt;

  /// Gösterilecek bölümler: sunucu bölüm vermediyse metin boş satırlardan bölünür.
  List<DisclosureSection> get displaySections {
    if (sections.isNotEmpty) return sections;
    final out = <DisclosureSection>[];
    for (final block in text.split(RegExp(r'\n\s*\n'))) {
      final b = block.trim();
      if (b.isEmpty) continue;
      final nl = b.indexOf('\n');
      out.add(
        nl < 0
            ? DisclosureSection(title: '', body: b)
            : DisclosureSection(
                title: b.substring(0, nl).trim(),
                body: b.substring(nl + 1).trim(),
              ),
      );
    }
    return out;
  }
}

/// `GET assistant/suggestions` satırı: kategori + başlangıç soruları.
@immutable
class SuggestionGroup {
  const SuggestionGroup({required this.category, required this.questions});

  factory SuggestionGroup.fromJson(JsonReader r) => SuggestionGroup(
    category: r.str('category'),
    questions: List.unmodifiable(r.strings('questions')),
  );

  final String category;
  final List<String> questions;
}

/// `POST assistant/chat` yanıtı.
@immutable
class ChatReply {
  const ChatReply({
    required this.reply,
    required this.chatLogId,
    this.isError = false,
  });

  factory ChatReply.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return ChatReply(
      reply: r.str('reply'),
      chatLogId: r.integer('chatLogId'),
      isError: r.boolean('isError'),
    );
  }

  final String reply;
  final int chatLogId;

  /// Model yanıt veremedi; [reply] sabit Türkçe metindir (hata balonu, geri bildirim yok).
  final bool isError;
}

enum ChatRole { user, assistant }

/// Geri bildirim durumu.
enum ChatFeedback { none, sending, helpful, notHelpful }

/// Sohbetteki bir mesaj (yalnızca cihazda; sunucu kayıtları `chatLogId` ile eşlenir).
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.chatLogId,
    this.isError = false,
    this.failed = false,
    this.failureMessage,
    this.feedback = ChatFeedback.none,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime at;

  /// Asistan yanıtının sunucu kaydı (geri bildirim için).
  final int? chatLogId;

  /// Asistan yanıt veremedi (hata balonu).
  final bool isError;

  /// Kullanıcı mesajı gönderilemedi ("Tekrar dene").
  final bool failed;
  final String? failureMessage;
  final ChatFeedback feedback;

  bool get isUser => role == ChatRole.user;

  /// Geri bildirim verilebilir mi.
  bool get canRate =>
      !isUser && !isError && chatLogId != null && chatLogId! > 0;

  ChatMessage copyWith({
    bool? failed,
    String? Function()? failureMessage,
    ChatFeedback? feedback,
  }) => ChatMessage(
    id: id,
    role: role,
    text: text,
    at: at,
    chatLogId: chatLogId,
    isError: isError,
    failed: failed ?? this.failed,
    failureMessage: failureMessage == null
        ? this.failureMessage
        : failureMessage(),
    feedback: feedback ?? this.feedback,
  );

  /// Sohbet geçmişi satırı (`{role, content}`).
  JsonMap toHistory() => {
    'role': isUser ? 'user' : 'assistant',
    'content': text.length > 2000 ? text.substring(0, 2000) : text,
  };
}
