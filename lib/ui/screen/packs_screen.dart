import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:operation_hermes/ui/firebase_image.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/category.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:operation_hermes/data/sw_level.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'levels_screen.dart';

class PacksScreen extends StatelessWidget {
  final Category category;
  const PacksScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final service = context.read<FirebaseService>();
    final packsStream = service.getPacksStream(category.id);

    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: StreamBuilder<List<Pack>>(
        stream: packsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
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
            Shimmer.fromColors(
              baseColor: colorScheme.onSurface.withAlpha(26),
              highlightColor: colorScheme.onSurface.withAlpha(51),
              enabled: isPlaceholder,
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
            InkWell(
              onTap: () {
                if (!context.mounted || widget.pack == null) return;
                final service = context.read<FirebaseService>();

                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => Provider<Stream<List<SWLevel>>>(
                            create: (ctx) =>
                                service.getLevelsStream(widget.pack!.id),
                            child: LevelsScreen(pack: widget.pack!),
                          )),
                );
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
    _fetchCompletedLevels();
  }

  void _fetchCompletedLevels() {
    final levelModel = context.read<LevelModel>();
    _completedLevelsFuture =
        levelModel.getUnlockedLevelsCountForPack(widget.pack.id);
  }

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
        final totalLevels = widget.pack.totalLevels;
        final double progress =
            (totalLevels > 0) ? completedLevels / totalLevels : 0.0;
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
                backgroundColor: colorScheme.primary.withAlpha(51),
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withAlpha(179),
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
