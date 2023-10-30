import 'package:flutter/material.dart';

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

Widget getMenuItemButton(MenuItem menuItem) {
  switch (menuItem) {
    case MenuItem.achievements:
      return MenuItemButton(
          onPressed: () {},
          leadingIcon: const Icon(Icons.leaderboard_outlined),
          child: Text(menuItem.name));
    case MenuItem.theme:
  return SubmenuButton(
        leadingIcon: const Icon(Icons.color_lens_outlined),
        menuChildren: ThemeSubMenuItem.values.map((item) {
          return getThemeSubMenuItem(item);
        }).toList(),
        child: Text(menuItem.name),
      );
    case MenuItem.feedback:
      return MenuItemButton(
          onPressed: () {},
          leadingIcon: const Icon(Icons.keyboard_outlined),
          child: Text(menuItem.name));
    case MenuItem.sound:
      return MenuItemButton(
          onPressed: () {},
          leadingIcon: const Icon(Icons.music_note_outlined),
          child: Text(menuItem.name));
    case MenuItem.music:
      return MenuItemButton(
          onPressed: () {},
          leadingIcon: const Icon(Icons.speaker_outlined),
          child: Text(menuItem.name));
    case MenuItem.about:
      return SubmenuButton(
        leadingIcon: const Icon(Icons.info_outline),
        menuChildren: AboutSubMenuItem.values.map((item) {
          return getAboutSubMenuItem(item);
        }).toList(),
        child: Text(menuItem.name),
      );
  }
}

MenuItemButton getAboutSubMenuItem(AboutSubMenuItem menuItem) {
  return MenuItemButton(onPressed: () {}, child: Text(menuItem.name));
}

MenuItemButton getThemeSubMenuItem(ThemeSubMenuItem menuItem) {
  switch (menuItem) {
    case ThemeSubMenuItem.red:
      return MenuItemButton(
          onPressed: () {},
          child: const CircleAvatar(backgroundColor: Colors.red));
    case ThemeSubMenuItem.yellow:
      return MenuItemButton(
          onPressed: () {},
          child: const CircleAvatar(backgroundColor: Colors.yellow));
    case ThemeSubMenuItem.green:
      return MenuItemButton(
          onPressed: () {},
          child: const CircleAvatar(backgroundColor: Colors.green));
    case ThemeSubMenuItem.blue:
      return MenuItemButton(
          onPressed: () {},
          child: const CircleAvatar(backgroundColor: Colors.blue));
    case ThemeSubMenuItem.purple:
      return MenuItemButton(
          onPressed: () {},
          child: const CircleAvatar(backgroundColor: Colors.purple));
  }
}

class SettingsMenu extends StatefulWidget {
  const SettingsMenu({Key? key}) : super(key: key);

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  @override
  Widget build(BuildContext context) {
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
        return getMenuItemButton(item);
      }).toList(),
    );
  }
}
