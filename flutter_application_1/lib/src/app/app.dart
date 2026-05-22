import 'package:flutter/material.dart';
import 'package:flutter_application_1/src/app/theme/app_theme.dart';
import 'package:flutter_application_1/src/features/stickers/presentation/home_page.dart';

class StickerApp extends StatelessWidget {
  final bool loadHomePacks;

  const StickerApp({super.key, this.loadHomePacks = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'meu app',
      theme: AppTheme.dark(),
      home: HomePage(loadOnInit: loadHomePacks),
    );
  }
}
