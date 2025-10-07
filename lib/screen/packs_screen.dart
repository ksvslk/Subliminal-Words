import 'package:flutter/material.dart';
import 'package:operation_hermes/firebase_image.dart';
import 'package:operation_hermes/level/firebase_service.dart';
import 'package:operation_hermes/model/category.dart';
import 'package:operation_hermes/model/pack.dart';
import 'package:provider/provider.dart';
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
    final firebaseService = Provider.of<FirebaseService>(context, listen: false);
    _packsFuture = firebaseService.getPacks(widget.category.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      ),
      body: FutureBuilder<List<Pack>>(
        future: _packsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No packs found in this category.'));
          }

          final packs = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: packs.length,
            itemBuilder: (context, index) {
              final pack = packs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16.0),
                elevation: 2,
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12.0),
                  leading: SizedBox(
                    width: 60,
                    height: 60,
                    child: FirebaseImage(storagePath: pack.thumbnailUrl),
                  ),
                  title: Text(pack.name,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer)),
                  subtitle: Text(pack.description,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer
                              .withOpacity(0.7))),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => LevelsScreen(pack: pack)),
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

