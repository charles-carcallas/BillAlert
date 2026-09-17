import 'package:flutter/material.dart';

/// Builds the body of an [showExpandableBottomSheet]. The body's own scroll
/// view must use [scrollController], so a drag on the content grows the sheet
/// before it scrolls the list.
typedef ExpandableSheetBuilder =
    Widget Function(BuildContext context, ScrollController scrollController);

/// Opens a modal bottom sheet that starts at [initialSize] of the screen and
/// can be dragged up to fill it — from the grip, from any [SheetDragRegion],
/// or from the content while it is scrolled to the top.
///
/// A non-[dismissible] sheet can still be resized, but no drag or outside tap
/// ever closes it; its own close button decides.
Future<T?> showExpandableBottomSheet<T>({
  required BuildContext context,
  required ExpandableSheetBuilder builder,
  double initialSize = 0.6,
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: dismissible,
  enableDrag: dismissible,
  builder: (_) => ExpandableSheet(
    initialSize: initialSize,
    dismissible: dismissible,
    builder: builder,
  ),
);

class ExpandableSheet extends StatefulWidget {
  final double initialSize;
  final bool dismissible;
  final ExpandableSheetBuilder builder;

  const ExpandableSheet({
    required this.initialSize,
    required this.dismissible,
    required this.builder,
    super.key,
  });

  @override
  State<ExpandableSheet> createState() => _ExpandableSheetState();
}

class _ExpandableSheetState extends State<ExpandableSheet> {
  static const double _fullSize = 1;
  static const Duration _settle = Duration(milliseconds: 220);

  /// Below this, a dismissible sheet closes when let go.
  static const double _closeSize = 0.2;

  final DraggableScrollableController _sheet = DraggableScrollableController();

  double get _minSize => widget.dismissible ? _closeSize : widget.initialSize;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails details) {
    if (!_sheet.isAttached) return;
    final double next = _sheet.size - _sheet.pixelsToSize(details.delta.dy);
    _sheet.jumpTo(next.clamp(_minSize, _fullSize));
  }

  void _release(DragEndDetails details) {
    if (!_sheet.isAttached) return;
    final double velocity = details.primaryVelocity ?? 0;
    final double size = _sheet.size;
    final double target;
    if (velocity < -700) {
      target = size < widget.initialSize ? widget.initialSize : _fullSize;
    } else if (velocity > 700) {
      target = size > widget.initialSize ? widget.initialSize : _minSize;
    } else {
      target = <double>[
        _minSize,
        widget.initialSize,
        _fullSize,
      ].reduce((a, b) => (a - size).abs() <= (b - size).abs() ? a : b);
    }
    if (widget.dismissible && target == _minSize) {
      Navigator.of(context).pop();
      return;
    }
    _sheet.animateTo(target, duration: _settle, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final bool snapsBetween = _minSize < widget.initialSize;
    return Padding(
      // Sit above the keyboard so a text field is never covered.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        controller: _sheet,
        expand: false,
        initialChildSize: widget.initialSize,
        minChildSize: _minSize,
        maxChildSize: _fullSize,
        snap: true,
        snapSizes: snapsBetween ? <double>[widget.initialSize] : null,
        shouldCloseOnMinExtent: widget.dismissible,
        builder: (BuildContext context, ScrollController scrollController) =>
            _SheetDragScope(
              onDrag: _drag,
              onRelease: _release,
              child: Column(
                children: <Widget>[
                  const SheetDragRegion(child: _Grip()),
                  Expanded(child: widget.builder(context, scrollController)),
                ],
              ),
            ),
      ),
    );
  }
}

/// Makes [child] (a sheet header, say) a handle that resizes the enclosing
/// expandable sheet. Outside one, it does nothing.
class SheetDragRegion extends StatelessWidget {
  final Widget child;

  const SheetDragRegion({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final _SheetDragScope? scope = context
        .dependOnInheritedWidgetOfExactType<_SheetDragScope>();
    if (scope == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: scope.onDrag,
      onVerticalDragEnd: scope.onRelease,
      child: child,
    );
  }
}

class _SheetDragScope extends InheritedWidget {
  final GestureDragUpdateCallback onDrag;
  final GestureDragEndCallback onRelease;

  const _SheetDragScope({
    required this.onDrag,
    required this.onRelease,
    required super.child,
  });

  @override
  bool updateShouldNotify(_SheetDragScope oldWidget) => false;
}

/// The same pill Material draws for `showDragHandle`, with a taller touch
/// target so it is easy to catch.
class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Drag to resize',
    child: SizedBox(
      height: 32,
      width: double.infinity,
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );
}
