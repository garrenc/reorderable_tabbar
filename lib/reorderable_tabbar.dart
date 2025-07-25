library reorderable_tabbar;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:tab_indicator_styler/tab_indicator_styler.dart';

const double _kTabHeight = 46.0;
const double _kTextAndIconTabHeight = 72.0;

class _TabStyle extends AnimatedWidget {
  const _TabStyle({
    Key? key,
    required Animation<double> animation,
    required this.selected,
    required this.labelColor,
    required this.unselectedLabelColor,
    required this.labelStyle,
    required this.unselectedLabelStyle,
    required this.child,
  }) : super(key: key, listenable: animation);

  final TextStyle? labelStyle;
  final TextStyle? unselectedLabelStyle;
  final bool selected;
  final Color? labelColor;
  final Color? unselectedLabelColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    final TabBarThemeData tabBarTheme = TabBarTheme.of(context);
    final TabBarTheme defaults = themeData.useMaterial3 ? _TabsDefaultsM3(context) : _TabsDefaultsM2(context);
    final Animation<double> animation = listenable as Animation<double>;

    // To enable TextStyle.lerp(style1, style2, value), both styles must have
    // the same value of inherit. Force that to be inherit=true here.
    final TextStyle defaultStyle = (labelStyle ?? tabBarTheme.labelStyle ?? defaults.labelStyle!).copyWith(inherit: true);
    final TextStyle defaultUnselectedStyle = (unselectedLabelStyle ?? tabBarTheme.unselectedLabelStyle ?? labelStyle ?? defaults.unselectedLabelStyle!).copyWith(inherit: true);
    final TextStyle textStyle = selected ? TextStyle.lerp(defaultStyle, defaultUnselectedStyle, animation.value)! : TextStyle.lerp(defaultUnselectedStyle, defaultStyle, animation.value)!;

    final Color selectedColor = labelColor ?? tabBarTheme.labelColor ?? defaults.labelColor!;
    final Color unselectedColor = unselectedLabelColor ?? tabBarTheme.unselectedLabelColor ?? (themeData.useMaterial3 ? defaults.unselectedLabelColor! : selectedColor.withAlpha(0xB2)); // 70% alpha
    final Color color = selected ? Color.lerp(selectedColor, unselectedColor, animation.value)! : Color.lerp(unselectedColor, selectedColor, animation.value)!;

    return DefaultTextStyle(
      style: textStyle.copyWith(color: color),
      child: IconTheme.merge(
        data: IconThemeData(
          size: 24.0,
          color: color,
        ),
        child: child,
      ),
    );
  }
}

double _indexChangeProgress(TabController controller) {
  final double controllerValue = controller.animation!.value;
  final double previousIndex = controller.previousIndex.toDouble();
  final double currentIndex = controller.index.toDouble();

  if (!controller.indexIsChanging) {
    return (currentIndex - controllerValue).abs().clamp(0.0, 1.0);
  }

  return (controllerValue - currentIndex).abs() / (currentIndex - previousIndex).abs();
}

