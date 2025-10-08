import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add this import for ImageInfo
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:operation_hermes/controller/firebase_service.dart';

class FirebaseImage extends StatefulWidget {
  final String storagePath;
  final BoxFit fit;
  final Alignment alignment;
  final VoidCallback? onLoaded;
  final ValueChanged<ImageInfo>? onImageInfoLoaded; // ADD THIS CALLBACK

  const FirebaseImage({
    super.key,
    required this.storagePath,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.onLoaded,
    this.onImageInfoLoaded, // ADD THIS TO CONSTRUCTOR
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

  // ... (loadUrl and didUpdateWidget methods remain the same) ...
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
    // ... (build method logic up to Image.network remains the same) ...
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
        
        // ADD THIS: We need an Image widget to get the ImageInfo
        final imageWidget = Image.network(
          url,
          fit: widget.fit,
          alignment: widget.alignment,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return placeholder;
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null) {
              _notifyOnce();
            }
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            _notifyOnce();
            return const Center(child: Icon(Icons.error));
          },
        );

        // ADD THIS: Logic to listen for when the image is loaded to get its info
        imageWidget.image.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener((imageInfo, synchronousCall) {
            widget.onImageInfoLoaded?.call(imageInfo);
          }),
        );

        return imageWidget;
      },
    );
  }
}