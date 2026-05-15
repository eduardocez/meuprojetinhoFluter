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
      final refreshed = <StickerPackInfo>[];
      for (final pack in packs) {
        final updated = await sticker_manager.StickerManager.refreshPackFromDisk(pack);
        refreshed.add(updated);
      }
      if (!mounted) return;
      setState(() {
        _packs
          ..clear()
          ..addAll(refreshed);
        _loadingPacks = false;
      });

      await PackStorage.savePacks(refreshed);
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
    if (_packs.isNotEmpty) {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Como deseja adicionar?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.add_box_rounded),
                  title: const Text('Criar novo pacote'),
                  onTap: () => Navigator.of(ctx).pop('new'),
                ),
                ListTile(
                  leading: const Icon(Icons.collections_rounded),
                  title: const Text('Adicionar em pacote existente'),
                  onTap: () => Navigator.of(ctx).pop('existing'),
                ),
              ],
            ),
          );
        },
      );

      if (action == 'existing') {
        final pack = await _selecionarPacote(context);
        if (pack != null && mounted) {
          await _adicionarAoPacote(context, pack);
        }
        return;
      }

      if (action != 'new') {
        return;
      }
    }

    String nomePasta = 'Meu Pacote';

    final action = await showDialog<String>(
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
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop('empty'),
            child: const Text('Criar vazio'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('photos'),
            child: const Text('Selecionar Fotos'),
          ),
        ],
      ),
    );

    if (action == 'empty' && mounted) {
      final pack = StickerPackInfo(
        id: 'pack_${DateTime.now().millisecondsSinceEpoch}',
        name: nomePasta,
        trayPath: '',
        stickers: const <String>[],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        published: false,
        needsSync: false,
      );
      await PackStorage.addPack(pack);
      if (!mounted) return;
      setState(() {
        _packs.insert(0, pack);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pacote criado. Adicione figurinhas.')),
      );
      return;
    }

    if (action != 'photos' || !mounted) return;

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
      final message = pack.needsSync
          ? 'Pacote criado localmente. Falha ao enviar ao WhatsApp.'
          : 'Pacote enviado ao WhatsApp';
      snack.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      snack.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _fluxoAdicionarFigurinhas(BuildContext context) async {
    final sources = await _pickImagePaths();
    if (sources.isEmpty || !mounted) return;

    if (_packs.isEmpty) {
      await _criarNovoPacoteComSources(context, sources);
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Adicionar figurinhas em:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.collections_rounded),
                title: const Text('Pacote existente'),
                onTap: () => Navigator.of(ctx).pop('existing'),
              ),
              ListTile(
                leading: const Icon(Icons.add_box_rounded),
                title: const Text('Novo pacote'),
                onTap: () => Navigator.of(ctx).pop('new'),
              ),
            ],
          ),
        );
      },
    );

    if (action == 'existing') {
      final pack = await _selecionarPacote(context);
      if (pack != null && mounted) {
        await _adicionarAoPacote(context, pack, sources: sources);
      }
      return;
    }

    if (action == 'new' && mounted) {
      await _criarNovoPacoteComSources(context, sources);
    }
  }

  Future<void> _criarNovoPacoteComSources(BuildContext context, List<String> sources) async {
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
            child: const Text('Criar pacote'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

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
      final message = pack.needsSync
          ? 'Pacote criado localmente. Falha ao enviar ao WhatsApp.'
          : 'Pacote enviado ao WhatsApp';
      snack.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      snack.showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<StickerPackInfo?> _selecionarPacote(BuildContext context) async {
    if (_packs.isEmpty) return null;

    return showModalBottomSheet<StickerPackInfo>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            itemCount: _packs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final pack = _packs[index];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: pack.trayPath.trim().isEmpty
                      ? Container(
                          width: 44,
                          height: 44,
                          color: Colors.black26,
                          alignment: Alignment.center,
                          child: const Icon(Icons.collections_rounded),
                        )
                      : Image.file(
                          File(pack.trayPath),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                        ),
                ),
                title: Text(pack.name),
                subtitle: Text('${pack.stickers.length}/30 figurinhas'),
                onTap: () => Navigator.of(ctx).pop(pack),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _adicionarAoPacote(
    BuildContext context,
    StickerPackInfo pack, {
    List<String>? sources,
  }) async {
    final selectedSources = sources ?? await _pickImagePaths();
    if (selectedSources.isEmpty || !mounted) {
      return;
    }

    final dialogContext = context;
    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Adicionando figurinhas...')),
          ],
        ),
      ),
    );

    try {
      final updated = await sticker_manager.StickerManager.addStickersToPack(pack, selectedSources);
      if (updated == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nao foi possivel adicionar figurinhas')),
        );
        return;
      }
      await PackStorage.updatePack(updated);
      if (!mounted) return;
      setState(() {
        final oldIndex = _packs.indexWhere((p) => p.id == pack.id);
        if (oldIndex >= 0) {
          _packs[oldIndex] = updated;
        } else {
          final newIndex = _packs.indexWhere((p) => p.id == updated.id);
          if (newIndex >= 0) {
            _packs[newIndex] = updated;
          } else {
            _packs.insert(0, updated);
          }
        }
      });
      final message = updated.needsSync
          ? 'Pacote salvo localmente. Falha ao enviar ao WhatsApp.'
          : updated.published
              ? 'Pacote atualizado no WhatsApp'
            : 'Pacote salvo localmente.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) {
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _verPacote(BuildContext context, StickerPackInfo pack) async {
    final refreshed = await sticker_manager.StickerManager.refreshPackFromDisk(pack);
    if (refreshed.stickers != pack.stickers || refreshed.trayPath != pack.trayPath) {
      await PackStorage.updatePack(refreshed);
      if (mounted) {
        setState(() {
          final oldIndex = _packs.indexWhere((p) => p.id == pack.id);
          if (oldIndex >= 0) {
            _packs[oldIndex] = refreshed;
          } else {
            final newIndex = _packs.indexWhere((p) => p.id == refreshed.id);
            if (newIndex >= 0) {
              _packs[newIndex] = refreshed;
            } else {
              _packs.insert(0, refreshed);
            }
          }
        });
      }
      pack = refreshed;
    }

    var currentPack = pack;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentPack.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Figurinhas: ${currentPack.stickers.length}/30'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: currentPack.stickers.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhuma figurinha ainda',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : GridView.builder(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: currentPack.stickers.length,
                              itemBuilder: (context, index) {
                                final path = currentPack.stickers[index];
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(path),
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.black26,
                                          alignment: Alignment.center,
                                          child: const Icon(Icons.broken_image_outlined),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: InkWell(
                                        onTap: () async {
                                          final confirm = await showDialog<bool>(
                                            context: modalContext,
                                            builder: (dialogContext) => AlertDialog(
                                              title: const Text('Excluir figurinha'),
                                              content: const Text('Deseja excluir esta figurinha?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(dialogContext).pop(false),
                                                  child: const Text('Cancelar'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () => Navigator.of(dialogContext).pop(true),
                                                  child: const Text('Excluir'),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirm != true) return;

                                          final file = File(path);
                                          if (await file.exists()) {
                                            await file.delete();
                                          }

                                          final updated = currentPack.copyWith(
                                            stickers: currentPack.stickers.where((p) => p != path).toList(),
                                            needsSync: true,
                                          );

                                          await PackStorage.updatePack(updated);
                                          if (!mounted) return;
                                          setState(() {
                                            final index = _packs.indexWhere((p) => p.id == updated.id);
                                            if (index >= 0) {
                                              _packs[index] = updated;
                                            }
                                          });
                                          setModalState(() {
                                            currentPack = updated;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _adicionarAoPacote(context, currentPack);
                            },
                            icon: const Icon(Icons.add_photo_alternate_rounded),
                            label: const Text('Adicionar figurinhas'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final snack = ScaffoldMessenger.of(context);
                              snack.showSnackBar(
                                const SnackBar(content: Text('Sincronizando com WhatsApp...')),
                              );

                              final updated = await sticker_manager.StickerManager.syncPack(currentPack);
                              if (updated == null) {
                                snack.showSnackBar(
                                  const SnackBar(content: Text('Nao foi possivel sincronizar')),
                                );
                                return;
                              }
                              await PackStorage.updatePack(updated);
                              if (!mounted) return;
                              setState(() {
                                final oldIndex = _packs.indexWhere((p) => p.id == currentPack.id);
                                if (oldIndex >= 0) {
                                  _packs[oldIndex] = updated;
                                } else {
                                  final newIndex = _packs.indexWhere((p) => p.id == updated.id);
                                  if (newIndex >= 0) {
                                    _packs[newIndex] = updated;
                                  } else {
                                    _packs.insert(0, updated);
                                  }
                                }
                              });
                              setModalState(() {
                                currentPack = updated;
                              });
                              snack.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    updated.needsSync
                                        ? 'Falha ao enviar ao WhatsApp'
                                        : 'Pacote sincronizado com WhatsApp',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.sync_rounded),
                            label: const Text('Sincronizar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          String novoNome = currentPack.name;
                          final confirm = await showDialog<bool>(
                            context: modalContext,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Renomear pacote'),
                              content: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Nome do pacote',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) {
                                  if (val.trim().isNotEmpty) {
                                    novoNome = val.trim();
                                  }
                                },
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(true),
                                  child: const Text('Salvar'),
                                ),
                              ],
                            ),
                          );

                          if (confirm != true || novoNome.trim().isEmpty) return;

                          final updated = currentPack.copyWith(name: novoNome, needsSync: true);
                          await PackStorage.updatePack(updated);
                          if (!mounted) return;
                          setState(() {
                            final index = _packs.indexWhere((p) => p.id == updated.id);
                            if (index >= 0) {
                              _packs[index] = updated;
                            }
                          });
                          setModalState(() {
                            currentPack = updated;
                          });
                        },
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Renomear pacote'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: modalContext,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Excluir pacote'),
                              content: const Text('Tem certeza que deseja excluir este pacote?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.of(dialogContext).pop(true),
                                  child: const Text('Excluir'),
                                ),
                              ],
                            ),
                          );

                          if (confirm != true) return;

                          await PackStorage.removePack(currentPack.id);
                          if (!mounted) return;
                          setState(() {
                            _packs.removeWhere((p) => p.id == currentPack.id);
                          });
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Pacote excluido')),
                          );
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        label: const Text(
                          'Excluir pacote',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'meu app',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: DefaultTabController(
        length: 2,
        child: Builder(
          builder: (context) => Scaffold(
            appBar: BaseAppBar(
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Adicionar Figurinhas'),
                  Tab(text: 'Meus Pacotes'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Crie suas figurinhas primeiro e depois escolha o pacote.',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _fluxoAdicionarFigurinhas(context),
                          icon: const Icon(Icons.add_photo_alternate_rounded),
                          label: const Text('Selecionar figurinhas'),
                        ),
                      ),
                      const SizedBox(height: 24),
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
                                : ListView.builder(
                                    itemCount: _packs.length,
                                    itemBuilder: (context, index) {
                                      final pack = _packs[index];
                                      return ListTile(
                                        leading: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: pack.trayPath.trim().isEmpty
                                              ? Container(
                                                  width: 44,
                                                  height: 44,
                                                  color: Colors.black26,
                                                  alignment: Alignment.center,
                                                  child: const Icon(Icons.collections_rounded),
                                                )
                                              : Image.file(
                                                  File(pack.trayPath),
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                                                ),
                                        ),
                                        title: Text(pack.name),
                                        subtitle: Text('${pack.stickers.length}/30 figurinhas'),
                                        onTap: () => _verPacote(context, pack),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
                Padding(
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
                                        onTap: () => _verPacote(context, pack),
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
                                                      pack.trayPath.trim().isEmpty
                                                          ? Container(
                                                              color: Colors.black26,
                                                              alignment: Alignment.center,
                                                              child: const Icon(
                                                                Icons.collections_rounded,
                                                                color: Colors.white70,
                                                                size: 48,
                                                              ),
                                                            )
                                                          : Image.file(
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
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        pack.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      SizedBox(
                                                        width: double.infinity,
                                                        child: OutlinedButton.icon(
                                                          onPressed: () => _adicionarAoPacote(context, pack),
                                                          icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                                                          label: const Text('Adicionar'),
                                                        ),
                                                      ),
                                                    ],
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
              ],
            ),
            floatingActionButton: HomeFloatingButton(
              onPressed: () => _criarNovoPacote(context),
            ),
          ),
        ),
      ),
    );
  }
}

