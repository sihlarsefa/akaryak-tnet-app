/// Bayi özelliğinin dışa açık yüzü (sahibi A4). Diğer özellikler yalnızca bu dosyayı içe aktarır;
/// özellikler arası gezinme rota yollarıyla yapılır (`AppRoutes`).
///
/// v4: çekirdek (görev kutusu) `application/`, `data/` dışa açımlarını ekledi.
library;

export 'application/home_controller.dart' show bayiHomeProvider;
export 'bayi_routes.dart' show bayiRoutes;
export 'data/bayi_repository.dart' show bayiRepositoryProvider;
export 'data/home_models.dart'
    show
        BayiHomeData,
        BayiDeskSection,
        BayiShipmentsSection,
        BayiApprovalsSection,
        BayiCollectionsSection,
        BayiFinanceSection,
        BayiFieldSection,
        BayiSetupSection;
export 'data/order_models.dart' show BayiOrderCounts, BayiOrderSegment;
export 'presentation/bayi_home.dart' show BayiHome;
