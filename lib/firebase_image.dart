import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:operation_hermes/level/firebase_service.dart'; // Ensure this path is correct

class FirebaseImage extends StatefulWidget {
  final String storagePath;
  final BoxFit fit;
  final VoidCallback? onLoaded;

  const FirebaseImage({
    super.key,
    required this.storagePath,
    this.fit = BoxFit.cover,
    this.onLoaded,
  });

  @override
  State<FirebaseImage> createState() => _FirebaseImageState();
}

class _FirebaseImageState extends State<FirebaseImage> {
  late Future<String> _urlFuture;
  bool _isLoadNotified = false;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  void _loadUrl() {
    final service = Provider.of<FirebaseService>(context, listen: false);
    _urlFuture = service.getDownloadUrl(widget.storagePath)
      ..catchError((error) {
        _notifyOnce();
      });
  }

  @override
  void didUpdateWidget(covariant FirebaseImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storagePath != oldWidget.storagePath) {
      _isLoadNotified = false;
      setState(() {
        _loadUrl();
      });
    }
  }

  void _notifyOnce() {
    if (!_isLoadNotified) {
      _isLoadNotified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onLoaded?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.storagePath.isEmpty) {
      _notifyOnce();
      return const Center(child: Icon(Icons.image_not_supported));
    }

    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = Shimmer.fromColors(
      baseColor: colorScheme.onSurface.withOpacity(0.1),
      highlightColor: colorScheme.onSurface.withOpacity(0.2),
      child: Container(color: Colors.white),
    );

    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return placeholder;
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          _notifyOnce();
          return const Center(child: Icon(Icons.error));
        }

        final url = snapshot.data!;
        return Image.network(
          url,
          fit: widget.fit,
          // We no longer send the signal from here. This builder just
          // handles showing the placeholder vs. the final image widget.
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return placeholder;
          },
          // THIS IS THE KEY FIX:
          // The frameBuilder is called when Flutter is ready to draw the image.
          // This is the perfect time to send the "loaded" signal.
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // If the frame is ready, notify the parent.
            if (frame != null) {
              _notifyOnce();
            }
            // Return the image widget (or an empty container if not yet ready).
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            _notifyOnce();
            return const Center(child: Icon(Icons.error));
          },
        );
      },
    );
  }
}