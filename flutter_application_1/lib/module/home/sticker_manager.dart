import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whatsapp_stickers_handler/whatsapp_stickers_handler.dart';
import 'package:whatsapp_stickers_handler/model/sticker_pack.dart';

import 'sticker_pack_info.dart';

class StickerManager {
  static Future<Uint8List> _compressWebpToLimit(Uint8List pngBytes, {int maxBytes = 100000}) async {
    int quality = 90;
    Uint8List result = await FlutterImageCompress.compressWithList(
      pngBytes,
      format: CompressFormat.webp,
      quality: quality,
    );

    while (result.lengthInBytes > maxBytes && quality > 10) {
      quality -= 10;
      result = await FlutterImageCompress.compressWithList(
        pngBytes,
        format: CompressFormat.webp,
        quality: quality,
      );
    }

    return result;
  }

  static Future<Uint8List> _readSourceBytes(String src) async {
    if (src.startsWith('http')) {
      return _fetchNetworkBytes(src);
    }
    return File(src).readAsBytes();
  }

  static Future<List<String>> _createStickerFiles({
    required String packId,
    required List<String> sources,
    required int startIndex,
    required int maxCount,
  }) async {
    final stickerFiles = <String>[];
    int index = startIndex;

    for (final src in sources) {
      if (stickerFiles.length >= maxCount) {
        break;
      }

      final bytes = await _readSourceBytes(src);
      final image = img.decodeImage(bytes);
      if (image == null) {
        continue;
      }

      final resized = img.copyResizeCropSquare(image, size: 512);
      final png = img.encodePng(resized);
      final webp = await _compressWebpToLimit(Uint8List.fromList(png));
      final filename = 'sticker_$index.webp';
      final path = await _saveBytesToFile(webp, packId, filename);
      stickerFiles.add(path);
      index++;
    }

    return stickerFiles;
  }

  /// Convert [bytes] to WebP 512x512 and save to app files under stickers/<packId>/name.webp
  static Future<String> saveSticker(Uint8List bytes, String packId, String name) async {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Imagem invalida');
    }
    final resized = img.copyResizeCropSquare(image, size: 512);
    final png = img.encodePng(resized);
    
