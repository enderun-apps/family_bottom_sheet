import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Toggle detailed debug logs (development only)
const bool _enableLogs = true;

void _log(String message) {
  if (_enableLogs && kDebugMode) {
    debugPrint('[ModalSheet] $message');
  }
}

AnimationStyle _defaultAnimationStyle = AnimationStyle(
    curve: Curves.easeInOutQuad, duration: Duration(milliseconds: 200));
const BorderRadius _defaultBorderRadius = BorderRadius.all(Radius.circular(36));
const EdgeInsets _defaultContentPadding = EdgeInsets.symmetric(horizontal: 16);
const Curve _defaultTransitionCurve = Curves.easeInOutQuad;
const Curve _defaultFadeCurve = Curves.linear;
const Duration _defaultTransitionDuration = Duration(milliseconds: 200);

class FamilyModalSheetAnimatedSwitcher extends StatefulWidget {
  FamilyModalSheetAnimatedSwitcher({
    super.key,
    required this.pageIndex,
    required this.pages,
    required this.contentBackgroundColor,
    AnimationStyle? mainContentAnimationStyle,
    EdgeInsets? mainContentPadding,
    BorderRadius? mainContentBorderRadius,
  })  : mainContentAnimationStyle =
            mainContentAnimationStyle ?? _defaultAnimationStyle,
        mainContentPadding = mainContentPadding ?? _defaultContentPadding,
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
  final AnimationStyle mainContentAnimationStyle;

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
    final transitionDuration = widget.mainContentAnimationStyle.duration ??
        _defaultTransitionDuration;
    final transitionCurve =
        widget.mainContentAnimationStyle.curve ?? _defaultTransitionCurve;

    final Widget content = AnimatedSwitcher(
      duration: transitionDuration,
      reverseDuration: transitionDuration,
      switchInCurve: _defaultFadeCurve,
      switchOutCurve: _defaultFadeCurve,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
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
