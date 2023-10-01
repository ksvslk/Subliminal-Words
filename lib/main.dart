import 'package:flutter/material.dart';

void main() => runApp(const MyApp());
final List<String> items = List.generate(20, (index) => 'Item $index');

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: 200, // Adjust the height as needed
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return Card(
                    child: Center(
                      child: Text(items[index]),
                    ),
                  );
                },
              ),
            ),
            const Center(child: Text("tere!"))
          ],
        ),
      ),
    );
  }
}
