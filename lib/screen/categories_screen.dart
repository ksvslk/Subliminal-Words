import 'package:flutter/material.dart';
import 'package:operation_hermes/firebase_image.dart';
import 'package:operation_hermes/game/model/level_model.dart';
import 'package:operation_hermes/level/firebase_service.dart';
import 'package:operation_hermes/model/category.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
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
    final firebaseService =
        Provider.of<FirebaseService>(context, listen: false);
    _categoriesFuture = firebaseService.getCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
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
          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return _CategoryListItem(category: category);
            },
          );
        },
      ),
    );
  }
}

class _CategoryListItem extends StatefulWidget {
  const _CategoryListItem({required this.category});
  final Category category;
  @override
  State<_CategoryListItem> createState() => _CategoryListItemState();
}

class _CategoryListItemState extends State<_CategoryListItem> {
  bool _isLoaded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final levelModel = context.watch<LevelModel>();

    final int completedLevels =
        levelModel.getUnlockedLevelsCountForCategory(widget.category.id);
    final int totalLevels = widget.category.totalLevels;
    final double progress =
        (totalLevels > 0) ? completedLevels / totalLevels : 0.0;

    return AspectRatio(
      aspectRatio: 2.5 / 1,
      child: Card(
        elevation: 2, // Slightly increased elevation for better depth
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 16.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Shimmer.fromColors(
              baseColor: colorScheme.onSurface.withOpacity(0.1),
              highlightColor: colorScheme.onSurface.withOpacity(0.2),
              // UPDATED: Shimmer child is colorless for theme compatibility
              child: Container(color: colorScheme.surfaceContainerHigh),
            ),
            AnimatedOpacity(
              opacity: _isLoaded ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeIn,
              child: InkWell(
                onTap: () async {
                  await Future.delayed(const Duration(milliseconds: 50));
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PacksScreen(category: widget.category)),
                  );
                },
                child: Container(
                  color: colorScheme.tertiaryContainer,
                  child: GridTile(
                    header: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 3.0,
                                backgroundColor:
                                    colorScheme.primary.withOpacity(0.2),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    colorScheme.primary),
                              ),
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: colorScheme.tertiaryContainer
                                      .withOpacity(0.7),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  // UPDATED: Using correct theme color for text on this container
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    footer: GridTileBar(
                      backgroundColor: colorScheme.surface.withAlpha(150),
                      title: Text(widget.category.name,
                          style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold)),
                    ),
                    child: FirebaseImage(
                      storagePath: widget.category.thumbnailUrl,
                      onLoaded: () => setState(() => _isLoaded = true),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}