// Defines the data model for a Pack.
// This model is tailored for the player's view, containing essential
// display information like name, description, and thumbnail.

import 'package:cloud_firestore/cloud_firestore.dart';

class Pack {
  final String id;
  final String name;
  final String description;
  final String thumbnailUrl;
  final String categoryId;
  final int order;
  final DateTime lastUpdated;
  final int totalLevels;

  Pack({
    required this.id,
    required this.name,
    required this.description,
    required this.thumbnailUrl,
    required this.categoryId,
    required this.order,
    required this.lastUpdated,
    required this.totalLevels
  });

  // Factory constructor to parse data from a database (like Firestore).
  // The client app's query would filter out any packs that are not
  // enabled, so no 'isEnabled' flag is needed here.
  factory Pack.fromMap(String id, Map<String, dynamic> data, {int? totalLevels}) {
    return Pack(
      id: id,
      name: data['name'] ?? 'Unnamed Pack',
      description: data['description'] ?? '',
      thumbnailUrl: data['imagePath'] ?? '',
      categoryId: data['categoryId'] ?? '',
      order: data['order'] ?? 0,
      lastUpdated: (data['modifiedAt'] as Timestamp).toDate(),
      totalLevels: totalLevels ?? data['totalLevels'] ?? 0
    );
  }
}
