import 'package:flutter/material.dart';
import 'package:operation_hermes/ui/firebase_image.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/category.dart';
import 'package:operation_hermes/data/pack.dart'; // Import Pack
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'packs_screen.dart';
import 'package:logging/logging.dart'; // Import the logging package

/// Displays a list of categories.
///
/// This screen reads the list of categories from a global [StreamProvider]
/// and automatically updates when the data changes.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});
  
  static final _log = Logger('CategoriesScreen');

  @override
  Widget build(BuildContext context) {
    // This is CORRECT. It watches the value from the global StreamProvider.
    final categories = context.watch<List<Category>>();
    _log.info('CategoriesScreen build called.');

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: () {
        // `initialData: []` in main.dart means `categories`
        // will be an empty list while loading for the first time.
        if (categories.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // We have data! Just build the list.
        _log.info(
            'CategoriesStream: Rebuilt with ${categories.length} categories.');
        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return _CategoryListItem(category: category);
          },
        );
      }(), // Using () runs this logic block
    );
  }
}

/// A single item in the category list.
class _CategoryListItem extends StatefulWidget {
  const _CategoryListItem({this.category});
  final Category? category;
  @override
  State<_CategoryListItem> createState() => _CategoryListItemState();
}

class _CategoryListItemState extends State<_CategoryListItem> {
  @override
  Widget build(BuildContext context) {
    final isPlaceholder = widget.category == null;
    final colorScheme = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 2 / 1,
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 16.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Shimmer as a base placeholder
            Shimmer.fromColors(
              baseColor: colorScheme.onSurface.withOpacity(0.1),
              highlightColor: colorScheme.onSurface.withOpacity(0.2),
              child: Container(color: colorScheme.surfaceContainerHigh),
            ),
            InkWell(
                onTap: () {
                  // 💡 --- THIS IS THE FIX FOR NAVIGATION ---
                  if (!context.mounted || widget.category == null) return;
                  
                  final service = context.read<FirebaseService>();

                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) =>
                        // 1. Use Provider<Stream<...>> to provide the stream object
                        Provider<Stream<List<Pack>>>(
                          create: (ctx) => service.getPacksStream(widget.category!.id),
                          // 2. No initialData
                          child: PacksScreen(category: widget.category!),
                        )
                    ),
                  );
                  // 💡 --- END OF FIX ---
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Layer 1 (Bottom): The solid background color that fills the card.
                    Container(
                      color: colorScheme.tertiaryContainer,
                    ),

                    // Layer 2a: The image
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ShaderMask(
                        shaderCallback: (bounds) {
                          return LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              colorScheme.surface, 
                              colorScheme.surface.withOpacity(0.0),
                            ],
                            stops: const [ 0.5, 1.0 ],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.dstIn,
                        child: FirebaseImage(
                          storagePath: widget.category?.thumbnailUrl ?? '',
                          fit: BoxFit.fitHeight,
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),

                    // Layer 2b: Extended gradient
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.topCenter,
                          colors: [
                            colorScheme.tertiaryContainer.withAlpha(0),
                            colorScheme.primaryContainer,
                          ],
                          stops: const [ 0.4, 1.0 ],
                        ),
                      ),
                    ),

                    // Layer 3 (Top): Your UI.
                    GridTile(
                      header: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: isPlaceholder
                              ? const SizedBox.shrink()
                              : _CategoryProgressIndicator(
                                  category: widget.category!),
                        ),
                      ),
                      footer: GridTileBar(
                        backgroundColor: colorScheme.surface.withAlpha(150),
                        title: Text(widget.category?.name ?? '',
                            style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold)),
                      ),
                      child: Container(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A widget that shows the user's progress for a specific category.
class _CategoryProgressIndicator extends StatefulWidget {
  final Category category;
  const _CategoryProgressIndicator({required this.category});

  @override
  State<_CategoryProgressIndicator> createState() =>
      _CategoryProgressIndicatorState();
}

class _CategoryProgressIndicatorState
    extends State<_CategoryProgressIndicator> {
  late Future<int> _completedLevelsFuture;
  static final _log = Logger('_CategoryProgressIndicatorState');

  @override
  void initState() {
    super.initState();
    _fetchCompletedLevels();
  }
  
  void _fetchCompletedLevels() {
    final levelModel = context.read<LevelModel>();
    _completedLevelsFuture =
        levelModel.getUnlockedLevelsCountForCategory(widget.category.id);
  }

  @override
  void didUpdateWidget(covariant _CategoryProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category.id != widget.category.id) {
      _fetchCompletedLevels();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<int>(
      future: _completedLevelsFuture,
      builder: (context, snapshot) {
        final completedLevels = snapshot.data ?? 0;
        // 💡 Use the totalLevels from the widget, which came from the denormalized field
        final totalLevels = widget.category.totalLevels; 
        final double progress =
            (totalLevels > 0) ? completedLevels / totalLevels : 0.0;

        _log.info('Category "${widget.category.name}": '
            'calculating progress with completedLevels=$completedLevels, totalLevels=$totalLevels');


        return SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress < 0 ? 0.0 : progress,
                strokeWidth: 3.0,
                backgroundColor: colorScheme.primary.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onTertiaryContainer),
              ),
            ],
          ),
        );
      },
    );
  }
}