class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter({
    required this.controller,
    required this.indicator,
    required this.indicatorSize,
    required this.tabKeys,
    required _IndicatorPainter? old,
    required this.indicatorPadding,
  }) : super(repaint: controller.animation) {
    if (old != null) {
      saveTabOffsets(old._currentTabOffsets, old._currentTextDirection);
    }
  }

  final TabController controller;
  final Decoration indicator;
  final TabBarIndicatorSize? indicatorSize;
  final EdgeInsetsGeometry indicatorPadding;
  final List<GlobalKey> tabKeys;

  // _currentTabOffsets and _currentTextDirection are set each time TabBar
  // layout is completed. These values can be null when TabBar contains no
  // tabs, since there are nothing to lay out.
  List<double>? _currentTabOffsets;
  TextDirection? _currentTextDirection;

  Rect? _currentRect;
  BoxPainter? _painter;
  bool _needsPaint = false;
  void markNeedsPaint() {
    _needsPaint = true;
  }

  void dispose() {
    _painter?.dispose();
  }

  void saveTabOffsets(List<double>? tabOffsets, TextDirection? textDirection) {
    _currentTabOffsets = tabOffsets;
    _currentTextDirection = textDirection;
  }

  int get maxTabIndex => _currentTabOffsets!.length - 2;

  double centerOf(int tabIndex) {
    assert(_currentTabOffsets != null);
    assert(_currentTabOffsets!.isNotEmpty);
    assert(tabIndex >= 0);
    assert(tabIndex <= maxTabIndex);
    return (_currentTabOffsets![tabIndex] + _currentTabOffsets![tabIndex + 1]) / 2.0;
  }

  Rect indicatorRect(Size tabBarSize, int tabIndex) {
    assert(_currentTabOffsets != null);
    assert(_currentTextDirection != null);
    assert(_currentTabOffsets!.isNotEmpty);
    assert(tabIndex >= 0);
    assert(tabIndex <= maxTabIndex);
    double tabLeft, tabRight;
    switch (_currentTextDirection!) {
      case TextDirection.rtl:
        tabLeft = _currentTabOffsets![tabIndex + 1];
        tabRight = _currentTabOffsets![tabIndex];
        break;
      case TextDirection.ltr:
        tabLeft = _currentTabOffsets![tabIndex];
        tabRight = _currentTabOffsets![tabIndex + 1];
        break;
    }

    if (indicatorSize == TabBarIndicatorSize.label) {
      final double tabWidth = tabKeys[tabIndex].currentContext!.size!.width;
      final double delta = ((tabRight - tabLeft) - tabWidth) / 2.0;
      tabLeft += delta;
      tabRight -= delta;
    }

    final EdgeInsets insets = indicatorPadding.resolve(_currentTextDirection);
    final Rect rect = Rect.fromLTWH(tabLeft, 0.0, tabRight - tabLeft, tabBarSize.height);

    if (!(rect.size >= insets.collapsedSize)) {
      throw FlutterError(
        'indicatorPadding insets should be less than Tab Size\n'
        'Rect Size : ${rect.size}, Insets: ${insets.toString()}',
      );
    }
    return insets.deflateRect(rect);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _needsPaint = false;
    _painter ??= indicator.createBoxPainter(markNeedsPaint);

    final double index = controller.index.toDouble();
    final double value = controller.animation!.value;
    final bool ltr = index > value;
    final int from = (ltr ? value.floor() : value.ceil()).clamp(0, maxTabIndex);
    final int to = (ltr ? from + 1 : from - 1).clamp(0, maxTabIndex);
    final Rect fromRect = indicatorRect(size, from);
    final Rect toRect = indicatorRect(size, to);
    _currentRect = Rect.lerp(fromRect, toRect, (value - from).abs());
    assert(_currentRect != null);

    final ImageConfiguration configuration = ImageConfiguration(
      size: _currentRect!.size,
      textDirection: _currentTextDirection,
    );
    _painter!.paint(canvas, _currentRect!.topLeft, configuration);
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) {
    bool rePaint = _needsPaint ||
        controller != old.controller ||
        indicator != old.indicator ||
        tabKeys.length != old.tabKeys.length ||
        (!listEquals(_currentTabOffsets, old._currentTabOffsets)) ||
        _currentTextDirection != old._currentTextDirection;

    return rePaint;
  }
}

class _ChangeAnimation extends Animation<double> with AnimationWithParentMixin<double> {
  _ChangeAnimation(this.controller);

  final TabController controller;

  @override
  Animation<double> get parent => controller.animation!;

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    if (controller.animation != null) super.removeStatusListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (controller.animation != null) super.removeListener(listener);
  }

  @override
  double get value => _indexChangeProgress(controller);
}

class _DragAnimation extends Animation<double> with AnimationWithParentMixin<double> {
  _DragAnimation(this.controller, this.index);

  final TabController controller;
  final int index;

  @override
  Animation<double> get parent => controller.animation!;

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    if (controller.animation != null) super.removeStatusListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (controller.animation != null) super.removeListener(listener);
  }

  @override
  double get value {
    assert(!controller.indexIsChanging);
    final double controllerMaxValue = (controller.length - 1).toDouble();
    final double controllerValue = controller.animation!.value.clamp(0.0, controllerMaxValue);
    return (controllerValue - index.toDouble()).abs().clamp(0.0, 1.0);
  }
}

typedef OnReorder = void Function(int, int);

class ReorderableTabBar extends StatefulWidget implements PreferredSizeWidget {
  const ReorderableTabBar({
    Key? key,
    required this.tabs,
    this.controller,
    this.isScrollable = false,
    this.padding,
    this.indicatorColor,
    this.automaticIndicatorColorAdjustment = true,
    this.indicatorWeight = 2.0,
    this.indicatorPadding = EdgeInsets.zero,
    this.indicator,
    this.indicatorSize,
    this.labelColor,
    this.labelStyle,
    this.labelPadding,
    this.unselectedLabelColor,
    this.unselectedLabelStyle,
    this.dragStartBehavior = DragStartBehavior.start,
    this.overlayColor,
    this.mouseCursor,
    this.enableFeedback,
    this.onTap,
    this.physics,
    this.onReorder,
    this.defaultIndicator = false,
    this.tabBorderRadius,
    this.reorderingTabBackgroundColor,
    this.tabBackgroundColor,
    this.buildDefaultDragHandles = true,
    this.useDelayedDragStartListener = false,
  })  : assert(indicator != null || (indicatorWeight > 0.0)),
        super(key: key);

  /// if false use `useDelayedDragStartListener` variable
  final bool buildDefaultDragHandles;

  /// uses the widget `ReorderableDelayedDragStartListener` if true and `ReorderableDragStartListener` if false
  final bool useDelayedDragStartListener;

  final BorderRadius? tabBorderRadius;

  final Color? tabBackgroundColor;

