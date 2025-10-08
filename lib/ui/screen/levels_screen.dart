import 'package:flutter/material.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/firebase_service.dart';
import 'package:operation_hermes/data/level.dart';
import 'package:operation_hermes/data/pack.dart';
import 'package:provider/provider.dart';

class LevelsScreen extends StatefulWidget {
  final Pack pack;
  const LevelsScreen({super.key, required this.pack});

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen> {
  late Future<List<Level>> _levelsFuture;

  @override
  void initState() {
    super.initState();
    final firebaseService =
        Provider.of<FirebaseService>(context, listen: false);
    _levelsFuture = firebaseService.getLevels(widget.pack.id);
  }

  @override
  Widget build(BuildContext context) {
    final levelModel = context.read<LevelModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pack.name),
      ),
      body: FutureBuilder<List<Level>>(
        future: _levelsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No levels found in this pack.'));
          }

          final levels = snapshot.data!;
          final screenWidth = MediaQuery.of(context).size.width;
          final crossAxisCount = (screenWidth / 120).floor().clamp(3, 6);

          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
            ),
            itemCount: levels.length,
            itemBuilder: (context, index) {
              final level = levels[index];
              return Card(
                elevation: 2, // Slightly increased elevation
                color: Theme.of(context).colorScheme.tertiaryContainer,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (!context.mounted) return;

                    levelModel.loadLevelFromSelection(level);
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  child: Center(
                    child: Text('${level.nr}',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onTertiaryContainer)),
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