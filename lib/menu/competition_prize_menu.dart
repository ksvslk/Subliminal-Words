import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import the services package for Clipboard

class CompetitionPrizeMenu extends StatelessWidget {
  final String promoCode;

  const CompetitionPrizeMenu({super.key, required this.promoCode});

  @override
  Widget build(BuildContext context) {
    copyToClipboard() {
      Clipboard.setData(ClipboardData(text: promoCode));
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
            "promo code prize",
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
