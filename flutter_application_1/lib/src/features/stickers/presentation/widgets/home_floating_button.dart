import 'package:flutter/material.dart';

class HomeFloatingButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const HomeFloatingButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton.extended(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      onPressed: onPressed,
      label: const Text('Novo Pacote'),
      icon: const Icon(Icons.add_box_rounded),
    );
  }
}
