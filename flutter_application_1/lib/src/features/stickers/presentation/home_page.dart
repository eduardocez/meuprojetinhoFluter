import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/src/features/stickers/data/pack_storage.dart';
import 'package:flutter_application_1/src/features/stickers/data/sticker_manager.dart' as sticker_manager;
import 'package:flutter_application_1/src/features/stickers/domain/sticker_pack_info.dart';
import 'package:flutter_application_1/src/shared/widgets/base_app_bar.dart';
import 'package:image_picker/image_picker.dart';

enum PackFilter { all, published, pending }

class HomePage extends StatefulWidget {
  final bool loadOnInit;

  const HomePage({super.key, this.loadOnInit = true});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final ImagePicker _imagePicker = ImagePicker();
  final List<StickerPackInfo> _packs = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loadingPacks = true;
  String _searchQuery = '';
  PackFilter _packFilter = PackFilter.all;

  NavigatorState? _blockingDialogNavigator;
  bool _blockingDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.loadOnInit) {
      _loadingPacks = false;
      return;
    }
    _loadPacks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  int get _totalStickers => _packs.fold<int>(0, (sum, pack) => sum + pack.stickers.length);

  List<StickerPackInfo> get _visiblePacks {
    final query = _searchQuery.trim().toLowerCase();
    return _packs.where((pack) {
      if (_packFilter == PackFilter.published && !pack.published) return false;
      if (_packFilter == PackFilter.pending && !pack.needsSync) return false;
      if (query.isNotEmpty && !pack.name.toLowerCase().contains(query)) return false;
      return true;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _packFilter = PackFilter.all;
      _searchController.clear();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Se o WhatsApp abrir por cima, fechamos o diálogo para não parecer "loading infinito".
    if ((state == AppLifecycleState.inactive || state == AppLifecycleState.paused) && _blockingDialogOpen) {
      final nav = _blockingDialogNavigator;
      if (nav != null && nav.canPop()) {
        nav.pop();
      }
      _blockingDialogOpen = false;
    }
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

    return pickedImages.map((image) => image.path).where((path) => path.trim().isNotEmpty).toList();
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
    if (_loadingPacks || !mounted) return;

    if (_packs.isEmpty) {
      await _criarNovoPacote(context);
      return;
    }

    final pack = await _selecionarPacote(context);
    if (pack == null || !mounted) return;

    final sources = await _pickImagePaths();
    if (sources.isEmpty || !mounted) return;

    await _adicionarAoPacote(context, pack, sources: sources);
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
            separatorBuilder: (_, _) => const Divider(height: 1),
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
                          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
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

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    _blockingDialogNavigator = rootNavigator;
    _blockingDialogOpen = true;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
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
      if (_blockingDialogOpen && rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      _blockingDialogOpen = false;
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
                                        errorBuilder: (_, _, _) => Container(
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

  Widget _buildEmptyState(BuildContext context, {required bool hasFilters}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isEmpty = _packs.isEmpty;

    final title = isEmpty ? 'Crie seu primeiro pacote' : 'Nenhum pacote encontrado';
    final subtitle = isEmpty
        ? 'Organize suas figurinhas em pacotes modernos e faceis de achar.'
        : 'Tente ajustar os filtros ou limpar a busca.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withAlpha(90),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 36,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (isEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadingPacks ? null : () => _criarNovoPacote(context),
                icon: const Icon(Icons.add_box_rounded),
                label: const Text('Criar primeiro pacote'),
              ),
            ] else if (hasFilters) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _clearFilters,
                child: const Text('Limpar filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPackCard(BuildContext context, StickerPackInfo pack) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final statusLabel = pack.needsSync
        ? 'Pendente'
        : pack.published
            ? 'Publicado'
            : 'Local';
    final statusColor = pack.needsSync
        ? colorScheme.error
        : pack.published
            ? colorScheme.primary
            : colorScheme.tertiary;

    final imageWidget = pack.trayPath.trim().isEmpty
        ? Container(
            color: colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(
              Icons.collections_rounded,
              color: colorScheme.onSurfaceVariant,
              size: 48,
            ),
          )
        : Image.file(
            File(pack.trayPath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return Container(
                color: colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
              );
            },
          );

    return Material(
      color: colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black.withAlpha(18),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _verPacote(context, pack),
        child: Stack(
          children: [
            Positioned.fill(child: imageWidget),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      colorScheme.surface.withAlpha(230),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pack.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${pack.stickers.length}/30 figurinhas',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: colorScheme.primaryContainer,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => _adicionarAoPacote(context, pack),
                      icon: const Icon(Icons.add_rounded),
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final visiblePacks = _visiblePacks;
    final hasFilters = _searchQuery.trim().isNotEmpty || _packFilter != PackFilter.all;
    final hasPacks = _packs.isNotEmpty;
    final primaryLabel = hasPacks ? 'Adicionar figurinhas' : 'Criar primeiro pacote';
    final primaryIcon = hasPacks ? Icons.add_photo_alternate_rounded : Icons.add_box_rounded;
    final VoidCallback? primaryAction = _loadingPacks
        ? null
        : () => hasPacks ? _fluxoAdicionarFigurinhas(context) : _criarNovoPacote(context);
    final VoidCallback? secondaryAction = _loadingPacks ? null : () => _criarNovoPacote(context);

    return Scaffold(
      appBar: BaseAppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colorScheme.outlineVariant.withAlpha(80)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pacotes',
                      style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_packs.length} pacotes · $_totalStickers figurinhas',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: primaryAction,
                          icon: Icon(primaryIcon),
                          label: Text(primaryLabel),
                        ),
                        if (hasPacks)
                          OutlinedButton.icon(
                            onPressed: secondaryAction,
                            icon: const Icon(Icons.add_box_rounded),
                            label: const Text('Novo pacote'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Buscar pacotes',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: _packFilter == PackFilter.all,
                          onSelected: (_) => setState(() => _packFilter = PackFilter.all),
                        ),
                        ChoiceChip(
                          label: const Text('Publicados'),
                          selected: _packFilter == PackFilter.published,
                          onSelected: (_) => setState(() => _packFilter = PackFilter.published),
                        ),
                        ChoiceChip(
                          label: const Text('Pendentes'),
                          selected: _packFilter == PackFilter.pending,
                          onSelected: (_) => setState(() => _packFilter = PackFilter.pending),
                        ),
                      ],
                    ),
                  ),
                  if (hasFilters)
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Limpar'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _loadingPacks
                    ? const Center(child: CircularProgressIndicator())
                    : visiblePacks.isEmpty
                        ? _buildEmptyState(context, hasFilters: hasFilters)
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: 0.82,
                            ),
                            itemCount: visiblePacks.length,
                            itemBuilder: (context, index) {
                              final pack = visiblePacks[index];
                              return _buildPackCard(context, pack);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
