/// AkaryakıtNet design system — design language v3 "Akış": Plus Jakarta
/// Sans, a calm graphite base with white cards floating on an off-white page,
/// the luminous orange header band and hero card of every home, Phosphor
/// icons and lively, physical motion. Tokens, themes, motion, status,
/// components and painters. Import this one file:
///
/// ```dart
/// import 'package:akaryakitnet/core/ui/ui.dart';
/// ```
///
/// Quick map:
/// * Theme: `AknTheme.light()` / `.dark()`; tokens via `context.akn`
///   ([AknColors]: plate / onPlate, ink, dim, brand marks, brandFill /
///   onBrandFill, chart tokens, `plateInk()`) and `context.aknText`
///   ([AknTextStyles]: Plus Jakarta Sans, tabular figures); spacing
///   [AknSpace], radii [AknRadius], shadows [AknShadows]; driver mode
///   [AknDriverMode].
/// * Icons: `PhosphorIconsRegular` (line), `PhosphorIconsFill` (selected,
///   solid status), `PhosphorIconsBold` — re-exported from phosphor_flutter.
/// * Motion: [AknMotion] (reduce-motion aware), [AknHaptics], [PressScale],
///   [FadeUp], [StaggerScope] + [StaggerItem], [AknAmbient],
///   [FadeThroughIndexedStack], [SharedAxisSwitcher], [FadeThroughSwitcher],
///   [AknOpenContainer], [MorphHero] + [AknHero].
/// * The plate: [AknPlate] (+ PlateHead, PlateFigure, PlateDelta,
///   PlateBars, PlateReadouts, PlateLedger, PlateMeter, PlateRankedBars,
///   PlateFunnel, PlateLine), [RollingFigure], [TriangleGlyph], [LanePager].
/// * Status: [AknLamp] / [StatusChip], [CountdownBadge], [AknStatus];
///   [StageStrip] + [StepTimeline] + [StepperHeader].
/// * Rows and content: [AknListTile], [SectionHeader], [KpiTile] + [KpiRow],
///   [FactRow], [AknBanner], [AknCard] (group box), [AknHomeHeader],
///   [TruckRoute], [PlateBadge] (TR), [AdrPlate], [AttachmentTile].
/// * Actions: [AknButton] (+ secondary / outline / ghost / danger),
///   [DestructiveButton], [AknIconButton], [AknInlineLink], [SlideToConfirm],
///   [showAppSheet], [showConfirmSheet], [showAknDialog], [AppToast] (+ the
///   static [AppToastCard]).
/// * Inputs: [AknTextField] (label above), [AknPasswordField] (+
///   [AknFieldRevealToggle], "Göster"), [MoneyField] (+ `.unitPrice`),
///   [LitersField], [DateField], [SearchField], [PlateField], [AknChip] +
///   [FilterChips], [AknSegmented], [AknTabBar] + [AknTab], [ChoiceCard].
/// * States: [EmptyState], [ErrorState], [ResultView], [LoadingView],
///   [Shimmer] + [SkeletonList] / [SkeletonCard] / [SkeletonBox],
///   [RefreshingContent], [TopProgressBar], [OfflineBanner], [PullToRefresh].
/// * Shell: [AppScaffold], [AppChrome], [AnimatedBottomBar].
/// * Painters: [LogoMark], [AknWordmark], [AknLogo], [ChevronSpinner],
///   [SuccessCheck], [ProgressRing], [TruckRoute], [Sparkline],
///   [EmptyIllustration] (the six §11 drawings).
/// * Dev: `DesignGalleryPage` at `/dev/gallery` (`gallery/`).
library;

export 'package:phosphor_flutter/phosphor_flutter.dart'
    show PhosphorIconsBold, PhosphorIconsFill, PhosphorIconsRegular;

export 'driver_mode.dart';
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
export 'widgets/adr_plate.dart';
export 'widgets/animated_bottom_bar.dart';
export 'widgets/animated_number.dart';
export 'widgets/app_scaffold.dart';
export 'widgets/attachment_tile.dart';
export 'widgets/buttons.dart';
export 'widgets/cards.dart';
export 'widgets/choice_card.dart';
export 'widgets/delta_chip.dart';
export 'widgets/filters.dart';
export 'widgets/hero_header.dart';
export 'widgets/home_header.dart';
export 'widgets/inputs.dart';
export 'widgets/kpi_tile.dart';
export 'widgets/lamp.dart';
export 'widgets/lane_pager.dart';
export 'widgets/open_container.dart';
export 'widgets/plate.dart';
export 'widgets/plate_badge.dart';
export 'widgets/pull_to_refresh.dart';
export 'widgets/rolling_figure.dart';
export 'widgets/sheets.dart';
export 'widgets/skeletons.dart';
export 'widgets/slide_to_confirm.dart';
export 'widgets/stage_strip.dart';
export 'widgets/states.dart';
export 'widgets/status_widgets.dart';
export 'widgets/timeline.dart';
export 'widgets/toast.dart';
export 'widgets/triangle_glyph.dart';
