// Defines the data model for a Category.
// This is a simple, read-only model for the client app, containing
// only the information needed to display the category to the player.

class Category {
  final String id;
  final String name;
  final String thumbnailUrl;
  final int order;
  final int totalLevels;

  Category({
    required this.id,
    required this.name,
    required this.thumbnailUrl,
    required this.order,
    required this.totalLevels,
  });

  // This factory constructor creates a Category instance from a map.
  // In a real app, you would fetch only the 'enabled' categories
  // from your backend to display in the client app.
  factory Category.fromMap(String id, Map<String, dynamic> data, {int? totalLevels}) {
    return Category(
      id: id,
      name: data['name'] ?? 'Unnamed Category',
      thumbnailUrl: data['thumbnailPath'] ?? '',
      order: data['order'] ?? 0,
      totalLevels: totalLevels ?? data['totalLevels'] ?? 0
    );
  }
}
