import 'package:flutter/material.dart';

/// Keep the viewport full height. Lists consume this inset as scrollable
/// bottom padding, rather than leaving an unpainted strip below the route.
class BottomChromeContent extends StatelessWidget {
  final double extent;
  final Widget child;

  const BottomChromeContent(
      {super.key, required this.extent, required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          bottom: media.viewInsets.bottom > 0 ? 0 : extent,
        ),
      ),
      child: child,
    );
  }
}
