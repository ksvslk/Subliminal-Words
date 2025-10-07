import 'package:flutter/material.dart';
import 'package:operation_hermes/level/firebase_service.dart';
import 'package:provider/provider.dart';

class FirebaseImage extends StatefulWidget {
  final String storagePath;
  final BoxFit fit;

  const FirebaseImage({
    super.key,
    required this.storagePath,
    this.fit = BoxFit.cover,
  });

  @override
  State<FirebaseImage> createState() => _FirebaseImageState();
}

class _FirebaseImageState extends State<FirebaseImage> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    final service = Provider.of<FirebaseService>(context, listen: false);
    _urlFuture = service.getDownloadUrl(widget.storagePath);
  }

  @override
  void didUpdateWidget(covariant FirebaseImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storagePath != oldWidget.storagePath) {
      final service = Provider.of<FirebaseService>(context, listen: false);
      _urlFuture = service.getDownloadUrl(widget.storagePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.storagePath.isEmpty) {
      return const Center(child: Icon(Icons.image_not_supported));
    }

    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.0)));
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Icon(Icons.error));
        }

        final url = snapshot.data!;
        return Image.network(
          url,
          fit: widget.fit,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: child,
            );
          },
        );
      },
    );
  }
}

