import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:whatsapp_stickers_handler/model/sticker_pack.dart';
import 'package:whatsapp_stickers_handler/whatsapp_stickers_handler.dart';

import 'sticker_pack_info.dart';

class StickerManager {
  static Future<bool> _fileExists(String path) async {
    if (path.trim().isEmpty) {
      return false;
    }
    return File(path).exists();
  }

  static Future<List<String>> _listStickerFiles(String packId) async {
    if (packId.trim().isEmpty) {
      return <String>[];
    }

    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory('${dir.path}/stickers/$packId');
    if (!await packDir.exists()) {
      return <String>[];
    }

    final files = await packDir.list().toList();
    final stickerFiles = files
        .whereType<File>()
        .where((file) {
          final name = file.path.split('/').last;
          return name.startsWith('sticker_') && name.endsWith('.webp');
        })
        .map((file) => file.path)
        .toList();

    stickerFiles.sort();
    return stickerFiles;
  }

  static Future<List<String>> _listLegacyStickerFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final legacyDir = Directory('${dir.path}/stickers');
    if (!await legacyDir.exists()) {
      return <String>[];
    }

    final files = await legacyDir.list().toList();
    final stickerFiles = files
        .whereType<File>()
        .where((file) {
          final name = file.path.split('/').last;
          return name.startsWith('sticker_') && name.endsWith('.webp');
        })
        .map((file) => file.path)
        .toList();

    stickerFiles.sort();
    return stickerFiles;
  }

  static Future<StickerPackInfo> _migrateLegacyFiles(StickerPackInfo pack) async {
    final legacyStickers = await _listLegacyStickerFiles();
    if (legacyStickers.isEmpty) {
      return pack;
    }

    final updated = await _ensurePackId(pack);
    if (updated.id == pack.id && updated.stickers.isNotEmpty) {
      return updated;
    }

    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory('${dir.path}/stickers/${updated.id}');
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    final movedStickers = <String>[];
    for (final path in legacyStickers) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      final filename = path.split('/').last;
      final newPath = '${packDir.path}/$filename';
      await file.rename(newPath);
      movedStickers.add(newPath);
    }

    return updated.copyWith(stickers: movedStickers, needsSync: true);
  }

  static Future<StickerPackInfo> refreshPackFromDisk(StickerPackInfo pack) async {
    var refreshed = pack;

    if (refreshed.id.trim().isEmpty) {
      refreshed = await _migrateLegacyFiles(refreshed);
      return refreshed;
    }

    final existing = <String>[];
    for (final path in refreshed.stickers) {
      if (await _fileExists(path)) {
        existing.add(path);
      }
    }

    final diskStickers = await _listStickerFiles(refreshed.id);
    final resolvedStickers = diskStickers.isNotEmpty ? diskStickers : existing;

    if (resolvedStickers.isEmpty) {
      refreshed = await _migrateLegacyFiles(refreshed);
      return refreshed;
    }

    String trayPath = refreshed.trayPath;
    if (!await _fileExists(trayPath)) {
      final firstBytes = await File(resolvedStickers.first).readAsBytes();
      trayPath = await saveTrayIcon(firstBytes, refreshed.id);
    }

    return refreshed.copyWith(stickers: resolvedStickers, trayPath: trayPath);
  }

  static Future<StickerPackInfo> _ensurePackId(StickerPackInfo pack) async {
    if (pack.id.trim().isNotEmpty) {
      return pack;
    }

    final newId = 'pack_${DateTime.now().millisecondsSinceEpoch}';
    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory('${dir.path}/stickers/$newId');
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }

    final movedStickers = <String>[];
    for (final path in pack.stickers) {
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      final filename = path.split('/').last;
      final newPath = '${packDir.path}/$filename';
      await file.rename(newPath);
      movedStickers.add(newPath);
    }

    String trayPath = pack.trayPath;
    if (trayPath.trim().isNotEmpty) {
      final trayFile = File(trayPath);
      if (await trayFile.exists()) {
        final newTrayPath = '${packDir.path}/tray.png';
        await trayFile.rename(newTrayPath);
        trayPath = newTrayPath;
      }
    }

    return pack.copyWith(
      id: newId,
      trayPath: trayPath,
      stickers: movedStickers,
      published: false,
      needsSync: true,
    );
  }

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

  static Future<void> saveMetadata(
    String packId,
    String packName,
    String publisher,
    List<String> stickerFiles,
    String trayFile,
  ) async {
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

  static Future<StickerPackInfo?> createPackAndAdd(
    String packId,
    String packName,
    List<String> sources,
  ) async {
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
      return StickerPackInfo(
        id: packId,
        name: packName,
        trayPath: trayFile,
        stickers: stickerFiles,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        published: false,
        needsSync: true,
      );
    }
  }

  static Future<StickerPackInfo?> addStickersToPack(
    StickerPackInfo pack,
    List<String> sources,
  ) async {
    if (sources.isEmpty) {
      return null;
    }

    pack = await _ensurePackId(pack);
    if (pack.stickers.isEmpty) {
      final diskStickers = await _listStickerFiles(pack.id);
      if (diskStickers.isNotEmpty) {
        pack = pack.copyWith(stickers: diskStickers);
      }
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
    final stickersForPublish = List<String>.from(allStickers);
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
    pack = await _ensurePackId(pack);
    if (pack.stickers.isEmpty) {
      final diskStickers = await _listStickerFiles(pack.id);
      if (diskStickers.isNotEmpty) {
        pack = pack.copyWith(stickers: diskStickers);
      }
    }

    if (pack.stickers.isEmpty) {
      return null;
    }

    String trayPath = pack.trayPath;
    if (trayPath.trim().isEmpty) {
      final firstStickerBytes = await File(pack.stickers.first).readAsBytes();
      trayPath = await saveTrayIcon(firstStickerBytes, pack.id);
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
