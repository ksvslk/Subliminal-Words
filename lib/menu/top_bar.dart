import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:operation_hermes/menu/in_app_purchase_menu.dart';
import 'package:operation_hermes/menu/settings_menu.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> _goToStorePage() async {
  var url = Platform.isAndroid
      ? Uri.parse(
          'https://play.google.com/store/apps/details?id=com.indest.subliminalfaces')
      : Uri.parse('https://apps.apple.com/app/subliminal-faces/id6476108606');
  if (!await launchUrl(url)) {
    throw Exception('Could not launch $url');
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  Future<ShareResult?> shareAndAskHelp(
      String imagePathInAssets, RenderBox? box) async {
    try {
      final bytes = await rootBundle.load(imagePathInAssets);
      final list = bytes.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/SW.jpg').create();
      file.writeAsBytesSync(list);
      final result = await Share.shareXFiles([XFile(file.path)],
          text:
              'Can you see it? ${Platform.isAndroid ? C.GOOGLE_PLAY_LINK : C.APPSTORE_LINK}',
          sharePositionOrigin: box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : Rect.fromPoints(Offset.zero, Offset.zero));
      return result;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        const Flexible(flex: 1, child: SettingsMenu()),
        Flexible(
          flex: 1,
          child: IconButton(
            style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.tertiaryContainer),
            color: Theme.of(context).colorScheme.onSecondaryContainer,
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return const InAppPurchaseMenuDialog();
                },
              );
            },
            icon: const Icon(Icons.add_shopping_cart_outlined),
          ),
        ),
        Flexible(
            flex: 1,
            child: LayoutBuilder(
              builder: (currentContext, constraints) {
                return IconButton(
                  onPressed: () {
                    _goToStorePage();
                  },
                  icon: const Icon(Icons.face_3_outlined),
                );
              },
            )),
        /*
        Flexible(
          flex: 1,
          child: LayoutBuilder(builder: (currentContext, constraints) {
            return IconButton(
            onPressed: () {
              final model = context.read<LevelModel>();
              final box = currentContext.findRenderObject() as RenderBox?;
              shareAndAskHelp(model.pictureModel.picturePath, box).then((value) => {
                if (value?.status == ShareResultStatus.success)
                {
                  model.showMessageFromMascot("Thank you for spreading the 'word'.")
                }
              });
            },
            icon: Platform.isAndroid
                ? const Icon(Icons.share_outlined)
                : const Icon(Icons.ios_share_outlined),
          );
          },) 
        ),
        */
        Flexible(
          flex: 6,
          child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(10), // Adjust the radius as needed
                border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .secondary), // Border style
              ),
              padding: const EdgeInsets.all(8), // Padding inside the container
              child: GestureDetector(
                child: const Text("Hmm.."),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return const Text("tere");
                    },
                  );
                },
              )),
        ),
      ],
    );
  }
}
