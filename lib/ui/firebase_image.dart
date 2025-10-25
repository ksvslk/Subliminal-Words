import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add this import for ImageInfo
import 'package:provider/provider.dart';
import 'package:operation_hermes/controller/firebase_service.dart';

class FirebaseImage extends StatefulWidget {
  final String storagePath;
  final BoxFit fit;
  final Alignment alignment;
  final ValueChanged<ImageInfo>? onImageInfoLoaded; // ADD THIS CALLBACK

  const FirebaseImage({
    super.key,
    required this.storagePath,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.onImageInfoLoaded, // ADD THIS TO CONSTRUCTOR
  });

  @override
  State<FirebaseImage> createState() => _FirebaseImageState();
}

class _FirebaseImageState extends State<FirebaseImage> {
  late Future<String> _urlFuture;
  bool _isImageLoaded = false; // Internal state for the image itself

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
        _setImageLoaded(); // Notify even on error to fade in the error icon
      });
  }

  @override
  void didUpdateWidget(covariant FirebaseImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storagePath != oldWidget.storagePath) {
      _isImageLoaded = false; // Reset loaded state for new image
      setState(() {
        _loadUrl();
      });
    }
  }

  // This method is called when the image is fully loaded or an error occurs.
  // It triggers the AnimatedOpacity to fade in the content.
  void _setImageLoaded() {
    if (!_isImageLoaded) {
      // Use addPostFrameCallback to ensure setState is called after the current build phase,
      // preventing "setState during build" errors and allowing AnimatedOpacity to animate.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isImageLoaded = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.storagePath.isEmpty) {
      return Container(); // Return an empty container if there's no path
    }

    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(); // Be transparent while URL is being fetched
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          _setImageLoaded(); // Notify to fade in the error icon
          return Container(); // Be transparent on error
        }

        final url = snapshot.data!;
        
        // ADD THIS: We need an Image widget to get the ImageInfo
        final imageContent = Image.network(
          url,
          fit: widget.fit,
          alignment: widget.alignment,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child; // Image is ready, show it.
            return Container(); // Be transparent while image data is downloading
          },
          errorBuilder: (context, error, stackTrace) {
            _setImageLoaded(); // Notify to fade in the error icon
            return Container(); // Be transparent on error, this will be wrapped by AnimatedOpacity
          },
        );

        // ADD THIS: Logic to listen for when the image is loaded to get its info
        imageContent.image.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener((imageInfo, synchronousCall) {
            widget.onImageInfoLoaded?.call(imageInfo);
            _setImageLoaded(); // Notify when image is fully resolved
          }, onError: (exception, stackTrace) {
            _setImageLoaded(); // Notify on error as well, so the error icon fades in
          }),
        );

        // Wrap the actual image content (or error icon) with AnimatedOpacity
        return AnimatedOpacity(
          opacity: _isImageLoaded ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeIn,
          child: imageContent,
        );
      },
    );
  }
}