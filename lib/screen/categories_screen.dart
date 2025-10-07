import 'package:flutter/material.dart';
import 'package:operation_hermes/firebase_image.dart';
import 'package:operation_hermes/level/firebase_service.dart';
import 'package:operation_hermes/model/category.dart';
import 'package:provider/provider.dart';
import 'packs_screen.dart';


class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<List<Category>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    final firebaseService = Provider.of<FirebaseService>(context, listen: false);
    _categoriesFuture = firebaseService.getCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      ),
      body: FutureBuilder<List<Category>>(
        future: _categoriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No categories found.'));
          }

          final categories = snapshot.data!;
          final screenWidth = MediaQuery.of(context).size.width;
          final crossAxisCount = (screenWidth / 200).floor().clamp(2, 4);

          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
              childAspectRatio: 3 / 2,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => PacksScreen(category: category)),
                ),
                child: Card(
                  elevation: 4,
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  clipBehavior: Clip.antiAlias,
                  child: GridTile(
                    footer: GridTileBar(
                      backgroundColor: Colors.black45,
                      title: Text(category.name,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onTertiaryContainer,
                              fontWeight: FontWeight.bold)),
                    ),
                    child: FirebaseImage(storagePath: category.thumbnailUrl),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

