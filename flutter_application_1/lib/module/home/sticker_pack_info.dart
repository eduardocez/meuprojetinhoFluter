class StickerPackInfo {
  final String id;
  final String name;
  final String trayPath;
  final List<String> stickers;
  final int createdAt;

  const StickerPackInfo({
    required this.id,
    required this.name,
    required this.trayPath,
    required this.stickers,
    required this.createdAt,
  });

  StickerPackInfo copyWith({
    String? id,
    String? name,
    String? trayPath,
    List<String>? stickers,
    int? createdAt,
  }) {
    return StickerPackInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      trayPath: trayPath ?? this.trayPath,
      stickers: stickers ?? this.stickers,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'trayPath': trayPath,
      'stickers': stickers,
      'createdAt': createdAt,
    };
  }

  factory StickerPackInfo.fromJson(Map<String, dynamic> json) {
    final stickers = (json['stickers'] as List?)?.cast<String>() ?? <String>[];
    return StickerPackInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      trayPath: json['trayPath'] as String,
      stickers: stickers,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}
