import 'package:flutter/material.dart';

class HomeFloatingButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const HomeFloatingButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: const Color.fromARGB(255, 212, 31, 31),
      onPressed: onPressed,
      label: const Text('Nova Foto'),
      icon: const Icon(Icons.add_a_photo_rounded),
    );
  }
}