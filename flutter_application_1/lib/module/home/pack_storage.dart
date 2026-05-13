import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'sticker_pack_info.dart';

class PackStorage {
  static const String _fileName = 'sticker_packs.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<StickerPackInfo>> loadPacks() async {
    final file = await _getFile();
    if (!await file.exists()) {
      return <StickerPackInfo>[];
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return <StickerPackInfo>[];
      }

      final data = jsonDecode(raw) as List<dynamic>;
      final packs = data
          .whereType<Map<String, dynamic>>()
          .map(StickerPackInfo.fromJson)
          .toList();

      packs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return packs;
    } catch (_) {
      return <StickerPackInfo>[];
    }
  }

  static Future<void> savePacks(List<StickerPackInfo> packs) async {
    final file = await _getFile();
    final jsonList = packs.map((p) => p.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
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
}
