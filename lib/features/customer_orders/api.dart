/// CustomerOrders özelliğinin dışa açık yüzü (sahibi A2). Diğer özellikler yalnızca bu dosyayı içe
/// aktarır; özellikler arası gezinme rota yollarıyla yapılır (`AppRoutes`, [templatesRoute]).
///
/// Müşteri ana sayfası (`customer_home`, A2) ana sayfa verisini, taslak / gönderim durumunu,
/// ödeme belgesi yükleme akışını ve ortak kartları buradan alır.
library;

export 'application/home_controller.dart'
    show customerHomeProvider, orderFormProvider, CustomerHomeController;
export 'application/loadable.dart'
    show Loadable, A2Keys, a2DataRevisionProvider;
export 'application/order_submitter.dart'
    show orderSubmitProvider, SubmitPhase, SubmitState, OrderSubmitController;
export 'application/ordering_config.dart'
    show OrderingConfig, orderingConfigProvider, orderingConfigValueProvider;
export 'application/wizard_store.dart'
    show DraftSummary, draftSummaryProvider, wizardDraftStoreProvider;
export 'copy.dart' show OrdersCopy, QuoteDecisionPresets, withDative;
export 'customer_orders_fake.dart'
    show A2Fake, CustomerOrdersFakeControls, registerCustomerOrdersFakes;
export 'customer_orders_routes.dart' show customerOrdersRoutes;
export 'data/customer_orders_repository.dart'
    show
        CustomerOrdersRepository,
        SpendingMonth,
        customerOrdersRepositoryProvider;
export 'data/form_models.dart' show TemplateListItem;
export 'data/home_models.dart'
    show
        CustomerHomeData,
        CustomerDashboard,
        CustomerLimit,
        CompanyApprovalRule,
        OrderingStatus,
        PendingPaymentDocument,
        StationContact,
        StationOption;
export 'data/order_models.dart' show OrderSegment;
export 'data/payment_models.dart' show PaymentUploadTarget;
export 'presentation/templates_page.dart' show templatesRoute;
export 'presentation/widgets/common.dart'
    show
        FailureView,
        LastUpdatedNote,
        SectionCard,
        ContentWidth,
        ButtonRow,
        FitBadge,
        isLargeText;
export 'presentation/widgets/contact_actions.dart'
    show StationContactButtons, ContactLinks, a2LauncherProvider;
export 'presentation/widgets/payment_document_flow.dart'
    show
        showPaymentDocumentSheet,
        a2DocumentPickerProvider,
        a2DocumentUploaderProvider;
