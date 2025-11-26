import 'package:flutter/material.dart';
import 'package:operation_hermes/ui/firebase_image.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/category.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'packs_screen.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<List<Category>>();

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: () {
        if (categories.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return _CategoryListItem(category: category);
          },
        );
      }(),
    );
  }
}

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
            Shimmer.fromColors(
              baseColor: colorScheme.onSurface.withAlpha(26),
              highlightColor: colorScheme.onSurface.withAlpha(51),
              child: Container(color: colorScheme.surfaceContainerHigh),
            ),
            InkWell(
              onTap: () {
                if (!context.mounted || widget.category == null) return;
                final service = context.read<FirebaseService>();

                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => Provider<Stream<List<Pack>>>(
                            create: (ctx) =>
                                service.getPacksStream(widget.category!.id),
                            child: PacksScreen(category: widget.category!),
                          )),
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: colorScheme.tertiaryContainer,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            colorScheme.surface,
                            colorScheme.surface.withAlpha(0),
                          ],
                          stops: const [0.5, 1.0],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: FirebaseImage(
                        storagePath: widget.category?.imagePath ?? '',
                        fit: BoxFit.fitHeight,
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.topCenter,
                        colors: [
                          colorScheme.tertiaryContainer.withAlpha(0),
                          colorScheme.primaryContainer,
                        ],
                        stops: const [0.4, 1.0],
                      ),
                    ),
                  ),
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
        final totalLevels = widget.category.totalLevels;
        final double progress =
            (totalLevels > 0) ? completedLevels / totalLevels : 0.0;

        return SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress < 0 ? 0.0 : progress,
                strokeWidth: 3.0,
                backgroundColor: colorScheme.primary.withAlpha(51),
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withAlpha(179),
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