  final bool defaultIndicator;

  final OnReorder? onReorder;

  final Color? reorderingTabBackgroundColor;

  /// Typically a list of two or more [Tab] widgets.
  ///
  /// The length of this list must match the [controller]'s [TabController.length]
  /// and the length of the [TabBarView.children] list.
  final List<Widget> tabs;

  /// This widget's selection and animation state.
  ///
  /// If [TabController] is not provided, then the value of [DefaultTabController.of]
  /// will be used.
  final TabController? controller;

  /// Whether this tab bar can be scrolled horizontally.
  ///
  /// If [isScrollable] is true, then each tab is as wide as needed for its label
  /// and the entire [TabBar] is scrollable. Otherwise each tab gets an equal
  /// share of the available space.
  final bool isScrollable;

  /// The amount of space by which to inset the tab bar.
  ///
  /// When [isScrollable] is false, this will yield the same result as if you had wrapped your
  /// [TabBar] in a [Padding] widget. When [isScrollable] is true, the scrollable itself is inset,
  /// allowing the padding to scroll with the tab bar, rather than enclosing it.
  final EdgeInsetsGeometry? padding;

  /// The color of the line that appears below the selected tab.
  ///
  /// If this parameter is null, then the value of the Theme's indicatorColor
  /// property is used.
  ///
  /// If [indicator] is specified or provided from [TabBarTheme],
  /// this property is ignored.
  final Color? indicatorColor;

  /// The thickness of the line that appears below the selected tab.
  ///
  /// The value of this parameter must be greater than zero and its default
  /// value is 2.0.
  ///
  /// If [indicator] is specified or provided from [TabBarTheme],
  /// this property is ignored.
  final double indicatorWeight;

  /// Padding for indicator.
  /// This property will now no longer be ignored even if indicator is declared
  /// or provided by [TabBarTheme]
  ///
  /// For [isScrollable] tab bars, specifying [kTabLabelPadding] will align
  /// the indicator with the tab's text for [Tab] widgets and all but the
  /// shortest [Tab.text] values.
  ///
  /// The default value of [indicatorPadding] is [EdgeInsets.zero].
  final EdgeInsetsGeometry indicatorPadding;

  /// Defines the appearance of the selected tab indicator.
  ///
  /// If [indicator] is specified or provided from [TabBarTheme],
  /// the [indicatorColor], and [indicatorWeight] properties are ignored.
  ///
  /// The default, underline-style, selected tab indicator can be defined with
  /// [UnderlineTabIndicator].
  ///
  /// The indicator's size is based on the tab's bounds. If [indicatorSize]
  /// is [TabBarIndicatorSize.tab] the tab's bounds are as wide as the space
  /// occupied by the tab in the tab bar. If [indicatorSize] is
  /// [TabBarIndicatorSize.label], then the tab's bounds are only as wide as
  /// the tab widget itself.
  final Decoration? indicator;

  /// Whether this tab bar should automatically adjust the [indicatorColor].
  ///
  /// If [automaticIndicatorColorAdjustment] is true,
  /// then the [indicatorColor] will be automatically adjusted to [Colors.white]
  /// when the [indicatorColor] is same as [Material.color] of the [Material] parent widget.
  final bool automaticIndicatorColorAdjustment;

  /// Defines how the selected tab indicator's size is computed.
  ///
  /// The size of the selected tab indicator is defined relative to the
  /// tab's overall bounds if [indicatorSize] is [TabBarIndicatorSize.tab]
  /// (the default) or relative to the bounds of the tab's widget if
  /// [indicatorSize] is [TabBarIndicatorSize.label].
  ///
  /// The selected tab's location appearance can be refined further with
  /// the [indicatorColor], [indicatorWeight], [indicatorPadding], and
  /// [indicator] properties.
  final TabBarIndicatorSize? indicatorSize;

  /// The color of selected tab labels.
  ///
  /// Unselected tab labels are rendered with the same color rendered at 70%
  /// opacity unless [unselectedLabelColor] is non-null.
  ///
  /// If this parameter is null, then the color of the [ThemeData.primaryTextTheme]'s
  /// bodyText1 text color is used.
  final Color? labelColor;

  /// The color of unselected tab labels.
  ///
  /// If this property is null, unselected tab labels are rendered with the
  /// [labelColor] with 70% opacity.
  final Color? unselectedLabelColor;

  /// The text style of the selected tab labels.
  ///
  /// If [unselectedLabelStyle] is null, then this text style will be used for
  /// both selected and unselected label styles.
  ///
  /// If this property is null, then the text style of the
  /// [ThemeData.primaryTextTheme]'s bodyText1 definition is used.
  final TextStyle? labelStyle;

  /// The padding added to each of the tab labels.
  ///
  /// If there are few tabs with both icon and text and few
  /// tabs with only icon or text, this padding is vertically
  /// adjusted to provide uniform padding to all tabs.
  ///
  /// If this property is null, then kTabLabelPadding is used.
  final EdgeInsetsGeometry? labelPadding;

