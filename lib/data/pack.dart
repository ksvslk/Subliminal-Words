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
