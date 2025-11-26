import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/controller/money_controller.dart';
import 'package:operation_hermes/menu/settings_menu.dart';
import 'package:operation_hermes/ui/screen/categories_screen.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:image/image.dart' as img;


Future<String> addWatermark(String originalPath) async {
  final originalFile = File(originalPath);
  final originalImage = img.decodeImage(await originalFile.readAsBytes());

  if (originalImage == null) {
    throw Exception('Could not decode original image');
  }
  final byteData = await rootBundle.load('assets/other/watermark.png');
  final watermarkBytes = byteData.buffer.asUint8List();
  final watermarkImage = img.decodeImage(watermarkBytes);

  if (watermarkImage == null) {
    throw Exception('Could not decode watermark image');
  }
  final padding = 16;
  final x = originalImage.width - watermarkImage.width - padding;
  final y = originalImage.height - watermarkImage.height - padding;

  img.compositeImage(
    originalImage,
    watermarkImage,
    dstX: x,
    dstY: y,
  );

  final tempDir = await getTemporaryDirectory();
  final newPath = '${tempDir.path}/watermarked_share.png';
  final newFile = File(newPath);
  await newFile.writeAsBytes(img.encodePng(originalImage));
  return newPath;
}

Future<ShareResult?> shareAndAskHelp(
    Uint8List? imageBytes,
    RenderBox? box,
    {String watermarkAssetPath =
        'assets/other/watermark.png'}
    ) async {
  try {
    if (imageBytes == null || imageBytes.isEmpty) {
      throw Exception('Image bytes are null or empty. Cannot share.');
    }

    final img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      throw Exception("Could not decode original image");
    }

    final watermarkBytesData = await rootBundle.load(watermarkAssetPath);
    final watermarkBytes = watermarkBytesData.buffer.asUint8List();
    final img.Image? watermarkImage = img.decodeImage(watermarkBytes);

    if (watermarkImage == null) {
      throw Exception("Could not decode watermark image");
    }

    final int padding = 16;
    final x = originalImage.width - watermarkImage.width - padding;
    final y = originalImage.height - watermarkImage.height - padding;

    img.compositeImage(
      originalImage,
      watermarkImage,
      dstX: x,
      dstY: y,
    );

    final List<int> newBytes = img.encodeJpg(originalImage, quality: 90);

    final store = Platform.isAndroid
      ? 'GooglePlay'
      : 'AppStore';

    final tempDir = await getTemporaryDirectory();
    final file = await File('${tempDir.path}/Subliminal_Words_$store.jpg').create();
    file.writeAsBytesSync(newBytes);

    final params = ShareParams(
      files:[XFile(file.path)],
      text: 'Can you see it?'
    );
    final result = await SharePlus.instance.share(params);

    try {
      await file.delete();
    } catch (e) {
      debugPrint('Failed to delete temp file: $e');
    }
    return result;
  } catch (e) {
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        const Flexible(flex: 2, child: SettingsMenu()),
        Flexible(
            flex: 2,
            child: LayoutBuilder(
              builder: (currentContext, constraints) {
                if (_isSharing) {
                  return const Padding(
                    padding: EdgeInsets.all(
                        12.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  );
                }

                return IconButton(
                  onPressed: () {
                    final model = context.read<LevelModel>();

                    if (model.pictureModel.puzzleImageBytes == null) {
                      model.showMessageFromMascot(
                          "Image is not ready to share yet. Please wait a moment.");
                      return;
                    }

                    final box = currentContext.findRenderObject() as RenderBox?;

                    setState(() {
                      _isSharing = true;
                    });

                    shareAndAskHelp(model.pictureModel.puzzleImageBytes, box)
                        .then((value) {
                      if (value?.status == ShareResultStatus.success) {
                        model.showMessageFromMascot(
                            "Thank you for spreading the 'word'.");
                      }
                    }).whenComplete(() {
                      if (mounted) {
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
              },
            )),
        Flexible(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context)
                      .colorScheme
                      .tertiaryContainer
                      .withAlpha(200),
                  blurRadius: 10.0,
                  spreadRadius: 2.0,
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
        Consumer<MoneyController>(builder: (context, iapController, _) {
          return Expanded(
            flex: iapController.hasAllAccess() == true ? 2 : 3,
            child: iapController.hasAllAccess() == true
            ? OutlinedButton.icon(
                    onPressed: () {
                      RevenueCatUI.presentPaywall(displayCloseButton: true);
                    },
                    icon: Icon(Icons.sunny),
                    label: AutoSizeText(
                      'Pro',
                      stepGranularity: 1,
                      minFontSize: 6.0,
                      wrapWords: false,
                    ),
                    iconAlignment: IconAlignment.start,
                  )
                : IconButton.filled(
                    onPressed: () {
                      RevenueCatUI.presentPaywall(displayCloseButton: true);
                    },
                    icon: Icon(Icons.monetization_on_sharp),
                  )
                
          );
        }),
        Consumer<LevelModel>(builder: (context, levelModel, _) {
          return Flexible(
            flex: 1,
            child: Center(
              child: Tooltip(
                message: levelModel.currentLevel?.packNameSanitized ??
                    'Current Level',
                child: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainer,
                  radius: 15,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: AutoSizeText(
                      levelModel.currentLevel?.nr.toString() ?? "",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      minFontSize: 6.0,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