  /// The text style of the unselected tab labels.
  ///
  /// If this property is null, then the [labelStyle] value is used. If [labelStyle]
  /// is null, then the text style of the [ThemeData.primaryTextTheme]'s
  /// bodyText1 definition is used.
  final TextStyle? unselectedLabelStyle;

  /// Defines the ink response focus, hover, and splash colors.
  ///
  /// If non-null, it is resolved against one of [MaterialState.focused],
  /// [MaterialState.hovered], and [MaterialState.pressed].
  ///
  /// [MaterialState.pressed] triggers a ripple (an ink splash), per
  /// the current Material Design spec. The [overlayColor] doesn't map
  /// a state to [InkResponse.highlightColor] because a separate highlight
  /// is not used by the current design guidelines. See
  /// https://material.io/design/interaction/states.html#pressed
  ///
  /// If the overlay color is null or resolves to null, then the default values
  /// for [InkResponse.focusColor], [InkResponse.hoverColor], [InkResponse.splashColor]
  /// will be used instead.
  final MaterialStateProperty<Color?>? overlayColor;

  /// {@macro flutter.widgets.scrollable.dragStartBehavior}
  final DragStartBehavior dragStartBehavior;

  /// The cursor for a mouse pointer when it enters or is hovering over the
  /// individual tab widgets.
  ///
  /// If this property is null, [SystemMouseCursors.click] will be used.
  final MouseCursor? mouseCursor;

  /// Whether detected gestures should provide acoustic and/or haptic feedback.
  ///
  /// For example, on Android a tap will produce a clicking sound and a long-press
  /// will produce a short vibration, when feedback is enabled.
  ///
  /// Defaults to true.
  final bool? enableFeedback;

  /// An optional callback that's called when the [TabBar] is tapped.
  ///
  /// The callback is applied to the index of the tab where the tap occurred.
  ///
  /// This callback has no effect on the default handling of taps. It's for
  /// applications that want to do a little extra work when a tab is tapped,
  /// even if the tap doesn't change the TabController's index. TabBar [onTap]
  /// callbacks should not make changes to the TabController since that would
  /// interfere with the default tap handler.
  final ValueChanged<int>? onTap;

  /// How the [TabBar]'s scroll view should respond to user input.
  ///
  /// For example, determines how the scroll view continues to animate after the
  /// user stops dragging the scroll view.
  ///
  /// Defaults to matching platform conventions.
  final ScrollPhysics? physics;

  /// A size whose height depends on if the tabs have both icons and text.
  ///
  /// [AppBar] uses this size to compute its own preferred size.
  @override
  Size get preferredSize {
    double maxHeight = _kTabHeight;
    for (final Widget item in tabs) {
      if (item is PreferredSizeWidget) {
        final double itemHeight = item.preferredSize.height;
        maxHeight = math.max(itemHeight, maxHeight);
      }
    }
    return Size.fromHeight(maxHeight + indicatorWeight);
  }

