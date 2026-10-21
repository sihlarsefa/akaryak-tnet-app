/// Asistan özelliğinin dışa açık yüzü (sahibi A8). Diğer özellikler yalnızca bu dosyayı içe aktarır;
/// özellikler arası gezinme rota yollarıyla yapılır (`AppRoutes.assistant`).
///
/// - [assistantEnabledProvider]: girişler (ana sayfa ikonu / kartı, "Diğer") gösterilsin mi —
///   `features.assistant` açık ve sunucu 503 `assistant_disabled` demedi.
/// - [assistantGateProvider] + [AssistantGate]: onay durumu (Profil > Gizlilik: onayı geri al).
/// - [AssistantAvatar]: duran » LogoMark (yalnızca "yazıyor" iken oklar çizilir).
library;

export 'application/assistant_gate.dart'
    show
        AssistantGate,
        AssistantGateController,
        GateChecking,
        GateDisabled,
        GateError,
        GateNeedsConsent,
        GateReady,
        assistantEnabledProvider,
        assistantGateProvider;
export 'assistant_routes.dart' show assistantRoutes;
export 'presentation/widgets/assistant_avatar.dart' show AssistantAvatar;
