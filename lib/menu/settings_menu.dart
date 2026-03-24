import 'package:flutter/material.dart';
import 'package:operation_hermes/controller/money_controller.dart';
import 'package:operation_hermes/ui/letter_box.dart';
import 'package:operation_hermes/controller/games_services.dart';
import 'package:operation_hermes/menu/credits_dialog.dart';
import 'package:operation_hermes/menu/licenses_dialog.dart';
import 'package:operation_hermes/controller/settings_controller.dart';
import 'package:operation_hermes/ui/screen/create_level_screen.dart';
import 'package:operation_hermes/ui/screen/my_levels_screen.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

enum MenuItem {
  myXlevels,
  createXlevel,
  achievements,
  theme,
  about,
  sound,
  music,
  restoreXpurchases,
  otherXgames,
}

enum AboutSubMenuItem { follow, licenses, credits, privacy, eula }

enum ThemeSubMenuItem { red, yellow, green, blue, purple }

Uri _getPortfolioUri() {
  return Platform.isAndroid
      ? Uri.parse(
          'https://play.google.com/store/apps/dev?id=7030085917427251773')
      : Uri.parse('itms-apps://itunes.apple.com/developer/indest/id1471549991');
}

final Uri _followUri = Uri.parse('https://twitter.com/IndestGames');
final Uri _privacyUri = Uri.parse('https://indest.ee/privacy-policy/');
final Uri _eulaUri = Uri.parse('https://indest.ee/eula');

Future<void> _launchUrl(Uri url) async {
  if (!await launchUrl(url)) {
    throw Exception('Could not launch $url');
  }
}

MenuItemButton getMenuButton(Color color, SettingsController settings) {
  return MenuItemButton(
      onPressed: () {
        settings.changeSeedColor(color);
      },
      child: settings.seedColor.value == color.toARGB32()
          ? CircleAvatar(
              backgroundColor: color,
              child:
                  Icon(Icons.check, color: color.blendWith(Colors.black, 0.5)))
          : CircleAvatar(backgroundColor: color));
}

class SettingsMenu extends StatefulWidget {
  const SettingsMenu({super.key});

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  @override
  Widget build(BuildContext mainContext) {
    final settings = mainContext.read<SettingsController>();
    final gamesServices = mainContext.read<GamesServicesController>();
    final moneyController = mainContext.read<MoneyController>();

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
          case MenuItem.myXlevels:
            return MenuItemButton(
                onPressed: () {
                  Navigator.of(mainContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MyLevelsScreen(),
                    ),
                  );
                },
                leadingIcon: const Icon(Icons.collections_bookmark_outlined),
                child: Text(item.name.replaceFirst('X', ' ')));
          case MenuItem.createXlevel:
            return MenuItemButton(
                onPressed: () {
                  Navigator.of(mainContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateLevelScreen(),
                    ),
                  );
                },
                leadingIcon: const Icon(Icons.draw_outlined),
                child: Text(item.name.replaceFirst('X', ' ')));
          case MenuItem.achievements:
            return MenuItemButton(
                onPressed: () {
                  gamesServices.showAchievements();
                },
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
                          return getMenuButton(color, settings);
                        case ThemeSubMenuItem.yellow:
                          const color = Color.fromARGB(255, 255, 255, 0);
                          return getMenuButton(color, settings);
                        case ThemeSubMenuItem.green:
                          const color = Color.fromARGB(255, 0, 255, 0);
                          return getMenuButton(color, settings);
                        case ThemeSubMenuItem.blue:
                          const color = Color.fromARGB(255, 0, 0, 255);
                          return getMenuButton(color, settings);
                        case ThemeSubMenuItem.purple:
                          const color = Color.fromARGB(255, 255, 0, 255);
                          return getMenuButton(color, settings);
                      }
                    }).toList(),
                    child: Text(item.name),
                  );
                });
          case MenuItem.otherXgames:
            return MenuItemButton(
                onPressed: () {
                  final feedbackUri = _getPortfolioUri();
                  _launchUrl(feedbackUri);
                },
                leadingIcon: const Icon(Icons.games_outlined),
                child: Text(item.name.replaceFirst("X", " ")));
          case MenuItem.sound:
            return ValueListenableBuilder(
                valueListenable: settings.soundsOn,
                builder: (context, value, child) {
                  return MenuItemButton(
                      onPressed: () {},
                      closeOnActivate: false,
                      leadingIcon: const Icon(Icons.music_note_outlined),
                      trailingIcon: Switch.adaptive(
                          onChanged: (newValue) {
                            settings.toggleSoundsOn();
                          },
                          value: value),
                      child: Text(item.name));
                });
          case MenuItem.music:
            return ValueListenableBuilder(
                valueListenable: settings.musicOn,
                builder: (context, value, child) {
                  return MenuItemButton(
                      onPressed: () {},
                      closeOnActivate: false,
                      leadingIcon: const Icon(Icons.speaker_outlined),
                      trailingIcon: Switch.adaptive(
                          onChanged: (newValue) {
                            settings.toggleMusicOn();
                          },
                          value: value),
                      child: Text(item.name));
                });
          case MenuItem.about:
            return SubmenuButton(
              leadingIcon: const Icon(Icons.info_outline),
              menuChildren: AboutSubMenuItem.values.map((item) {
                switch (item) {
                  case AboutSubMenuItem.follow:
                    return MenuItemButton(
                        onPressed: () {
                          _launchUrl(_followUri);
                        },
                        child: Text(item.name));

                  case AboutSubMenuItem.licenses:
                    return MenuItemButton(
                        onPressed: () {
                          showDialog(
                            context: mainContext,
                            builder: (BuildContext context) {
                              return const LicensesDialog();
                            },
                          );
                        },
                        child: Text(item.name));
                  case AboutSubMenuItem.credits:
                    return MenuItemButton(
                        onPressed: () {
                          showDialog(
                            context: mainContext,
                            builder: (BuildContext context) {
                              return const CreditsDialog();
                            },
                          );
                        },
                        child: Text(item.name));
                  case AboutSubMenuItem.privacy:
                    return MenuItemButton(
                        onPressed: () {
                          _launchUrl(_privacyUri);
                        },
                        child: Text(item.name));
                  case AboutSubMenuItem.eula:
                    return MenuItemButton(
                        onPressed: () {
                          (Platform.isIOS || Platform.isMacOS)
                              ? _launchUrl(_eulaUri)
                              : _launchUrl(Uri.parse('https://www.indest.ee'));
                        },
                        child: Text((Platform.isIOS || Platform.isMacOS)
                            ? item.name
                            : "developer"));
                }
              }).toList(),
              child: Text(item.name),
            );
          case MenuItem.restoreXpurchases:
            return MenuItemButton(
                onPressed: () {
                  moneyController.restorePurchases(context);
                },
                leadingIcon: const Icon(Icons.restore),
                child: Text(item.name.replaceFirst("X", " ")));
        }
      }).toList(),
    );
  }
}
