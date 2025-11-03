import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/ui/firebase_image.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/category.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:operation_hermes/data/sw_level.dart'; // Import SWLevel
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'levels_screen.dart';

/// Displays a list of packs for a given category.
///
/// This screen reads a Stream<List<Pack>> from a Provider and
/// uses a StreamBuilder to display the data. This avoids the "loading flash".
class PacksScreen extends StatelessWidget {
  final Category category;
  const PacksScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final service = context.read<FirebaseService>();
    final packsStream = service.getPacksStream(category.id);

    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      // 2. Use a StreamBuilder
      body: StreamBuilder<List<Pack>>(
        stream: packsStream,
        builder: (context, snapshot) {
          
          // 3. This check correctly handles the cached stream.
          // It will only show 'waiting' if the cache is empty.
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final packs = snapshot.data;
          if (packs == null || packs.isEmpty) {
            return const Center(
                child: Text('No packs found in this category.'));
          }
          
          // 4. We have data! Build the list.
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

/// A single item in the pack list.
class _PackListItem extends StatefulWidget {
  const _PackListItem({this.pack});
  final Pack? pack;
  @override
  State<_PackListItem> createState() => _PackListItemState();
}

class _PackListItemState extends State<_PackListItem> {
  @override
  Widget build(BuildContext context) {
    final isPlaceholder = widget.pack == null;
    final colorScheme = Theme.of(context).colorScheme;

    const double itemHeight = 100.0;

    final formattedDate = isPlaceholder
        ? ''
        : DateFormat.yMMMd().format(widget.pack!.lastUpdated);
    final updateText = 'Last update $formattedDate';

    final secondaryTextStyle =
        TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12);

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
            // Shimmer placeholder
            Shimmer.fromColors(
              baseColor: colorScheme.onSurface.withOpacity(0.1),
              highlightColor: colorScheme.onSurface.withOpacity(0.2),
              enabled: isPlaceholder, // Only shimmer if it's a placeholder
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
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
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(4))),
                          const SizedBox(height: 8.0),
                          Container(
                              height: 28,
                              width: MediaQuery.of(context).size.width * 0.4,
                              decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(4))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16.0),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Actual content
            InkWell(
              onTap: () {
                // --- THIS IS THE NAVIGATION LOGIC FOR LEVELS ---
                if (!context.mounted || widget.pack == null) return;

                final service = context.read<FirebaseService>();

                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          // 💡 Use Provider<Stream<...>> for levels too
                          Provider<Stream<List<SWLevel>>>(
                            create: (ctx) =>
                                service.getLevelsStream(widget.pack!.id),
                            // No initialData
                            child: LevelsScreen(pack: widget.pack!),
                          )),
                );
                // --- END OF NAVIGATION LOGIC ---
              },
              child: Container(
                color: isPlaceholder
                    ? Colors.transparent
                    : colorScheme.secondaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: FirebaseImage(
                            storagePath: widget.pack?.thumbnailUrl ?? ''),
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
                                  color: colorScheme.onSecondaryContainer,
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
                    else
                      const SizedBox(width: 44, height: 44),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A widget that shows the user's progress for a specific pack.
class _PackProgressIndicator extends StatefulWidget {
  final Pack pack;
  const _PackProgressIndicator({required this.pack});

  @override
  State<_PackProgressIndicator> createState() => _PackProgressIndicatorState();
}

class _PackProgressIndicatorState extends State<_PackProgressIndicator> {
  late Future<int> _completedLevelsFuture;

  static final _log = Logger('_PackProgressIndicatorState');
  @override
  void initState() {
    super.initState();
    _fetchCompletedLevels();
  }

  void _fetchCompletedLevels() {
    final levelModel = context.read<LevelModel>();
    _completedLevelsFuture =
        levelModel.getUnlockedLevelsCountForPack(widget.pack.id);
  }

  // Refetch if the widget is rebuilt with a different pack
  @override
  void didUpdateWidget(covariant _PackProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pack.id != widget.pack.id) {
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
        final totalLevels = widget.pack.totalLevels;
        final double progress =
            (totalLevels > 0) ? completedLevels / totalLevels : 0.0;

        _log.info('Pack "${widget.pack.name}": '
            'calculating progress with completedLevels=$completedLevels, totalLevels=$totalLevels');

        if (totalLevels <= 0 ||
            snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(width: 44, height: 44);
        }

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