  /// Returns whether the [TabBar] contains a tab with both text and icon.
  ///
  /// [TabBar] uses this to give uniform padding to all tabs in cases where
  /// there are some tabs with both text and icon and some which contain only
  /// text or icon.
  bool get tabHasTextAndIcon {
    for (final Widget item in tabs) {
      if (item is PreferredSizeWidget) {
        if (item.preferredSize.height == _kTextAndIconTabHeight) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  State<ReorderableTabBar> createState() => _ReorderableTabBarState();
}

class _ReorderableTabBarState extends State<ReorderableTabBar> {
  ScrollController? _scrollController;
  TabController? _controller;
  _IndicatorPainter? _indicatorPainter;
  ScrollController? _reorderController;
  int? _currentIndex;
  double? _tabStripWidth;
  List<double> xOffsets = [];
  double? height;
  bool isScrollToCurrentIndex = false;
  Reordered? isReordered;
  late double screenWidth;
  late List<GlobalKey> _tabKeys;
  late List<GlobalKey> _tabExtendKeys;
  late LinkedScrollControllerGroup _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = LinkedScrollControllerGroup();
    _reorderController = _controllers.addAndGet();
    _scrollController = _controllers.addAndGet();
    _tabKeys = widget.tabs.map((Widget tab) => GlobalKey()).toList();
    _tabExtendKeys = widget.tabs.map((Widget tab) => GlobalKey()).toList();
  }

  Decoration get _indicator {
    final ThemeData theme = Theme.of(context);
    final TabBarThemeData tabBarTheme = TabBarTheme.of(context);
    final TabBarTheme defaults = theme.useMaterial3 ? _TabsDefaultsM3(context) : _TabsDefaultsM2(context);

    if (widget.indicator != null) {
      return widget.indicator!;
    }
    if (tabBarTheme.indicator != null) {
      return tabBarTheme.indicator!;
    }

    Color color = widget.indicatorColor ?? (theme.useMaterial3 ? tabBarTheme.indicatorColor ?? defaults.indicatorColor! : Theme.of(context).indicatorColor);
    // ThemeData tries to avoid this by having indicatorColor avoid being the
    // primaryColor. However, it's possible that the tab bar is on a
    // Material that isn't the primaryColor. In that case, if the indicator
    // color ends up matching the material's color, then this overrides it.
    // When that happens, automatic transitions of the theme will likely look
    // ugly as the indicator color suddenly snaps to white at one end, but it's
    // not clear how to avoid that any further.
    //
    // The material's color might be null (if it's a transparency). In that case
    // there's no good way for us to find out what the color is so we don't.
    //
    // TODO(xu-baolin): Remove automatic adjustment to white color indicator
    // with a better long-term solution.
    // https://github.com/flutter/flutter/pull/68171#pullrequestreview-517753917
    if (widget.automaticIndicatorColorAdjustment && color.value == Material.maybeOf(context)?.color?.value) {
      color = Colors.white;
    }

    if (widget.defaultIndicator) {
      return UnderlineTabIndicator(
        borderSide: BorderSide(
          width: widget.indicatorWeight,
          color: color,
        ),
      );
    }

    return MaterialIndicator(
      height: widget.indicatorWeight,
      color: color,
      tabPosition: TabPosition.bottom,
    );
  }

  // If the TabBar is rebuilt with a new tab controller, the caller should
  // dispose the old one. In that case the old controller's animation will be
  // null and should not be accessed.
  bool get _controllerIsValid => _controller?.animation != null;

  void _updateTabController() {
    final TabController newController = widget.controller ?? DefaultTabController.of(context);

    if (newController == _controller) return;

    if (_controllerIsValid) {
      _controller!.animation!.removeListener(_handleTabControllerAnimationTick);
      _controller!.removeListener(_handleTabControllerTick);
    }
    _controller = newController;
    if (_controller != null) {
      _controller!.animation!.addListener(_handleTabControllerAnimationTick);
      _controller!.addListener(_handleTabControllerTick);
      _currentIndex = _controller!.index;
    }
  }

  void _initIndicatorPainter() {
    _indicatorPainter = !_controllerIsValid
        ? null
        : _IndicatorPainter(
            controller: _controller!,
            indicator: _indicator,
            indicatorSize: widget.indicatorSize ?? TabBarTheme.of(context).indicatorSize,
            indicatorPadding: widget.indicatorPadding,
            tabKeys: _tabKeys,
            old: _indicatorPainter,
          );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    assert(debugCheckHasMaterial(context));
    screenWidth = MediaQuery.of(context).size.width;
    _updateTabController();
    _initIndicatorPainter();
  }

  @override
  void didUpdateWidget(ReorderableTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      _updateTabController();
      _initIndicatorPainter();
    } else if (widget.indicatorColor != oldWidget.indicatorColor ||
        widget.indicatorWeight != oldWidget.indicatorWeight ||
        widget.indicatorSize != oldWidget.indicatorSize ||
        widget.indicator != oldWidget.indicator) {
      _initIndicatorPainter();
    }

    if (widget.tabs.length > oldWidget.tabs.length) {
      final int delta = widget.tabs.length - oldWidget.tabs.length;
      _tabKeys.addAll(List<GlobalKey>.generate(delta, (int n) => GlobalKey()));
      _tabExtendKeys.addAll(List<GlobalKey>.generate(delta, (int n) => GlobalKey()));
    } else if (widget.tabs.length < oldWidget.tabs.length) {
      _tabKeys.removeRange(widget.tabs.length, oldWidget.tabs.length);
      _tabExtendKeys.removeRange(widget.tabs.length, oldWidget.tabs.length);
    }
    if (!listEquals(oldWidget.tabs, widget.tabs)) {
      if (isReordered != null) {
        _scrollToNewCurrentIndex();
      }
    }
    if (oldWidget.isScrollable != widget.isScrollable) {
      if (widget.isScrollable) {
        isScrollToCurrentIndex = true;
      }
    }
  }

  @override
  void dispose() {
    _indicatorPainter!.dispose();
    if (_controllerIsValid) {
      _controller!.animation!.removeListener(_handleTabControllerAnimationTick);
      _controller!.removeListener(_handleTabControllerTick);
    }
    _controller = null;

    super.dispose();
  }

  int get maxTabIndex => _indicatorPainter!.maxTabIndex;

  double _tabScrollOffset(int index, double viewportWidth, double minExtent, double maxExtent) {
    if (!widget.isScrollable) return 0.0;

    double tabCenter = _indicatorPainter!.centerOf(index);
    switch (Directionality.of(context)) {
      case TextDirection.rtl:
        tabCenter = _tabStripWidth! - tabCenter;
        break;
      case TextDirection.ltr:
        break;
    }
    return (tabCenter - viewportWidth / 2.0).clamp(minExtent, maxExtent);
  }

  double _tabCenteredScrollOffset(int index) {
    final ScrollPosition? position = _reorderController?.position;

    return _tabScrollOffset(index, position?.viewportDimension ?? screenWidth, position?.minScrollExtent ?? 0, position?.maxScrollExtent ?? screenWidth);
  }

  void _initialScrollOffset() {
    if (!widget.isScrollable) {
      _controllers.animateTo(0.01, curve: Curves.linear, duration: const Duration(milliseconds: 1));
    }
  }

  void _scrollToCurrentIndex() {
    final double offset = _tabCenteredScrollOffset(_currentIndex!);

    _controllers.animateTo(offset, duration: kTabScrollDuration, curve: Curves.ease);
  }

  void _scrollToControllerValue() {
    final double? leadingPosition = _currentIndex! > 0 ? _tabCenteredScrollOffset(_currentIndex! - 1) : null;
    final double middlePosition = _tabCenteredScrollOffset(_currentIndex!);
    final double? trailingPosition = _currentIndex! < maxTabIndex ? _tabCenteredScrollOffset(_currentIndex! + 1) : null;

    final double index = _controller!.index.toDouble();
    final double value = _controller!.animation!.value;
    final double offset;
    if (value == index - 1.0) {
      offset = leadingPosition ?? middlePosition;
    } else if (value == index + 1.0) {
      offset = trailingPosition ?? middlePosition;
    } else if (value == index) {
      offset = middlePosition;
    } else if (value < index) {
      offset = leadingPosition == null ? middlePosition : lerpDouble(middlePosition, leadingPosition, index - value)!;
    } else {
      offset = trailingPosition == null ? middlePosition : lerpDouble(middlePosition, trailingPosition, value - index)!;
    }

    _controllers.jumpTo(offset);
  }

  void _handleTabControllerAnimationTick() {
    assert(mounted);
    if (!_controller!.indexIsChanging && widget.isScrollable) {
      _currentIndex = _controller!.index;
      _scrollToControllerValue();
    }
  }

  void _handleTabControllerTick() {
    if (_controller!.index != _currentIndex) {
      _currentIndex = _controller!.index;
      if (widget.isScrollable) _scrollToCurrentIndex();
    }
    setState(() {});
  }

  void _saveTabOffsets(List<double> tabOffsets, TextDirection textDirection, double width) {
    xOffsets = tabOffsets;
    _tabStripWidth = width;
    _indicatorPainter?.saveTabOffsets(tabOffsets, textDirection);
  }

  void _handleTap(int index) async {
    assert(index >= 0 && index < widget.tabs.length);
    _controller!.animateTo(index);
    widget.onTap?.call(index);
  }

  Widget _buildStyledTab(Widget child, bool selected, Animation<double> animation) {
    return _TabStyle(
      animation: animation,
      selected: selected,
      labelColor: widget.labelColor,
      unselectedLabelColor: widget.unselectedLabelColor,
      labelStyle: widget.labelStyle,
      unselectedLabelStyle: widget.unselectedLabelStyle,
      child: child,
    );
  }

  void calculateTabStripWidth() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      double width = 0;
      List<double> offsets = [0];
      TextDirection textDirection = Directionality.maybeOf(context)!;
      for (var key in (textDirection == TextDirection.rtl ? _tabExtendKeys.reversed.toList() : _tabExtendKeys)) {
        width += key.currentContext?.size?.width ?? 40;
        switch (textDirection) {
          case TextDirection.rtl:
            offsets.insert(0, width);
            break;
          case TextDirection.ltr:
            offsets.add(width);
            break;
        }
      }
      if ((_tabStripWidth ?? 0).floor() != width.floor() || !listEquals<double>(offsets, xOffsets)) {
        _saveTabOffsets(offsets, textDirection, width);
        if (!widget.isScrollable) {
          _initialScrollOffset();
        }
        setState(() {});
      }

      if (isScrollToCurrentIndex) {
        _scrollToCurrentIndex();
        isScrollToCurrentIndex = false;
      }
    });
  }

  void _scrollToNewCurrentIndex() {
    int oldIndex = isReordered!.oldIndex;
    int newIndex = isReordered!.newIndex;

    if (oldIndex == _currentIndex) {
      _checkAndAnimateTo(newIndex);
    } else if (oldIndex > (_currentIndex ?? 0)) {
      if (newIndex < (_currentIndex ?? 0) || newIndex == _currentIndex) {
        int index = (_currentIndex ?? 0);
        _checkAndAnimateTo(++index);
      }
    } else {
      if (newIndex > (_currentIndex ?? 0) || newIndex == _currentIndex) {
        int index = (_currentIndex ?? 0);
        _checkAndAnimateTo(--index);
      }
    }

    isReordered = null;
  }

  _checkAndAnimateTo(int index) {
    if (index < widget.tabs.length) {
      _controller!.animateTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterialLocalizations(context));
    assert(() {
      if (_controller!.length != widget.tabs.length) {
        throw FlutterError(
          "Controller's length property (${_controller!.length}) does not match the "
          "number of tabs (${widget.tabs.length}) present in TabBar's tabs property.",
        );
      }
      return true;
    }());
    final MaterialLocalizations localizations = MaterialLocalizations.of(context);
    if (_controller!.length == 0) {
      return Container(
        height: _kTabHeight + widget.indicatorWeight,
      );
    }

    final TabBarThemeData tabBarTheme = TabBarTheme.of(context);

    final List<Widget> wrappedTabs = List<Widget>.generate(widget.tabs.length, (int index) {
      const double verticalAdjustment = (_kTextAndIconTabHeight - _kTabHeight) / 2.0;
      EdgeInsetsGeometry? adjustedPadding;

      if (widget.tabs[index] is PreferredSizeWidget) {
        final PreferredSizeWidget tab = widget.tabs[index] as PreferredSizeWidget;
        if (widget.tabHasTextAndIcon && tab.preferredSize.height == _kTabHeight) {
          if (widget.labelPadding != null || tabBarTheme.labelPadding != null) {
            adjustedPadding = (widget.labelPadding ?? tabBarTheme.labelPadding!).add(const EdgeInsets.symmetric(vertical: verticalAdjustment));
          } else {
            adjustedPadding = const EdgeInsets.symmetric(vertical: verticalAdjustment, horizontal: 16.0);
          }
        }
      }

      return Center(
        heightFactor: 1.0,
        child: Padding(
          padding: adjustedPadding ?? widget.labelPadding ?? tabBarTheme.labelPadding ?? kTabLabelPadding,
          child: KeyedSubtree(
            key: _tabKeys[index],
            child: widget.tabs[index],
          ),
        ),
      );
    });

    if (_controller != null) {
      final int previousIndex = _controller!.previousIndex;

      if (_controller!.indexIsChanging) {
        assert(_currentIndex != previousIndex);
        final Animation<double> animation = _ChangeAnimation(_controller!);
        wrappedTabs[_currentIndex!] = _buildStyledTab(wrappedTabs[_currentIndex!], true, animation);
        wrappedTabs[previousIndex] = _buildStyledTab(wrappedTabs[previousIndex], false, animation);
      } else {
        final int tabIndex = _currentIndex!;
        final Animation<double> centerAnimation = _DragAnimation(_controller!, tabIndex);
        wrappedTabs[tabIndex] = _buildStyledTab(wrappedTabs[tabIndex], true, centerAnimation);
        if (_currentIndex! > 0) {
          final int tabIndex = _currentIndex! - 1;
          final Animation<double> previousAnimation = ReverseAnimation(_DragAnimation(_controller!, tabIndex));
          wrappedTabs[tabIndex] = _buildStyledTab(wrappedTabs[tabIndex], false, previousAnimation);
        }
        if (_currentIndex! < widget.tabs.length - 1) {
          final int tabIndex = _currentIndex! + 1;
          final Animation<double> nextAnimation = ReverseAnimation(_DragAnimation(_controller!, tabIndex));
          wrappedTabs[tabIndex] = _buildStyledTab(wrappedTabs[tabIndex], false, nextAnimation);
        }
      }
    }

    final int tabCount = widget.tabs.length;
    for (int index = 0; index < tabCount; index += 1) {
      wrappedTabs[index] = InkWell(
        borderRadius: widget.tabBorderRadius,
        mouseCursor: widget.mouseCursor ?? SystemMouseCursors.click,
        onTap: () async {
          _handleTap(index);
        },
        enableFeedback: widget.enableFeedback ?? true,
        overlayColor: widget.overlayColor,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: widget.tabBorderRadius,
            color: widget.tabBackgroundColor,
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.indicatorWeight),
            child: Stack(
              children: <Widget>[
                wrappedTabs[index],
                Semantics(
                  selected: index == _currentIndex,
                  label: localizations.tabLabel(tabIndex: index + 1, tabCount: tabCount),
                ),
              ],
            ),
          ),
        ),
      );
    }
    Widget? tabBar;

    height ??= widget.preferredSize.height;

    double? tabWidth;
    if (!widget.isScrollable) {
      tabWidth = (screenWidth - (widget.padding?.horizontal ?? 0)) / wrappedTabs.length;
    }
    for (var i = 0; i < wrappedTabs.length; i++) {
      Widget child = wrappedTabs[i];

      if (!widget.buildDefaultDragHandles) {
        if (widget.useDelayedDragStartListener) {
          child = ReorderableDelayedDragStartListener(
            index: i,
            child: child,
          );
        } else {
          child = ReorderableDragStartListener(
            index: i,
            child: child,
          );
        }
      }

      wrappedTabs[i] = SizedBox(
        key: _tabExtendKeys[i],
        width: tabWidth,
        height: height,
        child: _TabStyle(
          animation: kAlwaysDismissedAnimation,
          selected: false,
          labelColor: widget.labelColor,
          unselectedLabelColor: widget.unselectedLabelColor,
          labelStyle: widget.labelStyle,
          unselectedLabelStyle: widget.unselectedLabelStyle,
          child: child,
        ),
      );
    }
    tabBar = Stack(
      children: [
        SizedBox(
          height: height,
          width: double.maxFinite,
          child: ReorderableListView(
            buildDefaultDragHandles: widget.buildDefaultDragHandles,
            cacheExtent: double.maxFinite,
            physics: widget.physics,
            scrollController: _reorderController,
            scrollDirection: Axis.horizontal,
            children: wrappedTabs,
            proxyDecorator: (child, index, anim) {
              return Material(
                color: widget.reorderingTabBackgroundColor ?? Colors.transparent,
                borderRadius: widget.tabBorderRadius,
                child: child,
              );
            },
            onReorder: (oldIndex, newIndex) async {
              if (oldIndex < newIndex) {
                newIndex--;
              }
              if (widget.onReorder != null) {
                isReordered = Reordered(
                  oldIndex: oldIndex,
                  newIndex: newIndex,
                );
                widget.onReorder!(oldIndex, newIndex);
              }
            },
          ),
        ),
        if (_tabStripWidth != null) getIndicatorPainter(),
      ],
    );
    if (widget.padding != null) {
      tabBar = Padding(
        padding: widget.padding!,
        child: tabBar,
      );
    }
    calculateTabStripWidth();
    return tabBar;
  }

  Positioned getIndicatorPainter() {
    double width = _tabStripWidth!;
    if (!widget.isScrollable) {
      if (width > (screenWidth - (widget.padding?.horizontal ?? 0))) {
        width = screenWidth - (widget.padding?.horizontal ?? 0);
      }
    }
    return Positioned(
      bottom: 0,
      right: 0,
      left: 0,
      height: widget.indicatorWeight,
      child: SingleChildScrollView(
        physics: widget.physics,
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: CustomPaint(
          painter: _indicatorPainter,
          child: SizedBox(
            height: widget.indicatorWeight,
            width: width,
          ),
        ),
      ),
    );
  }
}

