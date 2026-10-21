/// Profil özelliğinin dışa açık yüzü (sahibi A8). Diğer özellikler yalnızca bu dosyayı içe aktarır.
///
/// - Rotalar: `/profile` (+ `edit`, `password`, `sessions`, `delete-account`; [ProfilePaths]).
/// - [showSupportSheet]: "Destek ile görüş" (telefon, WhatsApp, e-posta, destek sayfası).
/// - [profileLinkOpenerProvider], [legalUrisProvider], [SupportUris]: yasal metinler uygulama içi
///   tarayıcıda; testler bağlantı açıcıyı ezer.
/// - [confirmAndSignOut]: bekleyen işlem uyarılı çıkış.
library;

export 'application/links.dart'
    show
        LegalUris,
        ProfileLinkOpener,
        SupportUris,
        legalUrisProvider,
        profileLinkOpenerProvider;
export 'application/logout_flow.dart' show confirmAndSignOut;
export 'presentation/support_sheet.dart' show showSupportSheet;
export 'profile_paths.dart' show ProfilePaths;
export 'profile_routes.dart' show profileRoutes;
