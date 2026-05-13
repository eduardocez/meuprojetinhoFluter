import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_application_1/module/home/widgets/home_floating_button.dart';
import 'package:flutter_application_1/module/home/sticker_manager.dart' as sticker_manager;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_application_1/module/utils/shared/widgets/base_app_bar.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState ();
}


class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final List<_PhotoItem> imagensTeste = [];

  Future<void> _adicionarAoWhatsApp(BuildContext context, _PhotoItem photo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar ao WhatsApp?'),
        content: const Text('Deseja criar um pacote com esta figurinha e adicionar ao seu WhatsApp?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(const SnackBar(content: Text('Preparando pacote de figurinhas...')));

    final packId = 'pack_${DateTime.now().millisecondsSinceEpoch}';
    final packName = 'Meu Pct';
    final sources = <String>[];

    if (photo.networkUrl != null) {
      sources.add(photo.networkUrl!);
    } else if (photo.imageBytes != null) {
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/sticker_temp_single.png');
      await file.writeAsBytes(photo.imageBytes!);
      sources.add(file.path);
    }

    try {
      final ok = await sticker_manager.StickerManager.createPackAndAdd(packId, packName, sources);
      snack.showSnackBar(SnackBar(content: Text(ok ? 'Pedido enviado ao WhatsApp' : 'Falha ao criar pacote')));
    } catch (e) {
      snack.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _pickPhotosFromGallery() async {
    final List<XFile> pickedImages = await _imagePicker.pickMultiImage();

    if (pickedImages.isEmpty) {
      return;
    }

    final List<Uint8List> imageBytes = [];
    for (final XFile image in pickedImages) {
      imageBytes.add(await image.readAsBytes());
    }

    if (!mounted) {
      return;
    }

    setState(() {
      imagensTeste.addAll(imageBytes.map(_PhotoItem.memory));
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'meu app',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: BaseAppBar(),
          body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'Recentes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: imagensTeste.length,
                  itemBuilder: (context, index) {
                    final ValueNotifier<bool> isHovered = ValueNotifier(false);
                    final _PhotoItem photo = imagensTeste[index];

                    return ValueListenableBuilder<bool>(
                      valueListenable: isHovered,
                      builder: (context, hovered, child) {
                        return MouseRegion(
                          onEnter: (_) => isHovered.value = true,
                          onExit: (_) => isHovered.value = false,
                          child: AnimatedScale(
                            scale: hovered ? 1.05 : 0.9,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: GestureDetector(
                              onTap: () {
                                _adicionarAoWhatsApp(context, photo);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(hovered ? 0.4 : 0.2),
                                      blurRadius: hovered ? 10 : 5,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      photo.buildImage(),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              imagensTeste.removeAt(index);
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.redAccent,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
          floatingActionButton: HomeFloatingButton(
            onPressed: _pickPhotosFromGallery,
          ),
        ),
      ),
    );
  }
}

class _PhotoItem {
  final String? networkUrl;
  final Uint8List? imageBytes;

  const _PhotoItem.network(String url)
      : networkUrl = url,
        imageBytes = null;

  const _PhotoItem.memory(Uint8List bytes)
      : networkUrl = null,
        imageBytes = bytes;

  Widget buildImage() {
    if (networkUrl != null) {
      return Image.network(
        networkUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.black26,
            alignment: Alignment.center,
            child: const Icon(
              Icons.image_not_supported_outlined,
              color: Colors.white70,
            ),
          );
        },
      );
    }

    return Image.memory(
      imageBytes!,
      fit: BoxFit.cover,
    );
  }
}

