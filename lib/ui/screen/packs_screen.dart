import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:operation_hermes/ui/firebase_image.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/category.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'levels_screen.dart';

class PacksScreen extends StatefulWidget {
  final Category category;
  const PacksScreen({super.key, required this.category});
  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> {
  late Future<List<Pack>> _packsFuture;

  @override
  void initState() {
    super.initState();
    final firebaseService =
        Provider.of<FirebaseService>(context, listen: false);
    _packsFuture = firebaseService.getPacks(widget.category.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.name)),
      body: FutureBuilder<List<Pack>>(
        future: _packsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          // While waiting for data, show shimmer placeholders.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final packs = snapshot.data;
          if (packs == null || packs.isEmpty) {
            return const Center(
                child: Text('No packs found in this category.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: packs.length,
            itemBuilder: (context, index) {
              final pack = packs[index];
              return _PackListItem(pack: pack);
            },
          );
        },
      ),
    );
  }
}

class _PackListItem extends StatefulWidget {
  const _PackListItem({this.pack});
  final Pack? pack;
  @override
  State<_PackListItem> createState() => _PackListItemState();
}

class _PackListItemState extends State<_PackListItem> {

  @override
  Widget build(BuildContext context) {
    // If pack is null, this widget is being used as a pure placeholder.
    final isPlaceholder = widget.pack == null;
    final colorScheme = Theme.of(context).colorScheme;
    final levelModel = context.watch<LevelModel>();

    const double itemHeight = 100.0;

    final formattedDate = isPlaceholder
        ? ''
        : DateFormat.yMMMd().format(widget.pack!.lastUpdated);
    final updateText = 'Last update $formattedDate';

    // UPDATED: Using a cleaner theme color for subtitles
    final secondaryTextStyle = TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 12);

    return Container(
      height: itemHeight,
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4.0,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Shimmer.fromColors(
              baseColor: colorScheme.onSurface.withOpacity(0.1),
              highlightColor: colorScheme.onSurface.withOpacity(0.2),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        // UPDATED: Color removed for theme compatibility
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 16.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                              height: 16,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                  // UPDATED: Color removed for theme compatibility
                                  borderRadius: BorderRadius.circular(4))),
                          const SizedBox(height: 8.0),
                          Container(
                              height: 28,
                              width:
                                  MediaQuery.of(context).size.width * 0.4,
                              decoration: BoxDecoration(
                                  // UPDATED: Color removed for theme compatibility
                                  borderRadius: BorderRadius.circular(4))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16.0),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        // UPDATED: Color removed for theme compatibility
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ), // Removed AnimatedOpacity wrapper
            InkWell(
                onTap: () async {
                  await Future.delayed(const Duration(milliseconds: 50));
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => LevelsScreen(pack: widget.pack!)),
                  );
                },
                child: Container(
                  color: colorScheme.secondaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: FirebaseImage(storagePath: widget.pack?.thumbnailUrl ?? ''),
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [ 
                            Text(widget.pack?.name ?? '',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        colorScheme.onSecondaryContainer,
                                    fontSize: 16)),
                            const SizedBox(height: 4.0),
                            Text(
                              updateText,
                              style: secondaryTextStyle,
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              widget.pack?.description ?? '',
                              style: secondaryTextStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      if (widget.pack != null)
                        _PackProgressIndicator(pack: widget.pack!)
                      else // Placeholder for progress indicator
                        const SizedBox(width: 44, height: 44),
                    ], // Removed AnimatedOpacity wrapper
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PackProgressIndicator extends StatefulWidget {
  final Pack pack;

  const _PackProgressIndicator({required this.pack});

  @override
  State<_PackProgressIndicator> createState() => _PackProgressIndicatorState();
}

class _PackProgressIndicatorState extends State<_PackProgressIndicator> {
  late Future<int> _completedLevelsFuture;

  @override
  void initState() {
    super.initState();
    final levelModel = context.read<LevelModel>();
    _completedLevelsFuture =
        levelModel.getUnlockedLevelsCountForPack(widget.pack.id);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<int>(
      future: _completedLevelsFuture,
      builder: (context, snapshot) {
        final completedLevels = snapshot.data ?? 0;
        final totalLevels = widget.pack.totalLevels;
        final double progress =
            (totalLevels > 0) ? completedLevels / totalLevels : 0.0;

        if (progress <= 0) return const SizedBox.shrink();

        return SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 3.0,
                backgroundColor: colorScheme.primary.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}