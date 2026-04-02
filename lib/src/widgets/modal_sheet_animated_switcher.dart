import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Toggle detailed debug logs (development only)
const bool _enableLogs = false;

void _log(String message) {
  if (_enableLogs && kDebugMode) {
    debugPrint('[ModalSheet] $message');
  }
}

const BorderRadius _defaultBorderRadius =
    BorderRadius.all(Radius.circular(36));
const EdgeInsets _defaultContentPadding =
    EdgeInsets.symmetric(horizontal: 16);

// ─── Timing ──────────────────────────────────────────────────────────────────

/// Page/sheet transitions: 250ms.
/// Aligned with animation-design.mdc duration guide and AppAnimation.duration.
/// Snappier than 270ms while staying within the 200-300ms modal range.
const Duration _defaultTransitionDuration = Duration(milliseconds: 250);

/// Opacity completes in the first 100ms — fast crossfade that doesn't linger.
const Duration _opacityDuration = Duration(milliseconds: 100);

// ─── Curves ──────────────────────────────────────────────────────────────────

/// Enter: easeOutCubic — fast start, soft settle. iOS-native feel.
/// animation-design.mdc: "Sheet/modal opening → Curves.easeOutCubic"
const Curve _enterCurve = Curves.easeOutCubic;

/// Reverse: easeInCubic — during reverse (1→0) this produces ease-out FEEL.
/// Parent goes 1→0: easeInCubic drops FAST then slows = responsive exit.
/// animation-design.mdc: "CurvedAnimation.reverseCurve math"
const Curve _exitCurve = Curves.easeInCubic;

/// Size curve — snappy with subtle overshoot for height transitions.
const Curve _sizeCurve = Cubic(0.26, 1.0, 0.5, 1.0);

// ─── Scale ───────────────────────────────────────────────────────────────────

/// Subtle scale-in for card-level crossfade transitions.
const double _initialScale = 0.97;
const double _targetScale = 1.0;

// ─── Blur ────────────────────────────────────────────────────────────────────

/// web-animation-design.mdc: "Toggle/swap → blur+fade crossfade (blur 4px)"
/// practical-tips.mdc: "Add subtle blur (under 20px) to mask imperfections"
/// 4px matches the "toggle/swap crossfade → blur 4px" rule exactly.
/// Kept under the 20px performance ceiling (especially important on iOS).
const double _maxBlurSigma = 4.0;

/// Track peak animation value to distinguish normal exit from interrupted enter.
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
    if (oldWidget.pageIndex != widget.pageIndex) {
      _log('UPDATE: page ${oldWidget.pageIndex} -> ${widget.pageIndex}');
      _transitionId++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final transitionDuration =
        widget.mainContentAnimationStyle?.duration ??
            _defaultTransitionDuration;

    final durationMs = transitionDuration.inMilliseconds > 0
        ? transitionDuration.inMilliseconds
        : 1;

    final opacityIntervalEnd =
        (_opacityDuration.inMilliseconds / durationMs).clamp(0.0, 1.0);

    final transitionCurve =
        widget.mainContentAnimationStyle?.curve ?? _sizeCurve;

    final currentWidget = _safePageAt(widget.pageIndex);

    final Widget content = AnimatedSwitcher(
      duration: transitionDuration,
      reverseDuration: transitionDuration,
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      transitionBuilder: (child, animation) {
        final scaleAnimation = CurvedAnimation(
          parent: animation,
          curve: _enterCurve,
          reverseCurve: _exitCurve,
        );

        // GlobalObjectKey lets Flutter track and reparent this element
        // when the layoutBuilder moves it into Positioned.fill for exit.
        // Without it, the child's State is destroyed and recreated
        // (scroll position lost, data reloaded → visible flash).
        return AnimatedBuilder(
          key: GlobalObjectKey(animation),
          animation: animation,
          builder: (context, _) {
            final isExiting =
                animation.status == AnimationStatus.reverse ||
                    animation.status == AnimationStatus.dismissed;

            if (!isExiting) {
              final currentPeak =
                  _animationPeakValue[animation] ?? 0.0;
              if (animation.value > currentPeak) {
                _animationPeakValue[animation] = animation.value;
              }
            }

            // ── Opacity ─────────────────────────────────────────────
            final double opacity;
            if (isExiting) {
              final peak = _animationPeakValue[animation] ?? 1.0;
              if (peak > opacityIntervalEnd) {
                final endOfFadeValue = peak - opacityIntervalEnd;
                opacity = ((animation.value - endOfFadeValue) /
                        opacityIntervalEnd)
                    .clamp(0.0, 1.0);
              } else {
                opacity = (animation.value / opacityIntervalEnd)
                    .clamp(0.0, 1.0);
              }
            } else {
              opacity = (animation.value / opacityIntervalEnd)
                  .clamp(0.0, 1.0);
            }

            // ── Scale ───────────────────────────────────────────────
            final scaleValue =
                _initialScale +
                    (_targetScale - _initialScale) *
                        scaleAnimation.value;

            // ── Blur ────────────────────────────────────────────────
            final blurProgress =
                (1.0 - scaleAnimation.value).clamp(0.0, 1.0);
            final sigma = _maxBlurSigma * blurProgress;

            // ── Compose layers ──────────────────────────────────────
            // Tree shape is ALWAYS stable:
            //   ExcludeSemantics → IgnorePointer → Opacity →
            //   ImageFiltered → Transform → child
            // IgnorePointer/ExcludeSemantics toggle via isExiting,
            // keeping the structure identical for enter and exit so
            // Flutter never tears down and recreates elements.
            return ExcludeSemantics(
              excluding: isExiting,
              child: IgnorePointer(
                ignoring: isExiting,
                child: Opacity(
                  opacity: opacity,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: sigma,
                      sigmaY: sigma,
                      tileMode: TileMode.decal,
                    ),
                    child: Transform.scale(
                      scale: scaleValue,
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: <Widget>[
                if (currentChild != null) currentChild,
                ...previousChildren.map(
                  (child) => Positioned.fill(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: constraints.maxHeight,
                      child: child,
                    ),
                  ),
                ),
              ],
            );
          },
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
