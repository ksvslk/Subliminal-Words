import 'package:flutter/material.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/settings/settings_controller.dart';
import 'package:provider/provider.dart';

enum MenuItem { achievements, theme, feedback, sound, music, about }

enum AboutSubMenuItem {
  follow,
  licenses,
  privacy,
}

enum ThemeSubMenuItem {
  red,
  yellow,
  green,
  blue,
  purple,
}

class SettingsMenu extends StatefulWidget {
  const SettingsMenu({Key? key}) : super(key: key);

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsController>();

    return MenuAnchor(
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
        return IconButton(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Show menu',
        );
      },
      menuChildren: MenuItem.values.map((item) {
        switch (item) {
          case MenuItem.achievements:
            return MenuItemButton(
                onPressed: () {},
                leadingIcon: const Icon(Icons.leaderboard_outlined),
                child: Text(item.name));
          case MenuItem.theme:
            return ValueListenableBuilder(
                valueListenable: settings.seedColor,
                builder: (context, value, child) {
                  return SubmenuButton(
                    leadingIcon: const Icon(Icons.color_lens_outlined),
                    menuChildren: ThemeSubMenuItem.values.map((item) {
                      switch (item) {
                        case ThemeSubMenuItem.red:
                          const color = Color.fromARGB(255, 255, 0, 0);
                          return MenuItemButton(
                              onPressed: () {
                                settings.changeSeedColor(color);
                              },
                              child: settings.seedColor.value == color.value
                                  ?  CircleAvatar(
                                      backgroundColor: color,
                                      child: Icon(Icons.check, color: color.blendWith(Colors.black, 0.5)))
                                  : const CircleAvatar(backgroundColor: color));
                        case ThemeSubMenuItem.yellow:
                          const color = Color.fromARGB(255, 255, 255, 0);
                          return MenuItemButton(
                              onPressed: () {
                                settings.changeSeedColor(color);
                              },
                              child: settings.seedColor.value == color.value
                                  ?  CircleAvatar(
                                      backgroundColor: color,
                                     child: Icon(Icons.check, color: color.blendWith(Colors.black, 0.5)))
                                  : const CircleAvatar(backgroundColor: color));
                        case ThemeSubMenuItem.green:
                          const color = Color.fromARGB(255, 0, 255, 0);
                          return MenuItemButton(
                              onPressed: () {
                                settings.changeSeedColor(color);
                              },
                              child: settings.seedColor.value == color.value
                                  ? CircleAvatar(
                                      backgroundColor: color,
                                      child: Icon(Icons.check, color: color.blendWith(Colors.black, 0.5)))
                                  : const CircleAvatar(backgroundColor: color));
                        case ThemeSubMenuItem.blue:
                          const color = Color.fromARGB(255, 0, 0, 255);
                          return MenuItemButton(
                              onPressed: () {
                                settings.changeSeedColor(color);
                              },
                              child: settings.seedColor.value == color.value
                                  ?  CircleAvatar(
                                      backgroundColor: color,
                                   child: Icon(Icons.check, color: color.blendWith(Colors.black, 0.5)))
                                  : const CircleAvatar(backgroundColor: color));
                        case ThemeSubMenuItem.purple:
                          const color = Color.fromARGB(255, 255, 0, 255);
                          return MenuItemButton(
                              onPressed: () {
                                settings.changeSeedColor(color);
                              },
                              child: settings.seedColor.value == color.value
                                  ?  CircleAvatar(
                                      backgroundColor: color,
                                    child: Icon(Icons.check, color: color.blendWith(Colors.black, 0.5)))
                                  : const CircleAvatar(backgroundColor: color));
                      }
                    }).toList(),
                    child: Text(item.name),
                  );
                });
          case MenuItem.feedback:
            return MenuItemButton(
                onPressed: () {},
                leadingIcon: const Icon(Icons.keyboard_outlined),
                child: Text(item.name));
          case MenuItem.sound:
            return ValueListenableBuilder(
                valueListenable: settings.soundsOn,
                builder: (context, value, child) {
                  return MenuItemButton(
                      onPressed: () {},
                      closeOnActivate: false,
                      leadingIcon: const Icon(Icons.music_note_outlined),
                      child: Switch.adaptive(
                          onChanged: (newValue) {
                            settings.toggleSoundsOn();
                          },
                          value: value));
                });
          case MenuItem.music:
            return ValueListenableBuilder(
                valueListenable: settings.musicOn,
                builder: (context, value, child) {
                  return MenuItemButton(
                      onPressed: () {},
                      closeOnActivate: false,
                      leadingIcon: const Icon(Icons.speaker_outlined),
                      child: Switch.adaptive(
                          onChanged: (newValue) {
                            settings.toggleMusicOn();
                          },
                          value: value));
                });
          case MenuItem.about:
            return SubmenuButton(
              leadingIcon: const Icon(Icons.info_outline),
              menuChildren: AboutSubMenuItem.values.map((item) {
                return MenuItemButton(onPressed: () {}, child: Text(item.name));
              }).toList(),
              child: Text(item.name),
            );
        }
      }).toList(),
    );
  }
}
