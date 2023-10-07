import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NiceButton extends StatelessWidget {
  const NiceButton({super.key, this.callback, this.buttonText = ""});

  final VoidCallback? callback;
  final String buttonText;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        callback?.call();
        HapticFeedback.selectionClick();
      },
      child: LimitedBox(
        maxHeight: 60,
        child: Container(
            decoration: ShapeDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(
                  Radius.circular(12),
                ),
                side: BorderSide(
                  width: 1,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
            margin: const EdgeInsets.all(2.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Padding(padding: const EdgeInsets.all(8.0), child:Center(
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    child: Text(
                      buttonText,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily:
                            DefaultTextStyle.of(context).style.fontFamily,
                        color:
                            Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  ),
                );
              },
            ),
          ),
      ),
    );
  }
}