// Hand coded defaults based on Material Design 2.
class _TabsDefaultsM2 extends TabBarTheme {
  const _TabsDefaultsM2(this.context) : super(indicatorSize: TabBarIndicatorSize.tab);

  final BuildContext context;

  @override
  Color? get indicatorColor => Theme.of(context).indicatorColor;

  @override
  Color? get labelColor => Theme.of(context).primaryTextTheme.bodyLarge!.color!;

  @override
  TextStyle? get labelStyle => Theme.of(context).primaryTextTheme.bodyLarge;

  @override
  TextStyle? get unselectedLabelStyle => Theme.of(context).primaryTextTheme.bodyLarge;

  @override
  InteractiveInkFeatureFactory? get splashFactory => Theme.of(context).splashFactory;
}

// BEGIN GENERATED TOKEN PROPERTIES - Tabs

// Do not edit by hand. The code between the "BEGIN GENERATED" and
// "END GENERATED" comments are generated from data in the Material
// Design token database by the script:
//   dev/tools/gen_defaults/bin/gen_defaults.dart.

// Token database version: v0_143

class _TabsDefaultsM3 extends TabBarTheme {
  _TabsDefaultsM3(this.context) : super(indicatorSize: TabBarIndicatorSize.label);

  final BuildContext context;
  late final ColorScheme _colors = Theme.of(context).colorScheme;
  late final TextTheme _textTheme = Theme.of(context).textTheme;