    final webp = await _compressWebpToLimit(Uint8List.fromList(png));

    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory('${dir.path}/stickers/$packId');
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }
    final file = File('${packDir.path}/$name.webp');
    await file.writeAsBytes(webp);
    return file.path;
  }

  static Future<String> saveTrayIcon(Uint8List bytes, String packId) async {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Imagem invalida');
    }
    final resized = img.copyResizeCropSquare(image, size: 96);
    final png = img.encodePng(resized);

    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory('${dir.path}/stickers/$packId');
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }
    final file = File('${packDir.path}/tray.png');
    await file.writeAsBytes(png);
    return file.path;
  }

  static Future<String> _saveBytesToFile(Uint8List bytes, String packId, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory('${dir.path}/stickers/$packId');
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }
    final file = File('${packDir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<void> saveMetadata(String packId, String packName, String publisher, List<String> stickerFiles, String trayFile) async {
    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory('${dir.path}/stickers/$packId');
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    final trayName = trayFile.split('/').last;
    final stickerNames = stickerFiles.map((f) => f.split('/').last).toList();

    final metadata = {
      'android_play_store_link': '',
      'ios_app_store_link': '',
      'sticker_packs': [
        {
          'identifier': packId,
          'name': packName,
          'publisher': publisher,
          'tray_image_file': trayName,
          'publisher_email': '',
          'publisher_website': '',
          'privacy_policy_website': '',
          'license_agreement_website': '',
          'stickers': stickerNames.map((name) => {'image_file': name, 'emojis': ['😀']}).toList()
        }
      ]
    };

    final metaFile = File('${packDir.path}/contents.json');
    final metaJson = jsonEncode(metadata);
    await metaFile.writeAsString(metaJson);
    debugPrint('✅ Metadata saved: ${metaFile.path}');
    debugPrint('📄 Metadata content: $metaJson');
  }

  static Future<Uint8List> _fetchNetworkBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw Exception('Failed to fetch $url');
  }

  /// Create sticker pack from list of image sources (either local file paths or network URLs represented as strings in [sources]).
  /// [sources] format: if startsWith('http') it'll be fetched; otherwise treated as file path.
  static Future<StickerPackInfo?> createPackAndAdd(String packId, String packName, List<String> sources) async {
    final stickerFiles = <String>[];
    String? trayFile;
    int i = 0;
    for (final src in sources) {
      if (i >= 30) break;
      final bytes = await _readSourceBytes(src);

      final image = img.decodeImage(bytes);
      if (image == null) {
        continue;
      }

      final resized = img.copyResizeCropSquare(image, size: 512);
      final png = img.encodePng(resized);
      final webp = await _compressWebpToLimit(Uint8List.fromList(png));
      final filename = 'sticker_$i.webp';
      final path = await _saveBytesToFile(webp, packId, filename);
      stickerFiles.add(path);

      if (i == 0) {
        final tray = img.copyResizeCropSquare(image, size: 96);
        final trayPng = img.encodePng(tray);
        final trayPath = await _saveBytesToFile(Uint8List.fromList(trayPng), packId, 'tray.png');
        trayFile = trayPath;
      }

      i++;
    }

    if (stickerFiles.isEmpty || trayFile == null) {
      debugPrint('❌ Nenhuma figurinha foi criada');
      return null;
    }

    // Para o WhatsApp, exigem mínimo de 3 figurinhas no pacote
    if (stickerFiles.length < 3) {
      final missing = 3 - stickerFiles.length;
      debugPrint('⚠️ WhatsApp exige no mínimo 3 figurinhas. Duplicando a primeira figurinha $missing vezes...');
      final firstStickerFile = File(stickerFiles.first);
      final firstStickerBytes = await firstStickerFile.readAsBytes();
      
      for (int m = 0; m < missing; m++) {
        final filename = 'sticker_${stickerFiles.length}.webp';
        final path = await _saveBytesToFile(firstStickerBytes, packId, filename);
        stickerFiles.add(path);
      }
    }

    debugPrint('📦 Criando pack com ${stickerFiles.length} figurinhas');
    debugPrint('🎯 Pack ID: $packId');
    debugPrint('📁 Sticker files: $stickerFiles');
    
    await saveMetadata(packId, packName, 'Publisher', stickerFiles, trayFile);

    debugPrint('🚀 Enviando para WhatsApp...');
    
    try {
      final handler = WhatsappStickersHandler();
      final stickerPack = StickerPack(
        identifier: packId,
        name: packName,
        publisher: 'Publisher',
        trayImage: trayFile,
        stickers: stickerFiles,
      );

      await handler.addStickerPack(stickerPack);
      
      debugPrint('Pacote adicionado ao WhatsApp!');
      return StickerPackInfo(
        id: packId,
        name: packName,
        trayPath: trayFile,
        stickers: stickerFiles,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        published: true,
        needsSync: false,
      );
    } catch (e) {
      debugPrint('Erro generico: $e');
      return null;
    }
  }

  static Future<StickerPackInfo?> addStickersToPack(
    StickerPackInfo pack,
    List<String> sources,
  ) async {
    if (sources.isEmpty) {
      return null;
    }

    final remaining = 30 - pack.stickers.length;
    if (remaining <= 0) {
      debugPrint('⚠️ Pacote cheio (max 30 figurinhas)');
      return null;
    }

    final newStickers = await _createStickerFiles(
      packId: pack.id,
      sources: sources,
      startIndex: pack.stickers.length,
      maxCount: remaining,
    );

    if (newStickers.isEmpty) {
      return null;
    }

    String trayPath = pack.trayPath;
    if (trayPath.trim().isEmpty && sources.isNotEmpty) {
      final firstBytes = await _readSourceBytes(sources.first);
      trayPath = await saveTrayIcon(firstBytes, pack.id);
    }

    final allStickers = [...pack.stickers, ...newStickers];

    if (!pack.published && allStickers.length < 3) {
      return pack.copyWith(
        stickers: allStickers,
        trayPath: trayPath,
        needsSync: false,
      );
    }

    var stickersForPublish = List<String>.from(allStickers);
    if (stickersForPublish.length < 3) {
      final missing = 3 - stickersForPublish.length;
      final firstStickerFile = File(stickersForPublish.first);
      final firstStickerBytes = await firstStickerFile.readAsBytes();
      for (int m = 0; m < missing; m++) {
        final filename = 'sticker_${stickersForPublish.length}.webp';
        final path = await _saveBytesToFile(firstStickerBytes, pack.id, filename);
        stickersForPublish.add(path);
      }
    }

    await saveMetadata(pack.id, pack.name, 'Publisher', stickersForPublish, trayPath);

    try {
      final handler = WhatsappStickersHandler();
      final stickerPack = StickerPack(
        identifier: pack.id,
        name: pack.name,
        publisher: 'Publisher',
        trayImage: trayPath,
        stickers: stickersForPublish,
      );

      if (pack.published) {
        await handler.updateStickerPack(stickerPack);
      } else {
        await handler.addStickerPack(stickerPack);
      }

      return pack.copyWith(
        stickers: allStickers,
        trayPath: trayPath,
        published: true,
        needsSync: false,
      );
    } catch (e) {
      debugPrint('Erro generico: $e');
      return pack.copyWith(
        stickers: allStickers,
        trayPath: trayPath,
        needsSync: true,
      );
    }
  }

  static Future<StickerPackInfo?> syncPack(StickerPackInfo pack) async {
    if (pack.stickers.isEmpty) {
      return null;
    }

    String trayPath = pack.trayPath;
    if (trayPath.trim().isEmpty) {
      final firstStickerBytes = await File(pack.stickers.first).readAsBytes();
      trayPath = await saveTrayIcon(firstStickerBytes, pack.id);
    }

    if (pack.stickers.length < 3) {
      return pack.copyWith(trayPath: trayPath, needsSync: false);
    }

    await saveMetadata(pack.id, pack.name, 'Publisher', pack.stickers, trayPath);

    try {
      final handler = WhatsappStickersHandler();
      final stickerPack = StickerPack(
        identifier: pack.id,
        name: pack.name,
        publisher: 'Publisher',
        trayImage: trayPath,
        stickers: pack.stickers,
      );

      if (pack.published) {
        await handler.updateStickerPack(stickerPack);
      } else {
        await handler.addStickerPack(stickerPack);
      }

      return pack.copyWith(
        trayPath: trayPath,
        published: true,
        needsSync: false,
      );
    } catch (e) {
      debugPrint('Erro generico: $e');
      return pack.copyWith(trayPath: trayPath, needsSync: true);
    }
  }
}