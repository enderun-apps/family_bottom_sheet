import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Toggle detailed debug logs (development only)
const bool _enableLogs = false;

void _log(String message) {
  if (_enableLogs && kDebugMode) {
    debugPrint('[ModalSheet] $message');
  }
}

const BorderRadius _defaultBorderRadius = BorderRadius.all(Radius.circular(36));
const EdgeInsets _defaultContentPadding = EdgeInsets.symmetric(horizontal: 16);
const Duration _defaultTransitionDuration = Duration(milliseconds: 270);

/// Family App custom easing curve for content transitions
const Curve _familyCurve = Cubic(0.26, 0.08, 0.25, 1);

/// Family App custom easing curve for height/size transitions - snappier
const Curve _familySizeCurve = Cubic(0.26, 1, 0.5, 1);

const double _initialScale = 0.96;
const double _targetScale = 1.0;

/// Opacity duration
const Duration _opacityDuration = Duration(milliseconds: 100);

/// Track peak animation value to distinguish normal exit from interrupted enter
final Expando<double> _animationPeakValue = Expando<double>();

class FamilyModalSheetAnimatedSwitcher extends StatefulWidget {
  FamilyModalSheetAnimatedSwitcher({
    super.key,
    required this.pageIndex,
    required this.pages,
    required this.contentBackgroundColor,
    this.mainContentAnimationStyle,
    EdgeInsets? mainContentPadding,
    BorderRadius? mainContentBorderRadius,
  })  : mainContentPadding = mainContentPadding ?? _defaultContentPadding,
        mainContentBorderRadius =
            mainContentBorderRadius ?? _defaultBorderRadius,
        assert(pageIndex >= 0 && pageIndex < pages.length && pages.isNotEmpty);

  /// The current index of the page to display
  final int pageIndex;

  /// The list of pages to be display
  final List<Widget> pages;

  /// The background color of the modal sheet
  final Color contentBackgroundColor;

  /// The padding of the main content
  ///
  /// Defaults to `EdgeInsets.symmetric(horizontal: 16)` if no value is passed
  final EdgeInsets mainContentPadding;

  /// The border radius of the main content
  ///
  /// Defaults to placeholder value if no value is passed
  final BorderRadius mainContentBorderRadius;

  /// The animation style of the animated switcher
  final AnimationStyle? mainContentAnimationStyle;

  @override
  State<FamilyModalSheetAnimatedSwitcher> createState() =>
      _FamilyModalSheetAnimatedSwitcherState();
}

class _FamilyModalSheetAnimatedSwitcherState
    extends State<FamilyModalSheetAnimatedSwitcher> {
  int _transitionId = 0;

  @override
  void initState() {
    super.initState();
    _log('INIT: pageIndex=${widget.pageIndex}');
  }

  @override
  void didUpdateWidget(FamilyModalSheetAnimatedSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Sadece sayfa indexi değiştiğinde geçiş animasyonunu tetikle.
    // Eğer sadece liste içeriği değiştiyse (örneğin parent rebuild olduysa)
    // animasyon çalışmasın, sadece içerik güncellensin.
    if (oldWidget.pageIndex != widget.pageIndex) {
      _log('UPDATE: page ${oldWidget.pageIndex} -> ${widget.pageIndex}');
      _transitionId++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final transitionDuration = widget.mainContentAnimationStyle?.duration ??
        _defaultTransitionDuration;
    
    // Ensure duration is not zero to avoid division by zero
    final durationMs = transitionDuration.inMilliseconds > 0 
        ? transitionDuration.inMilliseconds 
        : 1;
        
    final opacityIntervalEnd =
        (_opacityDuration.inMilliseconds / durationMs).clamp(0.0, 1.0);
        
    final transitionCurve =
        widget.mainContentAnimationStyle?.curve ?? _familySizeCurve;

    final currentWidget = _safePageAt(widget.pageIndex);

    final Widget content = AnimatedSwitcher(
      duration: transitionDuration,
      reverseDuration: transitionDuration,
      // Curves handled in transitionBuilder, so use linear here
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      transitionBuilder: (child, animation) {
        final scaleAnimation = CurvedAnimation(
          parent: animation,
          curve: _familyCurve,
          reverseCurve: _familyCurve,
        );

        // Dual formula approach - both enter and exit complete in FIRST 100ms
        // Uses peak value tracking to handle interrupted transitions
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final isExiting = animation.status == AnimationStatus.reverse ||
                animation.status == AnimationStatus.dismissed;

            // Track peak value during forward animation
            if (!isExiting) {
              final currentPeak = _animationPeakValue[animation] ?? 0.0;
              if (animation.value > currentPeak) {
                _animationPeakValue[animation] = animation.value;
              }
            }

            final double opacity;
            if (isExiting) {
              final peak = _animationPeakValue[animation] ?? 1.0;
              
              // Exit Logic:
              // We want to fade out in the first 100ms of the exit animation.
              // The exit animation moves 'value' from 'peak' down to 0.
              // 100ms corresponds to a travel of 'opacityIntervalEnd' in value space.
              
              if (peak > opacityIntervalEnd) {
                 // CASE 1: Fully Opaque or Sustain Phase
                 // We have more than 100ms worth of "opaque" time accumulated.
                 // We map [peak, peak - opacityIntervalEnd] -> Opacity [1.0, 0.0]
                 // This ensures we start fading immediately from 1.0 down to 0.0.
                 final endOfFadeValue = peak - opacityIntervalEnd;
                 opacity = ((animation.value - endOfFadeValue) / opacityIntervalEnd).clamp(0.0, 1.0);
              } else {
                 // CASE 2: Interrupted Fade-In
                 // We never reached full opacity or the "sustain" phase.
                 // We simply reverse the fade-in curve.
                 // This corresponds to retracing the path: Opacity [peakOpacity, 0.0]
                 opacity = (animation.value / opacityIntervalEnd).clamp(0.0, 1.0);
              }
            } else {
              // Enter Logic:
              // Value 0 -> interval maps to Opacity 0 -> 1
              opacity = (animation.value / opacityIntervalEnd).clamp(0.0, 1.0);
            }

            return Opacity(
              opacity: opacity,
              child: ScaleTransition(
                scale: Tween<double>(begin: _initialScale, end: _targetScale)
                    .animate(scaleAnimation),
                child: child,
              ),
            );
          },
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: <Widget>[
            if (currentChild != null) currentChild,
            ...previousChildren.map(
              (child) => Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: ExcludeSemantics(
                    excluding: true,
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: KeyedSubtree(
        key: ValueKey(_transitionId),
        child: RepaintBoundary(child: currentWidget),
      ),
    );

    return Padding(
      padding: widget.mainContentPadding,
      child: ClipRRect(
        borderRadius: widget.mainContentBorderRadius,
        child: ColoredBox(
          color: widget.contentBackgroundColor,
          child: AnimatedSize(
            alignment: Alignment.topCenter,
            duration: transitionDuration,
            curve: transitionCurve,
            clipBehavior: Clip.none,
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _safePageAt(int index) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    final safeIndex = index.clamp(0, widget.pages.length - 1);
    return widget.pages[safeIndex];
  }
}
