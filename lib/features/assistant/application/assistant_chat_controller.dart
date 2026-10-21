import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/utils/tr_time.dart';
import '../copy.dart';
import '../data/assistant_models.dart';
import '../data/assistant_repository.dart';
import 'assistant_gate.dart';

/// Sohbetin durumu (yalnızca bellekte; oturum değişince sıfırlanır).
@immutable
class ChatState {
  const ChatState({
    this.messages = const [],
    this.typing = false,
    this.suggestions,
    this.cooldownUntil,
  });

  /// Eskiden yeniye.
  final List<ChatMessage> messages;

  /// Yanıt bekleniyor ("yazıyor").
  final bool typing;

  /// Başlangıç soruları (null = yükleniyor).
  final List<SuggestionGroup>? suggestions;

  /// 429 sonrası gönderim bu ana kadar kapalı.
  final DateTime? cooldownUntil;

  bool get isEmpty => messages.isEmpty;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? typing,
    List<SuggestionGroup>? Function()? suggestions,
    DateTime? Function()? cooldownUntil,
  }) => ChatState(
    messages: messages ?? this.messages,
    typing: typing ?? this.typing,
    suggestions: suggestions == null ? this.suggestions : suggestions(),
    cooldownUntil: cooldownUntil == null ? this.cooldownUntil : cooldownUntil(),
  );
}

/// Asistan sohbeti (spec A.6, B.11): mesaj gönderme (son 10 mesaj geçmiş olarak gider, onay sürümüyle),
/// "yazıyor", hata balonu (`isError`), gönderilemeyen mesajda "Tekrar dene", geri bildirim, başlangıç
/// soruları (persona; sunucu yanıt vermezse yerel yedek).
final assistantChatProvider =
    NotifierProvider<AssistantChatController, ChatState>(
      AssistantChatController.new,
    );

