// Defines the data model for a Pack.
// This model is tailored for the player's view, containing essential
// display information like name, description, and thumbnail.

class Pack {
  final String id;
  final String name;
  final String description;
  final String thumbnailUrl;
  final String categoryId;
  final int order;

  Pack({
    required this.id,
    required this.name,
    required this.description,
    required this.thumbnailUrl,
    required this.categoryId,
    required this.order,
  });

  // Factory constructor to parse data from a database (like Firestore).
  // The client app's query would filter out any packs that are not
  // enabled, so no 'isEnabled' flag is needed here.
  factory Pack.fromMap(String id, Map<String, dynamic> data) {
    return Pack(
      id: id,
      name: data['name'] ?? 'Unnamed Pack',
      description: data['description'] ?? '',
      thumbnailUrl: data['thumbnailPath'] ?? '',
      categoryId: data['categoryId'] ?? '',
      order: data['order'] ?? 0,
    );
  }
}

