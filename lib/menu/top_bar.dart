import 'dart:io';

import 'dart:typed_data'; // Import for Uint8List

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/controller/money_controller.dart';
import 'package:operation_hermes/menu/settings_menu.dart';
import 'package:operation_hermes/ui/ad_button.dart';
import 'package:operation_hermes/ui/screen/categories_screen.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:image/image.dart' as img; // Import with a prefix

Future<void> _goToStorePage() async {
  var url = Platform.isAndroid
      ? Uri.parse(
          'https://play.google.com/store/apps/details?id=com.indest.subliminalfaces')
      : Uri.parse('https://apps.apple.com/app/subliminal-faces/id6476108606');
  if (!await launchUrl(url)) {
    throw Exception('Could not launch $url');
  }
}

Future<String> addWatermark(String originalPath) async {
  // 1. Load the original image file
  final originalFile = File(originalPath);
  final originalImage = img.decodeImage(await originalFile.readAsBytes());

  if (originalImage == null) {
    throw Exception('Could not decode original image');
  }

  // 2. Load the watermark image from assets
  final byteData = await rootBundle.load('assets/other/watermark.png');
  final watermarkBytes = byteData.buffer.asUint8List();
  final watermarkImage = img.decodeImage(watermarkBytes);

  if (watermarkImage == null) {
    throw Exception('Could not decode watermark image');
  }

  // 3. Define padding
  final padding = 16; // Your desired padding

  // 4. Calculate position for bottom-right corner
  final x = originalImage.width - watermarkImage.width - padding;
  final y = originalImage.height - watermarkImage.height - padding;

  // 5. Draw the watermark onto the original image
  img.compositeImage(
    originalImage,
    watermarkImage,
    dstX: x,
    dstY: y,
  );

  // 6. Save the modified image to a temporary file
  final tempDir = await getTemporaryDirectory();
  final newPath = '${tempDir.path}/watermarked_share.png';
  final newFile = File(newPath);

  // Encode as PNG or JPG. PNG is lossless but larger.
  await newFile.writeAsBytes(img.encodePng(originalImage));

  return newPath;
}

// This function now accepts bytes directly
Future<ShareResult?> shareAndAskHelp(
    Uint8List? imageBytes, // Changed from imagePath
    RenderBox? box,
    {String watermarkAssetPath =
        'assets/other/watermark.png'} // Made this a parameter
    ) async {
  try {
    // 1. Check if bytes are valid
    if (imageBytes == null || imageBytes.isEmpty) {
      throw Exception('Image bytes are null or empty. Cannot share.');
    }

    // 2. Decode the original image from the provided bytes
    final img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      throw Exception("Could not decode original image");
    }

    // 3. Load YOUR watermark image from assets
    final watermarkBytesData = await rootBundle.load(watermarkAssetPath);
    final watermarkBytes = watermarkBytesData.buffer.asUint8List();
    final img.Image? watermarkImage = img.decodeImage(watermarkBytes);

    if (watermarkImage == null) {
      throw Exception("Could not decode watermark image");
    }

    // 4. Define padding and calculate position (bottom-right)
    final int padding = 16;
    final x = originalImage.width - watermarkImage.width - padding;
    final y = originalImage.height - watermarkImage.height - padding;

    // 5. Draw the watermark onto the original image
    img.compositeImage(
      originalImage,
      watermarkImage,
      dstX: x,
      dstY: y,
    );

    // 6. Re-encode the image to JPG bytes
    final List<int> newBytes = img.encodeJpg(originalImage, quality: 90);

    // 7. Write the NEW bytes to a temporary file
    final tempDir = await getTemporaryDirectory();
    final file = await File('${tempDir.path}/SW_watermarked.jpg').create();
    file.writeAsBytesSync(newBytes); // Use the new watermarked bytes

    // 8. Share the new file
    final result = await Share.shareXFiles([XFile(file.path)],
        text: 'Can you see it?',
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : Rect.fromPoints(Offset.zero, Offset.zero));

    // 9. Clean up the temp file after sharing
    try {
      await file.delete();
    } catch (e) {
      print('Failed to delete temp file: $e');
    }

    return result;
  } catch (e) {
    print('Error during share with watermark: $e');
    return null;
  }
}

class TopBar extends StatefulWidget {
  const TopBar({super.key});

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    final levelSelectGlowColor = Theme.of(context).colorScheme.secondary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        const Flexible(flex: 1, child: SettingsMenu()),
        Flexible(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: levelSelectGlowColor.withAlpha(50),
                  blurRadius: 5.0,
                  spreadRadius: 1.0,
                ),
              ],
            ),
            child: IconButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => CategoriesScreen(),
                ));
              },
              icon: const Icon(Icons.apps_outlined),
            ),
          ),
        ),
        Flexible(
            flex: 1,
            child: LayoutBuilder(
              builder: (currentContext, constraints) {
                // --- Here's the logic swap ---
                if (_isSharing) {
                  // 1. Show loader while sharing
                  return const Padding(
                    padding: EdgeInsets.all(
                        12.0), // Keeps alignment similar to IconButton
                    child: SizedBox(
                      width: 24, // Default icon size
                      height: 24, // Default icon size
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  );
                }

                // 2. Show icon button normally
                return IconButton(
                  onPressed: () {
                    final model = context.read<LevelModel>();

                    // Check if the bytes are loaded before attempting to share
                    if (model.pictureModel.puzzleImageBytes == null) {
                      model.showMessageFromMascot(
                          "Image is not ready to share yet. Please wait a moment.");
                      return; // Exit if bytes aren't loaded
                    }

                    final box = currentContext.findRenderObject() as RenderBox?;

                    // Set state to true BEFORE starting the async work
                    setState(() {
                      _isSharing = true;
                    });

                    // Pass the pre-loaded bytes, not the path
                    shareAndAskHelp(model.pictureModel.puzzleImageBytes, box)
                        .then((value) {
                      if (value?.status == ShareResultStatus.success) {
                        model.showMessageFromMascot(
                            "Thank you for spreading the 'word'.");
                      }
                    }).whenComplete(() {
                      // Use whenComplete to ALWAYS reset state,
                      // even if sharing fails or is cancelled.
                      if (mounted) {
                        // Check if widget is still in the tree
                        setState(() {
                          _isSharing = false;
                        });
                      }
                    });
                  },
                  icon: Platform.isAndroid
                      ? const Icon(Icons.share_outlined)
                      : const Icon(Icons.ios_share_outlined),
                );
                // --- End of logic swap ---
              },
            )),
        Consumer<MoneyController>(builder: (context, iapController, _) {
          return Expanded(
            flex: iapController.hasAllAccess() == true ? 1 : 2,
            child: iapController.hasAllAccess() == true
                ? FilledButton.tonalIcon(
                  label: Text('Pro'),
                    onPressed: () {}, icon: Icon(Icons.verified))
                : FilledButton.icon(
                    onPressed: () {
                      RevenueCatUI.presentPaywall(displayCloseButton: true);
                    },
                    icon: Icon(Icons.sunny),
                    label: Text('Get Pro!'),
                    iconAlignment: IconAlignment.start,
                  ),
          );
        }),
      ],
    );
  }
}
