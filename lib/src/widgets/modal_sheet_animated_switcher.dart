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
    with SingleTickerProviderStateMixin {
  int _transitionId = 0;

  Widget? _currentWidget;
  Widget? _previousWidget;

  late final AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _log('INIT: pageIndex=${widget.pageIndex}');

    _currentWidget = widget.pages.isEmpty
        ? const SizedBox.shrink()
        : widget.pages[widget.pageIndex];
    _previousWidget = null;

    _fadeController = AnimationController(
      vsync: this,
      duration: widget.mainContentAnimationStyle.duration ??
          _defaultTransitionDuration,
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: widget.mainContentAnimationStyle.curve ?? _defaultTransitionCurve,
      reverseCurve: widget.mainContentAnimationStyle.reverseCurve,
    );

    _fadeController.addStatusListener(_handleFadeStatus);
  }

  @override
  void didUpdateWidget(FamilyModalSheetAnimatedSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.pages != widget.pages) {
      _log('UPDATE: page ${oldWidget.pageIndex} -> ${widget.pageIndex}');
      _startTransition();
    }

    final oldDuration =
        oldWidget.mainContentAnimationStyle.duration ?? _defaultTransitionDuration;
    final newDuration =
        widget.mainContentAnimationStyle.duration ?? _defaultTransitionDuration;
    if (oldDuration != newDuration) {
      _fadeController.duration = newDuration;
    }

    // Update curve if changed
    if (oldWidget.mainContentAnimationStyle.curve !=
            widget.mainContentAnimationStyle.curve ||
        oldWidget.mainContentAnimationStyle.reverseCurve !=
            widget.mainContentAnimationStyle.reverseCurve) {
      _fadeAnimation = CurvedAnimation(
        parent: _fadeController,
        curve: widget.mainContentAnimationStyle.curve ?? _defaultTransitionCurve,
        reverseCurve: widget.mainContentAnimationStyle.reverseCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final transitionDuration = widget.mainContentAnimationStyle.duration ??
        _defaultTransitionDuration;
    final transitionCurve =
        widget.mainContentAnimationStyle.curve ?? _defaultTransitionCurve;

    final Widget content = _previousWidget == null
        ? (_currentWidget ?? const SizedBox.shrink())
        : AnimatedBuilder(
            // Tie fade to the same duration/curve as AnimatedSize.
            // This makes opacity and height transitions start together.
            animation: _fadeController,
            builder: (context, child) {
              final t = _fadeAnimation.value;
              final prevOpacity = (1.0 - t).clamp(0.0, 1.0);
              final currOpacity = t.clamp(0.0, 1.0);

              // Current widget defines the size; previous is an overlay and
              // won't affect layout (prevents "max height" behavior).
              return Stack(
                alignment: Alignment.topCenter,
                clipBehavior: Clip.none,
                children: [
                  if (_currentWidget case final current?)
                    Opacity(
                      opacity: currOpacity,
                      child: RepaintBoundary(child: current),
                    )
                  else
                    const SizedBox.shrink(),
                  if (_previousWidget case final previous?)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: true,
                        child: ExcludeSemantics(
                          excluding: true,
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minHeight: 0,
                            maxHeight: double.infinity,
                            child: Opacity(
                              opacity: prevOpacity,
                              child: RepaintBoundary(child: previous),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
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
  void dispose() {
    _fadeController.removeStatusListener(_handleFadeStatus);
    _fadeController.dispose();
    super.dispose();
  }

  void _handleFadeStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status != AnimationStatus.completed) return;

    // Only clear if nothing newer has started.
    final localTransitionId = _transitionId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_transitionId != localTransitionId) return;
      if (_previousWidget == null) return;
      setState(() => _previousWidget = null);
    });
  }

  void _startTransition() {
    if (!mounted) return;
    if (widget.pages.isEmpty) {
      setState(() {
        _previousWidget = null;
        _currentWidget = const SizedBox.shrink();
        _transitionId++;
      });
      return;
    }

    // Defensive: avoid range errors if pages changed unexpectedly.
    final nextIndex = widget.pageIndex.clamp(0, widget.pages.length - 1);
    final nextWidget = widget.pages[nextIndex];

    setState(() {
      _previousWidget = _currentWidget;
      _currentWidget = nextWidget;
      _transitionId++;
    });

    // Start fade aligned with AnimatedSize duration/curve.
    _fadeController.forward(from: 0.0);
  }
}