class AssistantChatController extends Notifier<ChatState> {
  int _epoch = 0;
  int _seq = 0;

  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);

  @override
  ChatState build() {
    ref.watch(currentUserIdProvider);
    _epoch++;
    return const ChatState();
  }

  /// Başlangıç sorularını bir kez yükler.
  Future<void> ensureSuggestions() async {
    if (state.suggestions != null) return;
    final epoch = _epoch;
    List<SuggestionGroup> groups;
    try {
      groups = await _repo.suggestions();
    } catch (_) {
      groups = const [];
    }
    if (epoch != _epoch) return;
    if (groups.every((g) => g.questions.isEmpty)) {
      groups = fallbackSuggestions(ref.read(accessPolicyProvider));
    }
    state = state.copyWith(suggestions: () => groups);
  }

  /// Şu an gönderilebilir mi (yanıt beklenmiyor, bekleme süresi doldu, onay var).
  bool get canSend {
    if (state.typing) return false;
    final cooldown = state.cooldownUntil;
    if (cooldown != null && TrTime.now().isBefore(cooldown)) return false;
    return ref.read(assistantGateProvider) is GateReady;
  }

  /// Mesaj gönderir. Boş, çok uzun ya da [canSend] değilken yok sayılır.
  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty ||
        message.length > AssistantRepository.messageMaxLength ||
        !canSend) {
      return;
    }
    final gate = ref.read(assistantGateProvider) as GateReady;

    final history = [
      for (final m in state.messages)
        if (!m.failed && !m.isError) m,
    ];
    final recent = history.length > AssistantRepository.historyItems
        ? history.sublist(history.length - AssistantRepository.historyItems)
        : history;
    final userMessage = ChatMessage(
      id: _nextId(),
      role: ChatRole.user,
      text: message,
      at: TrTime.now(),
    );
    final epoch = _epoch;
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      typing: true,
      cooldownUntil: () => null,
    );
    try {
      final reply = await _repo.chat(
        message: message,
        history: recent,
        consentVersion: gate.version,
      );
      if (epoch != _epoch) return;
      state = state.copyWith(
        typing: false,
        messages: [
          ...state.messages,
          ChatMessage(
            id: _nextId(),
            role: ChatRole.assistant,
            text: reply.reply.trim().isEmpty
                ? AssistantCopy.emptyReply
                : reply.reply.trim(),
            at: TrTime.now(),
            chatLogId: reply.chatLogId,
            isError: reply.isError,
          ),
        ],
      );
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      var reason = f.message;
      DateTime? until;
      if (f.code == 'consent_required') {
        reason = AssistantCopy.consentAgain;
        unawaited(ref.read(assistantGateProvider.notifier).consentRequired());
      } else if (isAssistantDisabled(f)) {
        reason = f.problem?.detail ?? AssistantCopy.disabledMessage;
        ref.read(assistantGateProvider.notifier).disabled(reason);
      } else if (f is RateLimitedFailure) {
        final wait = f.retryAfter ?? const Duration(seconds: 30);
        until = TrTime.now().add(wait);
      } else if (f is ValidationFailure) {
        reason = f.errorFor('message') ?? f.message;
      }
      state = state.copyWith(
        typing: false,
        cooldownUntil: () => until,
        messages: [
          for (final m in state.messages)
            m.id == userMessage.id
                ? m.copyWith(failed: true, failureMessage: () => reason)
                : m,
        ],
      );
    }
  }

  /// Gönderilemeyen mesajı yeniden dener.
  Future<void> retry(String messageId) async {
    final m = state.messages.where((x) => x.id == messageId).firstOrNull;
    if (m == null || !m.failed || !canSend) return;
    state = state.copyWith(
      messages: [
        for (final x in state.messages)
          if (x.id != messageId) x,
      ],
    );
    await send(m.text);
  }

  /// Yanıta geri bildirim. Hata olursa eski duruma döner ve hatayı döndürür.
  Future<AppFailure?> rate(
    String messageId, {
    required bool helpful,
    String? comment,
  }) async {
    final m = state.messages.where((x) => x.id == messageId).firstOrNull;
    if (m == null || !m.canRate || m.feedback != ChatFeedback.none) {
      return null;
    }
    _setFeedback(messageId, ChatFeedback.sending);
    try {
      await _repo.feedback(
        chatLogId: m.chatLogId!,
        helpful: helpful,
        comment: comment,
      );
      _setFeedback(
        messageId,
        helpful ? ChatFeedback.helpful : ChatFeedback.notHelpful,
      );
      return null;
    } catch (e) {
      _setFeedback(messageId, ChatFeedback.none);
      return AppFailure.from(e);
    }
  }

  /// "Yeni sohbet".
  void clear() {
    _epoch++;
    state = ChatState(suggestions: state.suggestions);
  }

  void _setFeedback(String id, ChatFeedback f) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          m.id == id ? m.copyWith(feedback: f) : m,
      ],
    );
  }

  String _nextId() => '${++_seq}-${newIdempotencyKey().substring(0, 8)}';
}

/// Sunucu soruları gelmezse persona başına başlangıç soruları (spec A.6).
List<SuggestionGroup> fallbackSuggestions(AccessPolicy p) {
  if (p.isCustomer) {
    return const [
      SuggestionGroup(
        category: 'Siparişler',
        questions: ['Siparişim nerede?', 'Teklifi nasıl onaylarım?'],
      ),
      SuggestionGroup(category: 'Ödeme', questions: ['Çek nasıl yüklerim?']),
    ];
  }
  if (p.isDriverOnly) {
    return const [
      SuggestionGroup(
        category: 'Teslimat',
        questions: [
          'Teslimatta imza zorunlu mu?',
          'İnternet yokken teslimat kaydedebilir miyim?',
        ],
      ),
    ];
  }
  if (p.isPlatform) {
    return const [
      SuggestionGroup(
        category: 'Onaylar',
        questions: ['Koşullu onay ne demek?'],
      ),
    ];
  }
  return const [
    SuggestionGroup(
      category: 'Teklifler',
      questions: ['Bugün kaç teklif bekliyor?'],
    ),
    SuggestionGroup(category: 'Onaylar', questions: ['Koşullu onay ne demek?']),
  ];
}
