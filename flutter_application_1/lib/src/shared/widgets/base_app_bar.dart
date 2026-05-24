import 'package:flutter/material.dart';

class BaseAppBar extends AppBar {
  BaseAppBar({super.key, this.bottom});

  @override
  final PreferredSizeWidget? bottom;

  @override
  State<BaseAppBar> createState() => _BaseAppBarState();
}

class _BaseAppBarState extends State<BaseAppBar> {
  @override
  AppBar build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppBar(
      centerTitle: false,
      titleSpacing: 20,
      title: Text(
        'Figurinhas',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: colorScheme.onSurface,
        ),
      ),
      bottom: widget.bottom,
    );
  }
}
