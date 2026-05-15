import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'sticker_pack_info.dart';

class PackStorage {
  static const String _fileName = 'sticker_packs.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_fileName');
  }

  static Future<File> _getLegacyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<StickerPackInfo>> loadPacks() async {
    final file = await _getFile();
    var readFile = file;
    if (!await file.exists()) {
      final legacy = await _getLegacyFile();
      if (await legacy.exists()) {
        readFile = legacy;
      } else {
        return <StickerPackInfo>[];
      }
    }

    try {
      final raw = await readFile.readAsString();
      if (raw.trim().isEmpty) {
        return <StickerPackInfo>[];
      }

      final decoded = jsonDecode(raw);
      final data = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
              ? (decoded['packs'] as List?)
              : null;

      if (data == null) {
        return <StickerPackInfo>[];
      }

      final packs = <StickerPackInfo>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          try {
            packs.add(StickerPackInfo.fromJson(item));
          } catch (e) {
            debugPrint('Erro ao ler pacote: $e');
          }
        }
      }

      packs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (readFile.path != file.path) {
        await savePacks(packs);
      }
      return packs;
    } catch (e) {
      debugPrint('Erro ao ler storage: $e');
      return <StickerPackInfo>[];
    }
  }

  static Future<void> savePacks(List<StickerPackInfo> packs) async {
    final file = await _getFile();
    final jsonList = packs.map((p) => p.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList), flush: true);
  }

  static Future<void> addPack(StickerPackInfo pack) async {
    final packs = await loadPacks();
    packs.removeWhere((p) => p.id == pack.id);
    packs.insert(0, pack);
    await savePacks(packs);
  }

  static Future<void> updatePack(StickerPackInfo pack) async {
    final packs = await loadPacks();
    final index = packs.indexWhere((p) => p.id == pack.id);
    if (index >= 0) {
      packs[index] = pack;
    } else {
      packs.insert(0, pack);
    }
    await savePacks(packs);
  }

  static Future<void> removePack(String packId) async {
    final packs = await loadPacks();
    packs.removeWhere((p) => p.id == packId);
    await savePacks(packs);
  }
}
