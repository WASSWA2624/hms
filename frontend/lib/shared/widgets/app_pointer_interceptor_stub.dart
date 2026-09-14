import 'package:flutter/widgets.dart';

/// Keeps [child] clickable where it overlaps an HTML platform view.
///
/// Only the web build needs to intercept anything; elsewhere Flutter owns all
/// pointer input, [child] is returned as is, and [onPointerLeave] never fires.
class AppPointerInterceptor extends StatelessWidget {
  const AppPointerInterceptor({
    required this.child,
    this.onPointerLeave,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPointerLeave;

  @override
  Widget build(BuildContext context) => child;
}
