import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:operation_hermes/config/sounds.dart';
import 'package:operation_hermes/ui/filled_letter_painter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:operation_hermes/controller/audio_controller.dart';
import 'package:operation_hermes/change_notifier/level_model.dart';
import 'package:operation_hermes/change_notifier/picture_model.dart';
import 'package:operation_hermes/data/svg_letter.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:provider/provider.dart';

class Puzzle extends StatelessWidget {
  const Puzzle({super.key});

  @override
  Widget build(BuildContext context) {
    final audioController = context.read<AudioController>();

    Widget buildPlaceholder() {
      return Shimmer.fromColors(
        baseColor: Theme.of(context).colorScheme.surface,
        highlightColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(
                color: Theme.of(context).colorScheme.secondary, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    }

    return Consumer<LevelModel>(builder: (context, levelModel, child) {
      return GestureDetector(
        onTap: levelModel.levelCompleted
            ? () {
                levelModel.nextLevel();
              }
            : null,
        child: levelModel.networkRequestActive
            ? AspectRatio(
                aspectRatio: 1,
                child: buildPlaceholder(),
              )
            : AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                            image: const AssetImage('assets/other/grid.png'),
                            repeat: ImageRepeat.repeat,
                            colorFilter: ColorFilter.mode(
                                Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                BlendMode.modulate)),
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withAlpha(64),
                        border: Border.all(
                            color: Theme.of(context).colorScheme.secondary,
                            width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    ChangeNotifierProvider<PictureModel>.value(
                      value: levelModel.pictureModel,
                      child: Consumer<PictureModel>(
                        builder: (context, model, child) {
                          Widget solutionWidget = const SizedBox.shrink();
                          if (model.isFactTypeLevel &&
                              model.isFactLevelComplete) {
                            final isBundled =
                                levelModel.currentLevel?.isBundled ?? false;
                            final solutionPath = model.svgPath;

                            ImageProvider? imageProvider;
                            if (solutionPath.isNotEmpty) {
                              if (isBundled) {
                                imageProvider = AssetImage(solutionPath);
                              } else {
                                imageProvider =
                                    CachedNetworkImageProvider(solutionPath);
                              }

                              imageProvider
                                  .resolve(const ImageConfiguration())
                                  .addListener(ImageStreamListener(
                                      (imageInfo, synchronousCall) {
                                model.beginSolutionAnimation();
                              }));
                            }

                            solutionWidget = Opacity(
                              opacity: model.solutionOpacity,
                              child: imageProvider != null ? Image(
                                image: imageProvider,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.error),
                              ) : const SizedBox.shrink(),
                            );
                          }

                          return RotatedBox(
                            quarterTurns: model.quarterTurn,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              transformAlignment: Alignment.center,
                              transform: Matrix4.diagonal3Values(
                                model.scale,
                                model.scale,
                                1,
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                alignment: Alignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: levelModel.currentLevel?.isBundled ==
                                            false
                                        ? (model.puzzleImageBytes != null && model.puzzleImageBytes!.isNotEmpty)
                                            ? Image.memory(
                                                model.puzzleImageBytes!,
                                                fit: BoxFit.contain,
                                                gaplessPlayback: true,
                                              )
                                            : model.picturePath.isEmpty
                                                ? const Icon(Icons.broken_image)
                                                : CachedNetworkImage(
                                                    imageUrl: model.picturePath,
                                                    placeholder: (context, url) =>
                                                        const Center(
                                                      child: SizedBox.square(
                                                        dimension: 24,
                                                        child: CircularProgressIndicator
                                                            .adaptive(),
                                                      ),
                                                    ),
                                                    errorWidget:
                                                        (context, url, error) =>
                                                            const Icon(Icons.error),
                                                  )
                                        : model.picturePath.isEmpty 
                                            ? const Icon(Icons.broken_image) 
                                            : Image.asset(
                                                model.picturePath,
                                                fit: BoxFit.contain,
                                                gaplessPlayback: true,
                                              ),
                                  ),
                                  solutionWidget,
                                  ...model.highlightLetters.map((svgLetter) {
                                    int getDurationAndSetLettersInitialized(
                                        SvgLetter svgLetter) {
                                      if (svgLetter.initialLoad) {
                                        svgLetter.initialLoad = false;
                                        return 0;
                                      } else {
                                        return 2000;
                                      }
                                    }

                                    final isDarkMode = MediaQuery.of(context)
                                            .platformBrightness ==
                                        Brightness.dark;
                                    final firstColor = isDarkMode
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .inversePrimary;
                                    final secondColor = isDarkMode
                                        ? Theme.of(context)
                                            .colorScheme
                                            .inverseSurface
                                        : Theme.of(context).colorScheme.surface;

                                    return AnimatedOpacity(
                                      duration: Duration(
                                          milliseconds:
                                              getDurationAndSetLettersInitialized(
                                                  svgLetter)),
                                      opacity: (svgLetter.show) ? 1.0 : 0.0,
                                      curve: Curves.fastOutSlowIn,
                                      onEnd: () {
                                        if (svgLetter.show &&
                                            !levelModel.levelCompleted) {
                                          model.hideLetter(svgLetter);
                                        }
                                      },
                                      child: CustomPaint(
                                        painter: FilledLetterPainter(
                                            path: svgLetter.usesTextOverlay
                                                ? null
                                                : parseSvgPathData(
                                                    svgLetter.path),
                                            text: svgLetter.usesTextOverlay
                                                ? svgLetter.text
                                                : null,
                                            center: svgLetter.usesTextOverlay
                                                ? Offset(
                                                    svgLetter.x ?? 512,
                                                    svgLetter.y ?? 512,
                                                  )
                                                : null,
                                            fontSize: svgLetter.usesTextOverlay
                                                ? (svgLetter.fontSize ?? 132)
                                                : 132,
                                            rotationDegrees:
                                                svgLetter.rotationDegrees,
                                            scaleX: svgLetter.scaleX,
                                            scaleY: svgLetter.scaleY,
                                            skewXDegrees:
                                                svgLetter.skewXDegrees,
                                            skewYDegrees:
                                                svgLetter.skewYDegrees,
                                            opacity: svgLetter.opacity,
                                            fontWeightValue:
                                                svgLetter.fontWeightValue,
                                            firstColor: firstColor,
                                            secondColor: secondColor),
                                        child: const AspectRatio(
                                          aspectRatio: 1 / 1,
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            strokeAlign: BorderSide.strokeAlignCenter,
                            color: Theme.of(context).colorScheme.secondary,
                            width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    levelModel.manipulationEnabled
                        ? ChangeNotifierProvider<PictureModel>.value(
                            value: levelModel.pictureModel,
                            child: Consumer<PictureModel>(
                                builder: (context, pictureModel, child) {
                              return Positioned(
                                bottom: 4,
                                right: 4,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton.filled(
                                      visualDensity: VisualDensity.comfortable,
                                      style: IconButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surface
                                              .withAlpha(64)),
                                      icon: Icon(
                                        Icons.zoom_out,
                                        color: pictureModel.scale <=
                                                pictureModel.minZoom
                                            ? null
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                      ),
                                      onPressed: pictureModel.scale <=
                                              pictureModel.minZoom
                                          ? null
                                          : () {
                                              pictureModel.setScaleDown();
                                              audioController
                                                  .playSfx(SfxType.zoomOut);
                                            },
                                    ),
                                    IconButton.filled(
                                      visualDensity: VisualDensity.comfortable,
                                      style: IconButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surface
                                              .withAlpha(64)),
                                      icon: Icon(
                                        Icons.zoom_in,
                                        color: pictureModel.scale >=
                                                pictureModel.maxZoom
                                            ? null
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                      ),
                                      onPressed: pictureModel.scale >=
                                              pictureModel.maxZoom
                                          ? null
                                          : () {
                                              pictureModel.setScaleUp();
                                              audioController
                                                  .playSfx(SfxType.zoomIn);
                                            },
                                    ),
                                    IconButton.filled(
                                      visualDensity: VisualDensity.comfortable,
                                      style: IconButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surface
                                              .withAlpha(64)),
                                      icon: Icon(
                                        Icons.rotate_90_degrees_cw,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                      onPressed: () {
                                        audioController.playSfx(SfxType.rotate);
                                        pictureModel.setNextQuarterTurn();
                                      },
                                    )
                                  ],
                                ),
                              );
                            }),
                          )
                        : const SizedBox.shrink(),
                  ],
                ),
              ),
      );
    });
  }
}
