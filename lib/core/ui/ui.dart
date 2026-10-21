/// AkaryakıtNet design system (M0b): tokens, themes, motion, status styles,
/// components and painters. Import this one file:
///
/// ```dart
/// import 'package:akaryakitnet/core/ui/ui.dart';
/// ```
///
/// Quick map:
/// * Theme: `AknTheme.light()` / `.dark()`; tokens via `context.akn`
///   ([AknColors]) and `context.aknText` ([AknTextStyles]); spacing
///   [AknSpace], radii [AknRadius], shadows [AknShadows].
/// * Motion: [AknMotion] timings (reduce-motion aware), [AknHaptics],
///   [FadeUp], [StaggerScope] + [StaggerItem], [PressScale],
///   [FadeThroughIndexedStack] (tab switch), [SharedAxisSwitcher] (wizard
///   steps), [FadeThroughSwitcher], [AknOpenContainer] (container transform,
///   list → detail), [MorphHero] + [AknHero] + [AknHeroTags] (same-navigator
///   heroes), page transitions in the theme.
/// * Status: `order.status.statusStyle` → [StatusStyle] → [StatusChip.style];
///   [AknStatus] maps every server enum, barem bands and server tone keys.
/// * Actions: [AknButton] (+ `.secondary/.ghost/.danger`, async morph),
///   [AknIconButton], [SlideToConfirm], [showConfirmSheet], [showAppSheet],
///   [showAknDialog], [AppToast].
/// * Content: [AknCard], [AknHeroPanel] (navy, re-themes its content),
///   [AknListTile], [SectionHeader], [KpiTile] + [KpiRow], [FactRow], [AknBanner],
///   [UsageBar], [AmountText], [AknAvatar], [AknCountBadge], [PlateBadge],
///   [AttachmentTile], [StepTimeline], [StepperHeader], [CountdownBadge].
/// * Inputs: [AknTextField], [MoneyField] (+ `.unitPrice`), [LitersField],
///   [DateField], [SearchField], [PlateField], [FilterChips], [AknSegmented],
///   [ChoiceCard] (payment method, delivery point, driver).
/// * States: [EmptyState], [ErrorState], [ResultView], [LoadingView], [Shimmer] +
///   [SkeletonList] / [SkeletonCard] / [SkeletonBox], [TopProgressBar],
///   [OfflineBanner], [PullToRefresh].
/// * Shell: [AppScaffold] (bell, offline banner, refresh bar, action bar),
///   [AppChrome] (provided once by the shell), [AnimatedBottomBar].
/// * Painters: [LogoMark], [AknWordmark], [AknLogo], [ChevronSpinner],
///   [SuccessCheck], [ProgressRing], [FuelDrop], [TruckRoute], [Sparkline],
///   [EmptyIllustration].
/// * Dev: `DesignGalleryPage` at `/dev/gallery` (`gallery/`).
library;

export 'motion.dart';
export 'painters/chevron_spinner.dart';
export 'painters/empty_illustration.dart';
export 'painters/fuel_drop.dart';
export 'painters/hero_backdrop.dart';
export 'painters/logo_mark.dart';
export 'painters/progress_ring.dart';
export 'painters/sparkline.dart';
export 'painters/success_check.dart';
export 'painters/truck_route.dart';
export 'status.dart';
export 'theme.dart';
export 'tokens.dart';
export 'typography.dart';
export 'widgets/animated_bottom_bar.dart';
export 'widgets/app_scaffold.dart';
export 'widgets/attachment_tile.dart';
export 'widgets/buttons.dart';
export 'widgets/cards.dart';
export 'widgets/choice_card.dart';
export 'widgets/filters.dart';
export 'widgets/inputs.dart';
export 'widgets/kpi_tile.dart';
export 'widgets/open_container.dart';
export 'widgets/plate_badge.dart';
export 'widgets/pull_to_refresh.dart';
export 'widgets/sheets.dart';
export 'widgets/skeletons.dart';
export 'widgets/slide_to_confirm.dart';
export 'widgets/states.dart';
export 'widgets/status_widgets.dart';
export 'widgets/timeline.dart';
export 'widgets/toast.dart';
