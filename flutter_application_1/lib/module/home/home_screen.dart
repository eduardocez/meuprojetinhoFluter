import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_application_1/module/home/widgets/home_floating_button.dart';
import 'package:flutter_application_1/module/home/sticker_manager.dart' as sticker_manager;
import 'package:flutter_application_1/module/utils/shared/widgets/base_app_bar.dart';
import 'package:flutter_application_1/module/home/pack_storage.dart';
import 'package:flutter_application_1/module/home/sticker_pack_info.dart';
import 'dart:io';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState ();
}


class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final List<StickerPackInfo> _packs = [];
  bool _loadingPacks = true;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    try {
      final packs = await PackStorage.loadPacks();
      if (!mounted) return;
      setState(() {
        _packs
          ..clear()
          ..addAll(packs);
        _loadingPacks = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar pacotes: $e');
      if (!mounted) return;
      setState(() {
        _packs.clear();
        _loadingPacks = false;
      });
    }
  }

  Future<List<String>> _pickImagePaths() async {
    final pickedImages = await _imagePicker.pickMultiImage();
    if (pickedImages.isEmpty) {
      return <String>[];
    }

    return pickedImages
        .map((image) => image.path)
        .where((path) => path.trim().isNotEmpty)
        .toList();
  }

  Future<void> _criarNovoPacote(BuildContext context) async {
    String nomePasta = 'Meu Pacote';
    
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo pacote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Crie um pacote de figurinhas:'),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Nome da Pasta',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                if (val.trim().isNotEmpty) {
                  nomePasta = val.trim();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Selecionar Fotos'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    final sources = await _pickImagePaths();
    if (sources.isEmpty || !mounted) {
      return;
    }

    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(const SnackBar(content: Text('Preparando pacote de figurinhas...')));

    final packId = 'pack_${DateTime.now().millisecondsSinceEpoch}';
    final packName = nomePasta;
    try {
      final pack = await sticker_manager.StickerManager.createPackAndAdd(packId, packName, sources);
      if (pack == null) {
        snack.showSnackBar(const SnackBar(content: Text('Falha ao criar pacote')));
        return;
      }
      await PackStorage.addPack(pack);
      if (!mounted) return;
      setState(() {
        _packs.insert(0, pack);
      });
      snack.showSnackBar(const SnackBar(content: Text('Pacote enviado ao WhatsApp')));
    } catch (e) {
      snack.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _adicionarAoPacote(BuildContext context, StickerPackInfo pack) async {
    final confirmar = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pack.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Figurinhas: ${pack.stickers.length}/30'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      label: const Text('Adicionar figurinhas'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmar != true || !mounted) return;

    final sources = await _pickImagePaths();
    if (sources.isEmpty || !mounted) {
      return;
    }

    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(const SnackBar(content: Text('Adicionando figurinhas...')));

    try {
      final updated = await sticker_manager.StickerManager.addStickersToPack(pack, sources);
      if (updated == null) {
        snack.showSnackBar(const SnackBar(content: Text('Nao foi possivel adicionar figurinhas')));
        return;
      }
      await PackStorage.updatePack(updated);
      if (!mounted) return;
      setState(() {
        final index = _packs.indexWhere((p) => p.id == updated.id);
        if (index >= 0) {
          _packs[index] = updated;
        }
      });
      snack.showSnackBar(const SnackBar(content: Text('Pacote atualizado')));
    } catch (e) {
      snack.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Pacotes',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    if (!_loadingPacks)
                      ElevatedButton.icon(
                        onPressed: () => _criarNovoPacote(context),
                        icon: const Icon(Icons.add_box_rounded),
                        label: const Text('Novo pacote'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loadingPacks
                    ? const Center(child: CircularProgressIndicator())
                    : _packs.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhum pacote criado ainda',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.9,
                            ),
                            itemCount: _packs.length,
                            itemBuilder: (context, index) {
                              final pack = _packs[index];
                              return GestureDetector(
                                onTap: () => _adicionarAoPacote(context, pack),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: const Color(0xFF1E1E1E),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 6,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.file(
                                                File(pack.trayPath),
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return Container(
                                                    color: Colors.black26,
                                                    alignment: Alignment.center,
                                                    child: const Icon(
                                                      Icons.broken_image_outlined,
                                                      color: Colors.white70,
                                                    ),
                                                  );
                                                },
                                              ),
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black54,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    '${pack.stickers.length}/30',
                                                    style: const TextStyle(fontSize: 12),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(
                                            pack.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
          floatingActionButton: HomeFloatingButton(
            onPressed: () => _criarNovoPacote(context),
          ),
        ),
      ),
    );
  }
}

