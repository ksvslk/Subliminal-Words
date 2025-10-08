// Defines the data model for a Level.
// This is a minimal model for the client, providing just enough
// information to display the level selection grid.

class Level {
  final String id;
  final String name;
  final int nr;
  final String puzzleUrl;

  Level({
    required this.id,
    required this.name,
    required this.nr,
    required this.puzzleUrl,
  });

  // Factory constructor to create a Level instance from a map.
  // The backend would ensure that only enabled levels are sent
  // to the client, keeping the app's logic simple.
  factory Level.fromMap(String id, Map<String, dynamic> data) {
    return Level(
      id: id,
      name: data['name'] ?? 'Unnamed Level',
      nr: data['nr'] ?? 0,
      puzzleUrl: data['puzzleUrl'] ?? '',
    );
  }
}
