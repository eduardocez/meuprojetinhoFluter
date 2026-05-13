import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whatsapp_stickers_plus/whatsapp_stickers.dart';
import 'package:whatsapp_stickers_plus/exceptions.dart';

class StickerManager {
  static const MethodChannel _channel = MethodChannel('flutter.whatsapp.stickers');

  /// Convert [bytes] to WebP 512x512 and save to app files under stickers/<packId>/name.webp
  static Future<String> saveSticker(Uint8List bytes, String packId, String name) async {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Imagem invalida');
    }
    final resized = img.copyResizeCropSquare(image, 512);
    final png = img.encodePng(resized);
    
    final webp = await FlutterImageCompress.compressWithList(
      Uint8List.fromList(png),
      format: CompressFormat.webp,
      quality: 90,
    );

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
    final resized = img.copyResizeCropSquare(image, 96);
    final png = img.encodePng(resized);
    
    final webp = await FlutterImageCompress.compressWithList(
      Uint8List.fromList(png),
      format: CompressFormat.webp,
      quality: 90,
    );

    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory('${dir.path}/stickers/$packId');
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }
    final file = File('${packDir.path}/tray.webp');
    await file.writeAsBytes(webp);
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
  static Future<bool> createPackAndAdd(String packId, String packName, List<String> sources) async {
    final stickerFiles = <String>[];
    String? trayFile;
    int i = 0;
    for (final src in sources) {
      if (i >= 30) break;
      Uint8List bytes;
      if (src.startsWith('http')) {
        bytes = await _fetchNetworkBytes(src);
      } else {
        bytes = await File(src).readAsBytes();
      }

      final image = img.decodeImage(bytes);
      if (image == null) {
        continue;
      }

      final resized = img.copyResizeCropSquare(image, 512);
      final png = img.encodePng(resized);
      final webp = await FlutterImageCompress.compressWithList(
        Uint8List.fromList(png),
        format: CompressFormat.webp,
        quality: 90,
      );
      final filename = 'sticker_$i.webp';
      final path = await _saveBytesToFile(webp, packId, filename);
      stickerFiles.add(path);

      if (i == 0) {
        final tray = img.copyResizeCropSquare(image, 96);
        final trayPng = img.encodePng(tray);
        final trayWebp = await FlutterImageCompress.compressWithList(
          Uint8List.fromList(trayPng),
          format: CompressFormat.webp,
          quality: 90,
        );
        final trayPath = await _saveBytesToFile(trayWebp, packId, 'tray.webp');
        trayFile = trayPath;
      }

      i++;
    }

    if (stickerFiles.isEmpty || trayFile == null) {
      debugPrint('❌ Nenhuma figurinha foi criada');
      return false;
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
    
    // Envia usando a biblioteca
    try {
      final stickerPack = WhatsappStickers(
        identifier: packId,
        name: packName,
        publisher: 'Publisher',
        trayImageFileName: WhatsappStickerImage.fromFile(trayFile),
        publisherWebsite: '',
        privacyPolicyWebsite: '',
        licenseAgreementWebsite: '',
      );

      for (final sf in stickerFiles) {
        stickerPack.addSticker(WhatsappStickerImage.fromFile(sf), ['😀']);
      }

      await stickerPack.sendToWhatsApp();
      debugPrint('Pacote adicionado ao WhatsApp!');
      return true;
    } on WhatsappStickersException catch (e) {
      debugPrint('Erro do WhatsApp: ${e.cause}');
      return false;
    } catch (e) {
      debugPrint('Erro generico: $e');
      return false;
    }
  }

  /// Ask the Android side to add the sticker pack to WhatsApp. packId must match saved files.
  static Future<bool> addPackToWhatsApp(String packId, String packName) async {
    final res = await _channel.invokeMethod('addStickerPack', {
      'packId': packId,
      'packName': packName,
    });
    return res == true;
  }
}