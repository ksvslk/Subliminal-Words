import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:operation_hermes/controller/firebase_service.dart';

class FirebaseImage extends StatefulWidget {
  final String storagePath;
  final BoxFit fit;
  final Alignment alignment;
  final ValueChanged<ImageInfo>? onImageInfoLoaded;

  const FirebaseImage({
    super.key,
    required this.storagePath,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.onImageInfoLoaded,
  });

  @override
  State<FirebaseImage> createState() => _FirebaseImageState();
}

class _FirebaseImageState extends State<FirebaseImage> {
  late Future<String> _urlFuture;
  bool _isImageLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  void _loadUrl() {
    final service = Provider.of<FirebaseService>(context, listen: false);
    _urlFuture = service.getDownloadUrl(widget.storagePath)
      ..catchError((error) {
        _setImageLoaded();
        return '';
      });
  }

  @override
  void didUpdateWidget(covariant FirebaseImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storagePath != oldWidget.storagePath) {
      _isImageLoaded = false;
      setState(() {
        _loadUrl();
      });
    }
  }

  void _setImageLoaded() {
    if (!_isImageLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isImageLoaded = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.storagePath.isEmpty) {
      return Container();
    }

    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container();
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          _setImageLoaded();
          return Container();
        }

        final url = snapshot.data!;

        final imageContent = Image.network(
          url,
          fit: widget.fit,
          alignment: widget.alignment,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container();
          },
          errorBuilder: (context, error, stackTrace) {
            _setImageLoaded();
            return Container();
          },
        );

        imageContent.image.resolve(const ImageConfiguration()).addListener(
              ImageStreamListener((imageInfo, synchronousCall) {
                widget.onImageInfoLoaded?.call(imageInfo);
                _setImageLoaded();
              }, onError: (exception, stackTrace) {
                _setImageLoaded();
              }),
            );

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
