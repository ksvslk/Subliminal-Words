import 'package:flutter/material.dart';

class CreditsDialog extends StatelessWidget {
  const CreditsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Music and sounds"),
      ),
      body: const Dialog.fullscreen(
          child: Column(
        children: [
          ListTile(
             title: Text("Kenney"),
            subtitle: Text("Sound -                                                                                                                                                                             https://www.patreon.com/kenney"),
          ),
          ListTile(
            title: Text("symphony"),
            subtitle: Text("Music - https://www.patreon.com/bitverse"),
          ),
          ListTile(
             title: Text("LokiF"),
            subtitle: Text("Sound - https://opengameart.org/users/lokif"),
          ),
          ListTile(
             title: Text("ccr_fs"),
            subtitle: Text("Sound - https://freesound.org/people/ccr_fs"),
          ),
        ],
      )),
    );
  }
}
