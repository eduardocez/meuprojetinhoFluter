import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

enum _CropHandle { topLeft, topRight, bottomLeft, bottomRight }

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
  static const double _minCropScale = 1.0;
  static const double _maxCropScale = 4.0;
  static const double _minCropSize = 120;
  static const double _handleSize = 20;
  static const double _moveHandleSize = 26;

  final GlobalKey _canvasKey = GlobalKey();
  final TransformationController _cropController = TransformationController();

  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Size? _imageSize;
  Size _canvasSize = Size.zero;
  Rect _cropRect = Rect.zero;
  Size _lastCanvasSize = Size.zero;

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
    _cropController.dispose();
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

  void _ensureCropRectInitialized(Size size) {
    if (_cropRect != Rect.zero && _lastCanvasSize == size) {
      return;
    }

    _lastCanvasSize = size;
    final width = size.width * 0.78;
    final height = size.height * 0.78;
    final center = Offset(size.width / 2, size.height / 2);
    _cropRect = Rect.fromCenter(center: center, width: width, height: height);
  }

  Rect _fitRectToCanvas(Rect rect) {
    double left = rect.left;
    double top = rect.top;

    if (left < 0) {
      left = 0;
    }
    if (top < 0) {
      top = 0;
    }
    if (left + rect.width > _canvasSize.width) {
      left = _canvasSize.width - rect.width;
    }
    if (top + rect.height > _canvasSize.height) {
      top = _canvasSize.height - rect.height;
    }

    return Rect.fromLTWH(left, top, rect.width, rect.height);
  }

  void _moveCropRect(Offset delta) {
    final next = _fitRectToCanvas(_cropRect.shift(delta));
    setState(() {
      _cropRect = next;
    });
  }

  Widget _buildCropOverlay(ColorScheme colorScheme) {
    if (_cropRect == Rect.zero) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CropOverlayPainter(
                cropRect: _cropRect,
                overlayColor: Colors.black.withAlpha(160),
                borderColor: colorScheme.primary,
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: _cropRect,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) => _moveCropRect(details.delta),
            child: const SizedBox.expand(),
          ),
        ),
        _buildCropHandle(_CropHandle.topLeft, _cropRect.topLeft, colorScheme),
        _buildCropHandle(_CropHandle.topRight, _cropRect.topRight, colorScheme),
        _buildCropHandle(
          _CropHandle.bottomLeft,
          _cropRect.bottomLeft,
          colorScheme,
        ),
        _buildCropHandle(
          _CropHandle.bottomRight,
          _cropRect.bottomRight,
          colorScheme,
        ),
      ],
    );
  }

  Widget _buildCropHandle(
    _CropHandle handle,
    Offset center,
    ColorScheme colorScheme,
  ) {
    return Positioned(
      left: center.dx - _moveHandleSize / 2,
      top: center.dy - _moveHandleSize / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) => _resizeCropRect(handle, details.delta),
        child: SizedBox(
          width: _moveHandleSize,
          height: _moveHandleSize,
          child: Center(
            child: Container(
              width: _handleSize,
              height: _handleSize,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.primary, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _resizeCropRect(_CropHandle handle, Offset delta) {
    final rect = _cropRect;
    double left = rect.left;
    double top = rect.top;
    double right = rect.right;
    double bottom = rect.bottom;

    switch (handle) {
      case _CropHandle.topLeft:
        left += delta.dx;
        top += delta.dy;
        break;
      case _CropHandle.topRight:
        right += delta.dx;
        top += delta.dy;
        break;
      case _CropHandle.bottomLeft:
        left += delta.dx;
        bottom += delta.dy;
        break;
      case _CropHandle.bottomRight:
        right += delta.dx;
        bottom += delta.dy;
        break;
    }

    if (right - left < _minCropSize) {
      if (handle == _CropHandle.topLeft || handle == _CropHandle.bottomLeft) {
        left = right - _minCropSize;
      } else {
        right = left + _minCropSize;
      }
    }

    if (bottom - top < _minCropSize) {
      if (handle == _CropHandle.topLeft || handle == _CropHandle.topRight) {
        top = bottom - _minCropSize;
      } else {
        bottom = top + _minCropSize;
      }
    }

    if (right - left > _canvasSize.width) {
      if (handle == _CropHandle.topLeft || handle == _CropHandle.bottomLeft) {
        left = right - _canvasSize.width;
      } else {
        right = left + _canvasSize.width;
      }
    }

    if (bottom - top > _canvasSize.height) {
      if (handle == _CropHandle.topLeft || handle == _CropHandle.topRight) {
        top = bottom - _canvasSize.height;
      } else {
        bottom = top + _canvasSize.height;
      }
    }

    final next = _fitRectToCanvas(Rect.fromLTRB(left, top, right, bottom));
    setState(() {
      _cropRect = _fitRectToCanvas(next);
    });
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
                        onTap: () =>
                            setSheetState(() => tempColor = Colors.white),
                      ),
                      _ColorDot(
                        color: Colors.black,
                        selected: tempColor == Colors.black,
                        onTap: () =>
                            setSheetState(() => tempColor = Colors.black),
                      ),
                      _ColorDot(
                        color: Colors.redAccent,
                        selected: tempColor == Colors.redAccent,
                        onTap: () =>
                            setSheetState(() => tempColor = Colors.redAccent),
                      ),
                      _ColorDot(
                        color: Colors.blueAccent,
                        selected: tempColor == Colors.blueAccent,
                        onTap: () =>
                            setSheetState(() => tempColor = Colors.blueAccent),
                      ),
                      _ColorDot(
                        color: Colors.green,
                        selected: tempColor == Colors.green,
                        onTap: () =>
                            setSheetState(() => tempColor = Colors.green),
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
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
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
      String outputPath;

      if (_cropRect == Rect.zero) {
        outputPath = await _writeEditedFile(bytes);
      } else {
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          outputPath = await _writeEditedFile(bytes);
        } else {
          final scaleX = decoded.width / _canvasSize.width;
          final scaleY = decoded.height / _canvasSize.height;
          final cropLeft = (_cropRect.left * scaleX).round();
          final cropTop = (_cropRect.top * scaleY).round();
          final cropWidth = (_cropRect.width * scaleX).round().clamp(
            1,
            decoded.width,
          );
          final cropHeight = (_cropRect.height * scaleY).round().clamp(
            1,
            decoded.height,
          );
          final cropped = img.copyCrop(
            decoded,
            x: cropLeft,
            y: cropTop,
            width: cropWidth,
            height: cropHeight,
          );
          final croppedBytes = Uint8List.fromList(img.encodePng(cropped));
          outputPath = await _writeEditedFile(croppedBytes);
        }
      }

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
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: AspectRatio(
                        aspectRatio: _imageSize!.width / _imageSize!.height,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              _canvasSize = constraints.biggest;
                              _ensureCropRectInitialized(_canvasSize);
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  RepaintBoundary(
                                    key: _canvasKey,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Container(color: Colors.black),
                                        InteractiveViewer(
                                          transformationController:
                                              _cropController,
                                          minScale: _minCropScale,
                                          maxScale: _maxCropScale,
                                          panEnabled: true,
                                          scaleEnabled: true,
                                          clipBehavior: Clip.hardEdge,
                                          boundaryMargin: const EdgeInsets.all(
                                            96,
                                          ),
                                          child: SizedBox.expand(
                                            child: Image.file(
                                              File(widget.imagePath),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                        if (_text.trim().isNotEmpty)
                                          Positioned(
                                            left: _textOffset.dx,
                                            top: _textOffset.dy,
                                            child: GestureDetector(
                                              onPanUpdate: (details) {
                                                final bounds =
                                                    _cropRect == Rect.zero
                                                    ? Rect.fromLTWH(
                                                        0,
                                                        0,
                                                        _canvasSize.width,
                                                        _canvasSize.height,
                                                      )
                                                    : _cropRect;
                                                final next =
                                                    _textOffset + details.delta;
                                                setState(() {
                                                  _textOffset = Offset(
                                                    next.dx.clamp(
                                                      bounds.left,
                                                      bounds.right - 20,
                                                    ),
                                                    next.dy.clamp(
                                                      bounds.top,
                                                      bounds.bottom - 20,
                                                    ),
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
                                    ),
                                  ),
                                  _buildCropOverlay(colorScheme),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
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
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black12,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final Color overlayColor;
  final Color borderColor;

  const _CropOverlayPainter({
    required this.cropRect,
    required this.overlayColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cropRect == Rect.zero) {
      return;
    }

    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;

    final overlayPaint = Paint()..color = overlayColor;
    canvas.drawPath(overlayPath, overlayPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(cropRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.borderColor != borderColor;
  }
}
