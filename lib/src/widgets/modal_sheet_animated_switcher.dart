import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Toggle detailed debug logs (development only)
const bool _enableLogs = true;

void _log(String message) {
  if (_enableLogs && kDebugMode) {
    debugPrint('[ModalSheet] $message');
  }
}

const BorderRadius _defaultBorderRadius = BorderRadius.all(Radius.circular(36));
const EdgeInsets _defaultContentPadding = EdgeInsets.symmetric(horizontal: 16);
const Duration _defaultTransitionDuration = Duration(milliseconds: 270);

/// Family App custom easing curve for content transitions (opacity/scale/blur)
const Curve _familyCurve = Cubic(0.26, 0.08, 0.25, 1);

/// Family App custom easing curve for height/size transitions - snappier
const Curve _familySizeCurve = Cubic(0.26, 1, 0.5, 1);

/// Scale animation constants
const double _initialScale = 0.96;
const double _targetScale = 1.0;

/// Blur animation constants
const double _maxBlurSigma = 2.0;

/// Opacity completes at 70% of total duration (~190ms of 270ms)
const double _opacityIntervalEnd = 0.7;

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
    extends State<FamilyModalSheetAnimatedSwitcher>
{
  int _transitionId = 0;
  late Widget _currentWidget;

  @override
  void initState() {
    super.initState();
    _log('INIT: pageIndex=${widget.pageIndex}');

    _currentWidget = _safePageAt(widget.pageIndex);
  }

  @override
  void didUpdateWidget(FamilyModalSheetAnimatedSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.pages != widget.pages) {
      _log('UPDATE: page ${oldWidget.pageIndex} -> ${widget.pageIndex}');
      _startTransition();
    }
  }

  @override
  Widget build(BuildContext context) {
    final transitionDuration = widget.mainContentAnimationStyle?.duration ??
        _defaultTransitionDuration;
    final transitionCurve =
        widget.mainContentAnimationStyle?.curve ?? _familySizeCurve;

    final Widget content = AnimatedSwitcher(
      duration: transitionDuration,
      reverseDuration: transitionDuration,
      // Curves handled in transitionBuilder, so use linear here
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
        transitionBuilder: (child, animation) {
        // Opacity Animation
        // Enter: Full duration (270ms)
        // Exit: First 190ms (70%) of the duration
        // We use reverseCurve with an interval of [0.3, 1.0] because reverse animation
        // goes from 1.0 to 0.0. The interval covers the first 70% of the reverse timeline.
        final opacityAnimation = CurvedAnimation(
          parent: animation,
          curve: _familyCurve,
          reverseCurve: const Interval(
            1.0 - _opacityIntervalEnd, // ~0.3
            1.0,
            curve: _familyCurve,
          ),
        );

        // Scale & Blur Animation
        // Enter & Exit: Full duration (270ms)
        final scaleBlurAnimation = CurvedAnimation(
          parent: animation,
          curve: _familyCurve,
        );

        return FadeTransition(
          opacity: opacityAnimation,
          child: AnimatedBuilder(
            animation: scaleBlurAnimation,
            builder: (context, child) {
              final scale = _initialScale +
                  ((_targetScale - _initialScale) * scaleBlurAnimation.value);
              final blur = _maxBlurSigma * (1 - scaleBlurAnimation.value);

              return Transform.scale(
                scale: scale,
                child: blur > 0.01
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: blur,
                          sigmaY: blur,
                          tileMode: TileMode.decal,
                        ),
                        child: child,
                      )
                    : child,
              );
            },
            child: child,
          ),
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
        child: RepaintBoundary(child: _currentWidget),
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

  @override
  void _startTransition() {
    if (!mounted) return;
    setState(() {
      _currentWidget = _safePageAt(widget.pageIndex);
      _transitionId++;
    });
  }

  Widget _safePageAt(int index) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    final safeIndex = index.clamp(0, widget.pages.length - 1);
    return widget.pages[safeIndex];
  }
}
