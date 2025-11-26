class Category {
  final String id;
  final String name;
  final String thumbnailUrl;
  final String imagePath;
  final int order;
  final int totalLevels;

  Category({
    required this.id,
    required this.name,
    required this.thumbnailUrl,
    required this.imagePath,
    required this.order,
    required this.totalLevels,
  });

  factory Category.fromMap(String id, Map<String, dynamic> data, {int? totalLevels}) {
    return Category(
      id: id,
      name: data['name'] ?? 'Unnamed Category',
      thumbnailUrl: data['thumbnailPath'] ?? '',
      imagePath: data['imagePath'] ?? '',
      order: data['order'] ?? 0,
      totalLevels: totalLevels ?? data['totalLevels'] ?? 0
    );
  }
}
