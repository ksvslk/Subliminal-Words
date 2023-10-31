import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LicensesDialog extends StatelessWidget {
  const LicensesDialog({super.key});

  Future<String> _loadTextFromFile() async {
    return await rootBundle.loadString('assets/licenses.txt');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: FutureBuilder(
        future: _loadTextFromFile(),
        builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            // Display the loaded text when available
            return SingleChildScrollView(child: Text(
              snapshot.data ?? 'No data found',
              style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall?.fontSize)
              ));
          } else {
            // Display a loading spinner while the text is loading
            return const CircularProgressIndicator();
          }
        },
      ),
      actions: <Widget>[
        TextButton(child: const Text('Close'), onPressed: () { Navigator.pop(context); }),
      ],
    ); 
  }
}
