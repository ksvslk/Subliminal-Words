import 'package:flutter/material.dart';

class CreditsDialog extends StatelessWidget {
  const CreditsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Credits"),
      ),
      body: const Dialog.fullscreen(
          child: Column(
        children: [
          ListTile(
            title: Text("Kenney"),
            subtitle: Text("Sound - https://www.patreon.com/kenney"),
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
          ListTile(
            title: Text("Gaspard Tertrais"),
            subtitle: Text("Co-founder and CTO at Tomorrow Theory"),
          ),
          ListTile(
            title: Text("AP123"),
            subtitle:
                Text("https://huggingface.co/spaces/AP123/IllusionDiffusion"),
          ),
        ],
      )),
    );
  }
}
