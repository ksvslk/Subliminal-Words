import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:operation_hermes/firebase_options.dart';
import 'package:operation_hermes/model/level.dart';
import 'package:operation_hermes/model/pack.dart';
import 'package:operation_hermes/model/category.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
      bucket: DefaultFirebaseOptions.currentPlatform.storageBucket!);

  final Map<String, String> _urlCache = {};

  Future<String> getDownloadUrl(String storagePath) async {
    debugPrint("[FirebaseService] Requesting URL for storagePath: '$storagePath'");

    if (storagePath.isEmpty) {
      debugPrint("[FirebaseService] Path is empty, returning empty URL.");
      return '';
    }
    if (_urlCache.containsKey(storagePath)) {
      debugPrint("[FirebaseService] Returning cached URL.");
      return _urlCache[storagePath]!;
    }
    try {
      // This is the correct method for relative paths like "categories/..."
      final ref = _storage.ref(storagePath);
      final url = await ref.getDownloadURL();

      debugPrint("[FirebaseService] Successfully fetched URL: '$url'");
      _urlCache[storagePath] = url;
      return url;
    } catch (e) {
      debugPrint("[FirebaseService] !!! FAILED to get download URL for '$storagePath'. Error: $e");
      // This is often a permissions error. Check your Firebase Storage Rules from Step 1.
      return '';
    }
  }

  Future<List<Category>> getCategories() async {
    final snapshot = await _db
        .collection('categories')
        .where('isEnabled', isEqualTo: true)
        .orderBy('order')
        .get();
    return snapshot.docs
        .map((doc) => Category.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<List<Pack>> getPacks(String categoryId) async {
    final snapshot = await _db
        .collection('packs')
        .where('categoryId', isEqualTo: categoryId)
        .where('isEnabled', isEqualTo: true)
        .orderBy('order')
        .get();
    return snapshot.docs
        .map((doc) => Pack.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<List<Level>> getLevels(String packId) async {
    final snapshot = await _db
        .collection('packs')
        .doc(packId)
        .collection('levels')
        .where('isEnabled', isEqualTo: true)
        .orderBy('nr')
        .get();
    return snapshot.docs
        .map((doc) => Level.fromMap(doc.id, doc.data()))
        .toList();
  }
}

