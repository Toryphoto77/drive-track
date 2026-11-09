import 'package:flutter/material.dart';

/// 子页统一转场：约 320ms 淡入 + 轻微上滑，和底栏 AnimatedSwitcher 同节奏。
const Duration kDtPageTransition = Duration(milliseconds: 320);

Widget dtFadeSlideTransition(
  Animation<double> animation,
  Widget child,
) {
  final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    ),
  );
}

class DtFadeSlideTransitionsBuilder extends PageTransitionsBuilder {
  const DtFadeSlideTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return dtFadeSlideTransition(animation, child);
  }
}

class DtPageRoute<T> extends PageRoute<T> {
  DtPageRoute({
    required this.builder,
    super.settings,
  });

  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => kDtPageTransition;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return dtFadeSlideTransition(animation, child);
  }
}
