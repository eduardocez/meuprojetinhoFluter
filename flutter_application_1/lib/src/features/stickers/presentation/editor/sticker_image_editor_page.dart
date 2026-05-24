import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

class StickerImageEditorPage extends StatefulWidget {
  final String imagePath;
  final int? imageIndex;
  final int? totalImages;

  const StickerImageEditorPage({
    super.key,
    required this.imagePath,
    this.imageIndex,
    this.totalImages,
  });

  @override
  State<StickerImageEditorPage> createState() => _StickerImageEditorPageState();
}

class _StickerImageEditorPageState extends State<StickerImageEditorPage> {
  final GlobalKey _canvasKey = GlobalKey();

  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Size? _imageSize;
  Size _canvasSize = Size.zero;

  String _text = '';
  double _textSize = 28;
  Color _textColor = Colors.white;
  Offset _textOffset = const Offset(24, 24);

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    super.dispose();
  }

  void _resolveImage() {
    final provider = FileImage(File(widget.imagePath));
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _imageSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
    });

    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  String get _title {
    final index = widget.imageIndex;
    final total = widget.totalImages;
    if (index != null && total != null) {
      return 'Editar $index/$total';
    }
    return 'Editar figurinha';
  }

  Future<void> _openTextEditor() async {
    final controller = TextEditingController(text: _text);
    double tempSize = _textSize;
    Color tempColor = _textColor;

    final result = await showModalBottomSheet<_TextEditResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Texto',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Digite o texto',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Tamanho: ${tempSize.toStringAsFixed(0)}'),
                  Slider(
                    min: 16,
                    max: 56,
                    value: tempSize,
                    onChanged: (value) {
                      setSheetState(() => tempSize = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text('Cor'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _ColorDot(
                        color: Colors.white,
                        selected: tempColor == Colors.white,
                        onTap: () => setSheetState(() => tempColor = Colors.white),
                      ),
                      _ColorDot(
                        color: Colors.black,
                        selected: tempColor == Colors.black,
                        onTap: () => setSheetState(() => tempColor = Colors.black),
                      ),
                      _ColorDot(
                        color: Colors.redAccent,
                        selected: tempColor == Colors.redAccent,
                        onTap: () => setSheetState(() => tempColor = Colors.redAccent),
                      ),
                      _ColorDot(
                        color: Colors.blueAccent,
                        selected: tempColor == Colors.blueAccent,
                        onTap: () => setSheetState(() => tempColor = Colors.blueAccent),
                      ),
                      _ColorDot(
                        color: Colors.green,
                        selected: tempColor == Colors.green,
                        onTap: () => setSheetState(() => tempColor = Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop(
                          _TextEditResult(
                            text: controller.text.trim(),
                            size: tempSize,
                            color: tempColor,
                          ),
                        );
                      },
                      child: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() {
      _text = result.text;
      _textSize = result.size;
      _textColor = result.color;
      if (_text.isNotEmpty && _textOffset == Offset.zero) {
        _textOffset = const Offset(24, 24);
      }
    });
  }

  Future<void> _saveEditedImage() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        setState(() => _saving = false);
        return;
      }

      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        setState(() => _saving = false);
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      final outputPath = await _writeEditedFile(bytes);
      if (!mounted) return;
      Navigator.of(context).pop(outputPath);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel salvar a edicao.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<String> _writeEditedFile(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final outputDir = Directory('${dir.path}/edited_stickers');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final filename = 'sticker_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${outputDir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _skipEditing() {
    Navigator.of(context).pop(widget.imagePath);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Pular',
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: _saving ? null : _skipEditing,
          ),
          IconButton(
            tooltip: 'Salvar',
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            onPressed: _saving ? null : _saveEditedImage,
          ),
        ],
      ),
      body: _imageSize == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: AspectRatio(
                        aspectRatio: _imageSize!.width / _imageSize!.height,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            _canvasSize = constraints.biggest;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(widget.imagePath),
                                  fit: BoxFit.cover,
                                ),
                                if (_text.trim().isNotEmpty)
                                  Positioned(
                                    left: _textOffset.dx,
                                    top: _textOffset.dy,
                                    child: GestureDetector(
                                      onPanUpdate: (details) {
                                        final next = _textOffset + details.delta;
                                        setState(() {
                                          _textOffset = Offset(
                                            next.dx.clamp(0.0, _canvasSize.width - 20),
                                            next.dy.clamp(0.0, _canvasSize.height - 20),
                                          );
                                        });
                                      },
                                      child: Text(
                                        _text,
                                        style: TextStyle(
                                          fontSize: _textSize,
                                          fontWeight: FontWeight.w700,
                                          color: _textColor,
                                          shadows: const [
                                            Shadow(
                                              offset: Offset(0, 2),
                                              blurRadius: 4,
                                              color: Colors.black54,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _openTextEditor,
                          icon: const Icon(Icons.text_fields_rounded),
                          label: const Text('Texto'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _saveEditedImage,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Salvar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _TextEditResult {
  final String text;
  final double size;
  final Color color;

  const _TextEditResult({
    required this.text,
    required this.size,
    required this.color,
  });
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.black12,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
