/// Finance özelliğinin dışa açık yüzü (sahibi A5). Diğer özellikler yalnızca bu dosyayı içe aktarır;
/// özellikler arası gezinme rota yollarıyla yapılır (`AppRoutes`).
///
/// v4 tur 2: Bende'deki finans taleplerini konusuna göre veren sağlayıcı (bayi sipariş ayrıntısı ve
/// listesi, saha ana sayfası da kullanır: "sıra sizde" satırı kararın verildiği sayfayı açar).
library;

export 'application/my_approvals.dart'
    show
        ApprovalSubjects,
        MyApprovals,
        approvalsOfType,
        leadFinanceApprovals,
        myApprovalsBySubjectProvider,
        onboardingApprovals,
        orderFinanceApprovals;
export 'finance_routes.dart' show financeRoutes;
