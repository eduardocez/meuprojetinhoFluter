import 'package:flutter/material.dart';

class BaseAppBar extends AppBar {
  BaseAppBar({super.key});


  @override
  State<BaseAppBar> createState() => _BaseAppBarState();
}

class _BaseAppBarState extends State<BaseAppBar> { 

  @override
  AppBar build(BuildContext context) {
    return AppBar(  
      centerTitle: true,
      title: const Text(
        'Minhas figurinhas',
        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
      ),
    );
  }
}