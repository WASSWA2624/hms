import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Keeps [child] clickable where it overlaps an HTML platform view.
///
/// The browser delivers pointer input over an `<iframe>` (for example the
/// print preview) to the iframe's own document, so Flutter never sees it. An
/// empty `<div>` platform view painted beneath [child] sits above the iframe
/// instead; its events bubble to the Flutter view, which hit-tests [child] as
/// usual.
class AppPointerInterceptor extends StatefulWidget {
  const AppPointerInterceptor({
    required this.child,
    this.onPointerLeave,
    super.key,
  });

  final Widget child;

  /// Called when the pointer leaves [child]'s area. Flutter cannot tell on its
  /// own when the pointer moves from [child] straight onto an iframe.
  final VoidCallback? onPointerLeave;

  @override
  State<AppPointerInterceptor> createState() => _AppPointerInterceptorState();
}

class _AppPointerInterceptorState extends State<AppPointerInterceptor> {
  web.HTMLElement? _element;
  web.EventListener? _leaveListener;

  @override
  void dispose() {
    final web.EventListener? listener = _leaveListener;
    if (listener != null) {
      _element?.removeEventListener('mouseleave', listener);
    }
    super.dispose();
  }

  void _handleElementCreated(Object element) {
    final web.HTMLElement div = element as web.HTMLElement;
    div.style
      ..width = '100%'
      ..height = '100%';
    final web.EventListener listener = ((web.Event _) {
      if (mounted) {
        widget.onPointerLeave?.call();
      }
    }).toJS;
    div.addEventListener('mouseleave', listener);
    _element = div;
    _leaveListener = listener;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: HtmlElementView.fromTagName(
            tagName: 'div',
            onElementCreated: _handleElementCreated,
          ),
        ),
        widget.child,
      ],
    );
  }
}
