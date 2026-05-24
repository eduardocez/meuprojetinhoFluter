class StickerPackInfo {
  final String id;
  final String name;
  final String trayPath;
  final List<String> stickers;
  final int createdAt;
  final bool published;
  final bool needsSync;

  const StickerPackInfo({
    required this.id,
    required this.name,
    required this.trayPath,
    required this.stickers,
    required this.createdAt,
    required this.published,
    required this.needsSync,
  });

  StickerPackInfo copyWith({
    String? id,
    String? name,
    String? trayPath,
    List<String>? stickers,
    int? createdAt,
    bool? published,
    bool? needsSync,
  }) {
    return StickerPackInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      trayPath: trayPath ?? this.trayPath,
      stickers: stickers ?? this.stickers,
      createdAt: createdAt ?? this.createdAt,
      published: published ?? this.published,
      needsSync: needsSync ?? this.needsSync,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'trayPath': trayPath,
      'stickers': stickers,
      'createdAt': createdAt,
      'published': published,
      'needsSync': needsSync,
    };
  }

  factory StickerPackInfo.fromJson(Map<String, dynamic> json) {
    final stickers = (json['stickers'] as List?)?.cast<String>() ?? <String>[];
    final id = json['id'] as String? ?? '';
    final name = json['name'] as String? ?? '';
    final trayPath = json['trayPath'] as String? ?? '';
    return StickerPackInfo(
      id: id,
      name: name,
      trayPath: trayPath,
      stickers: stickers,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      published: json['published'] as bool? ?? false,
      needsSync: json['needsSync'] as bool? ?? false,
    );
  }
}
