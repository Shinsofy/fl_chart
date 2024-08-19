// coverage:ignore-file
import 'package:fl_chart/src/chart/base/base_chart/base_chart_data.dart';
import 'package:fl_chart/src/chart/base/base_chart/fl_touch_event.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// It implements shared logics between our renderers such as touch/pointer events recognition, size, layout, ...
abstract class RenderBaseChart<R extends BaseTouchResponse> extends RenderBox
    implements MouseTrackerAnnotation {
  /// We use [FlTouchData] to retrieve [FlTouchData.touchCallback] and [FlTouchData.mouseCursorResolver]
  /// to invoke them when touch happens.
  RenderBaseChart(FlTouchData<R>? touchData, BuildContext context)
      : _buildContext = context {
    updateBaseTouchData(touchData);
    initGestureRecognizers();
  }

  // We use buildContext to retrieve Theme data
  BuildContext get buildContext => _buildContext;
  BuildContext _buildContext;
  set buildContext(BuildContext value) {
    _buildContext = value;
    markNeedsPaint();
  }

  void updateBaseTouchData(FlTouchData<R>? value) {
    _touchCallback = value?.touchCallback;
    _mouseCursorResolver = value?.mouseCursorResolver;
    _longPressDuration = value?.longPressDuration;
  }

  BaseTouchCallback<R>? _touchCallback;
  MouseCursorResolver<R>? _mouseCursorResolver;
  Duration? _longPressDuration;

  MouseCursor _latestMouseCursor = MouseCursor.defer;

  late bool _validForMouseTracker;

  // Instead of drag we use scale which also includes pan gestures
  // Recognizes pan gestures, such as onDown, onStart, onUpdate, onCancel, ...
  // and detects scale gestures scroll, pinch in out, such as onStart, onUpdate, onEnd, ...
  late ScaleGestureRecognizer _scaleGestureRecognizer;

  /// Recognizes tap gestures, such as onTapDown, onTapCancel and onTapUp
  late TapGestureRecognizer _tapGestureRecognizer;

  /// Recognizes longPress gestures, such as onLongPressStart, onLongPressMoveUpdate and onLongPressEnd
  late LongPressGestureRecognizer _longPressGestureRecognizer;

  /// Initializes our recognizers and implement their callbacks.
  void initGestureRecognizers() {
    _scaleGestureRecognizer = ScaleGestureRecognizer();
    _scaleGestureRecognizer
      ..onStart = (details) {
        _notifyScaleEvent(FlScaleStartEvent(details));
        _notifyTouchEvent(FlPanDownEvent(details));
        _notifyTouchEvent(FlPanStartEvent(details));
      }
      ..onUpdate = (details) {
        _notifyScaleEvent(FlScaleUpdateEvent(details));
        _notifyTouchEvent(FlPanUpdateEvent(details));
      }
      ..onEnd = (details) {
        _notifyScaleEvent(FlScaleEndEvent(details));
        _notifyTouchEvent(FlPanEndEvent(details));
      };

    _tapGestureRecognizer = TapGestureRecognizer();
    _tapGestureRecognizer
      ..onTapDown = (tapDownDetails) {
        _notifyTouchEvent(FlTapDownEvent(tapDownDetails));
      }
      ..onTapCancel = () {
        _notifyTouchEvent(const FlTapCancelEvent());
      }
      ..onTapUp = (tapUpDetails) {
        _notifyTouchEvent(FlTapUpEvent(tapUpDetails));
      };

    _longPressGestureRecognizer =
        LongPressGestureRecognizer(duration: _longPressDuration);
    _longPressGestureRecognizer
      ..onLongPressStart = (longPressStartDetails) {
        _notifyTouchEvent(FlLongPressStart(longPressStartDetails));
      }
      ..onLongPressMoveUpdate = (longPressMoveUpdateDetails) {
        _notifyTouchEvent(
          FlLongPressMoveUpdate(longPressMoveUpdateDetails),
        );
      }
      ..onLongPressEnd = (longPressEndDetails) =>
          _notifyTouchEvent(FlLongPressEnd(longPressEndDetails));
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return Size(constraints.maxWidth, constraints.maxHeight);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  /// Feeds our gesture recognizers for handling events, we also handle [PointerHoverEvent] here.
  ///
  /// Our gesture recognizers are responsible for notifying us about happened gestures (such as tap, panMove, ...)
  /// we need to give them [PointerDownEvent] then they will listen to the global [GestureBinding] for further events.
  ///
  /// We need to handle [PointerHoverEvent] because there is no gesture recognizer
  /// for mouse hover events (in fact they don't have any gestures, they are just events).
  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    assert(debugHandleEvent(event, entry));
    if (_touchCallback == null) {
      return;
    }
    if (event is PointerDownEvent) {
      _longPressGestureRecognizer.addPointer(event);
      _tapGestureRecognizer.addPointer(event);
      _scaleGestureRecognizer.addPointer(event);
    } else if (event is PointerHoverEvent) {
      _notifyTouchEvent(FlPointerHoverEvent(event));
    }
  }

  /// Here we handle mouse hover enter event
  @override
  PointerEnterEventListener? get onEnter =>
      (event) => _notifyTouchEvent(FlPointerEnterEvent(event));

  /// Here we handle mouse hover exit event
  @override
  PointerExitEventListener? get onExit =>
      (event) => _notifyTouchEvent(FlPointerExitEvent(event));

  /// Invokes the [_touchCallback] to notify listeners of this [FlTouchEvent] if the pointer is one or zero(exit events).
  ///
  /// We get a [BaseTouchResponse] using [getResponseAtLocation] for events which contains a localPosition.
  /// Then we invoke [_touchCallback] using the [event] and [response].
  void _notifyTouchEvent(FlTouchEvent event) {
    if (_touchCallback == null) {
      return;
    }
    final localPosition = event.localPosition;
    final pointerCount = event.pointerCount;

    R? response;
    if (localPosition != null && pointerCount == 1) {
      response = getResponseAtLocation(localPosition);
    }

    if (pointerCount <= 1) {
      _touchCallback!(event, response);
    }

    if (_mouseCursorResolver == null) {
      _latestMouseCursor = MouseCursor.defer;
    } else {
      _latestMouseCursor = _mouseCursorResolver!(event, response);
    }
  }

  /// Invokes the [_touchCallback] to notify listeners of this [FlTouchEvent]
  ///
  /// We don't get a response for these events because they are scale events (scroll, pinch.etc)
  /// We just invoke [_touchCallback] using the [event].
  void _notifyScaleEvent(FlTouchEvent event) {
    if (_touchCallback == null) {
      return;
    }

    final pointerCount = event.pointerCount;

    R? response;
    if (pointerCount > 1) {
      _touchCallback!(event, response);
    }
  }

  /// Represents the mouse cursor style when hovers on our chart
  /// In the future we can change it runtime, for example we can turn it to
  /// [SystemMouseCursors.click] when mouse hovers a specific point of our chart.
  @override
  MouseCursor get cursor => _latestMouseCursor;

  /// [MouseTracker] will catch us if this variable is true
  @override
  bool get validForMouseTracker => _validForMouseTracker;

  /// Charts need to implement this class to tell us what [BaseTouchResponse] is available at provided [localPosition]
  /// When touch/pointer event happens, we send it to the user alongside the [FlTouchEvent] using [_touchCallback]
  R getResponseAtLocation(Offset localPosition);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _validForMouseTracker = true;
  }

  @override
  void detach() {
    _validForMouseTracker = false;
    super.detach();
  }
}
