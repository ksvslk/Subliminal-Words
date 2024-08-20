import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import the services package for Clipboard

class CopyToClipboardWidget extends StatelessWidget {
  final String textToCopy;

  CopyToClipboardWidget({required this.textToCopy});

  @override
  Widget build(BuildContext context) {

    copyToClipboard() {
      Clipboard.setData(ClipboardData(text: textToCopy));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard')),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            copyToClipboard();
          },
          child: Text(
            "earned promo code",
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.bodyMedium?.fontSize,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy),
          onPressed: () {
            copyToClipboard();
          },
        ),
      ],
    );
  }
}