  @override
  Color? get dividerColor => _colors.surfaceVariant;

  @override
  Color? get indicatorColor => _colors.primary;

  @override
  Color? get labelColor => _colors.primary;

  @override
  TextStyle? get labelStyle => _textTheme.titleSmall;

  @override
  Color? get unselectedLabelColor => _colors.onSurfaceVariant;

  @override
  TextStyle? get unselectedLabelStyle => _textTheme.titleSmall;

  @override
  WidgetStateProperty<Color?> get overlayColor {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.selected)) {
        if (states.contains(WidgetState.hovered)) {
          return _colors.primary.withOpacity(0.08);
        }
        if (states.contains(WidgetState.focused)) {
          return _colors.primary.withOpacity(0.12);
        }
        if (states.contains(WidgetState.pressed)) {
          return _colors.primary.withOpacity(0.12);
        }
        return null;
      }
      if (states.contains(WidgetState.hovered)) {
        return _colors.onSurface.withOpacity(0.08);
      }
      if (states.contains(WidgetState.focused)) {
        return _colors.onSurface.withOpacity(0.12);
      }
      if (states.contains(WidgetState.pressed)) {
        return _colors.primary.withOpacity(0.12);
      }
      return null;
    });
  }

  @override
  InteractiveInkFeatureFactory? get splashFactory => Theme.of(context).splashFactory;
}

class Reordered {
  int oldIndex;
  int newIndex;
  Reordered({
    required this.oldIndex,
    required this.newIndex,
  });
}
