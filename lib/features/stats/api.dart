/// İstatistikler (spec R1 §3): ana sayfadaki yönetici destesi ve `/stats` sayfası. Diğer özellikler
/// yalnızca bu dosyayı içe aktarır.
///
/// Ana sayfalar `const ManagerStatsDeck()` ekler (kendi kendini gizler). Müşteri ana sayfası harcama
/// eğrisini `canSeeStatsDeckProvider` true iken gizler. Ana sayfa "aşağı çek yenile" ile desteyi de
/// tazelemek için `refreshManagerStats(ref)` çağrılabilir (isteğe bağlı).
library;

export 'application/stats_providers.dart'
    show
        bayiStatsProvider,
        customerStatsProvider,
        canSeeStatsDeckProvider,
        refreshManagerStats,
        StatsKeys;
export 'application/stats_scope.dart'
    show StatsScope, statsScopeProvider, statsScopeFor;
export 'data/stats_models.dart'
    show BayiStats, CustomerStats, StatsPeriod, StatsSummary;
export 'data/stats_repository.dart'
    show StatsRepository, statsRepositoryProvider;
export 'presentation/deck/manager_stats_deck.dart' show ManagerStatsDeck;
export 'presentation/stats_page.dart' show StatsPage;
export 'stats_fake.dart' show registerStatsFakes;
export 'stats_routes.dart' show statsRoutes;
