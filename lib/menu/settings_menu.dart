import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/game/info_competition_dialog.dart';
import 'package:operation_hermes/game/letter_box.dart';
import 'package:operation_hermes/games_services/games_services.dart';
import 'package:operation_hermes/menu/credits_dialog.dart';
import 'package:operation_hermes/menu/licenses_dialog.dart';
import 'package:operation_hermes/settings/settings_controller.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

enum MenuItem { achievements, competition, theme, faces, sound, music, about }

enum AboutSubMenuItem {
  follow,
  licenses,
  credits,
  privacy,
}

enum ThemeSubMenuItem { red, yellow, green, blue, purple }

Uri _getFeedbackUri() {
  return Platform.isAndroid
      ? Uri.parse(
          'https://play.google.com/store/apps/details?id=com.indest.subliminalfaces')
      : Uri.parse('https://apps.apple.com/app/subliminal-faces/id6476108606');
}

final Uri _followUri = Uri.parse('https://twitter.com/IndestGames');
final Uri _privacyUri = Uri.parse('https://indest.ee/privacy-policy/');

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
      child: settings.seedColor.value == color.value
          ? CircleAvatar(
              backgroundColor: color,
              child:
                  Icon(Icons.check, color: color.blendWith(Colors.black, 0.5)))
          : CircleAvatar(backgroundColor: color));
}

class SettingsMenu extends StatefulWidget {
  const SettingsMenu({Key? key}) : super(key: key);

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  static final _log = Logger('SettingsMenu');

  void _showPromoCode(String promoCode) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Stack(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.only(
                  top: 66 + 16,
                  bottom: 16,
                  left: 16,
                  right: 16,
                ),
                margin: const EdgeInsets.only(top: 66),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10.0,
                      offset: Offset(0.0, 10.0),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      "Congratulations!",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize:
                            Theme.of(context).textTheme.titleLarge?.fontSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Text(
                      "You've won a promo code!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize:
                            Theme.of(context).textTheme.bodyLarge?.fontSize,
                      ),
                    ),
                    const SizedBox(height: 24.0),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        promoCode,
                        style: TextStyle(
                          fontSize:
                              Theme.of(context).textTheme.bodySmall?.fontSize,
                          fontWeight: FontWeight.w700,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                child: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  radius: 66,
                  child: Icon(
                    Icons.emoji_events,
                    size: 60,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext mainContext) {
    final settings = mainContext.read<SettingsController>();
    final gamesServices = mainContext.read<GamesServicesController>();

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
                onPressed: () {
                  gamesServices.showAchievements();
                },
                leadingIcon: const Icon(Icons.leaderboard_outlined),
                child: Text(item.name));
          case MenuItem.competition:
            return MenuItemButton(
              onPressed: () {
                showInfoCompetitionDialog(mainContext);
              },
              leadingIcon: const Icon(Icons.star_outline_outlined),
              child: Text(item.name),
            );
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
          case MenuItem.faces:
            return MenuItemButton(
                onPressed: () {
                  final feedbackUri = _getFeedbackUri();
                  _launchUrl(feedbackUri);
                },
                leadingIcon: const Icon(Icons.games_outlined),
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
                }
              }).toList(),
              child: Text(item.name),
            );
        }
      }).toList(),
    );
  }
}
