import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/sounds.dart';
import 'package:operation_hermes/controller/settings_controller.dart';
import 'package:real_volume/real_volume.dart';

class AudioController {
  static final _log = Logger('AudioController');

  SettingsController? _settings;
  ValueNotifier<AppLifecycleState>? _lifecycleNotifier;
  final ValueNotifier<bool> isSoundMutedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isMusicMutedNotifier = ValueNotifier(false);
  StreamSubscription? _ringerModeSubscription;
  final Map<SfxType, AudioSource> _sfxs = {};
  final List<SoundHandle> _activeSfxHandles = [];
  AudioSource? _musicSource;
  SoundHandle? _musicHandle;
  AudioController();

  void attachLifecycleNotifier(
    ValueNotifier<AppLifecycleState> lifecycleNotifier,
  ) {
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);
    lifecycleNotifier.addListener(_handleAppLifecycle);
    _lifecycleNotifier = lifecycleNotifier;
  }

  void attachSettings(SettingsController settingsController) {
    if (_settings == settingsController) {
      return;
    }

    final oldSettings = _settings;
    if (oldSettings != null) {
      oldSettings.soundsOn.removeListener(_soundsOnHandler);
      oldSettings.musicOn.removeListener(_musicOnHandler);
    }
    _settings = settingsController;
    settingsController.soundsOn.addListener(_soundsOnHandler);
    settingsController.musicOn.addListener(_musicOnHandler);
    _updateMusicState();
  }

  void dispose() {
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);
    _ringerModeSubscription?.cancel();
    _settings?.soundsOn.removeListener(_soundsOnHandler);
    _settings?.musicOn.removeListener(_musicOnHandler);
    _cleanupAudio();
    if (SoLoud.instance.isInitialized) {
      SoLoud.instance.deinit();
    }
  }

  Future<void> initialize() async {
    await SoLoud.instance.init();
    await _initRingerModeListener();
    await _loadAllSfx();
    await _loadMusic();
    _updateMusicState();
  }

  Future<void> _loadAllSfx() async {
    _sfxs.clear();
    try {
      await _loadSfx(SfxType.freeLetter, 'assets/sfx/freeLetter.wav');
      await _loadSfx(SfxType.notAllowed, 'assets/sfx/notAllowed.wav');
      await _loadSfx(SfxType.pickLetter, 'assets/sfx/pickLetter.wav');
      await _loadSfx(SfxType.rewardGiven, 'assets/sfx/rewardGiven.wav');
      await _loadSfx(SfxType.rotate, 'assets/sfx/rotate.wav');
      await _loadSfx(SfxType.win, 'assets/sfx/win.wav');
      await _loadSfx(SfxType.wrong, 'assets/sfx/wrong.wav');
      await _loadSfx(SfxType.zoomIn, 'assets/sfx/zoomIn.wav');
      await _loadSfx(SfxType.zoomOut, 'assets/sfx/zoomOut.wav');
    } on Exception catch (e) {
      _log.severe("Error loading sound files", e);
    }
  }

  Future<void> _loadSfx(SfxType type, String assetPath) async {
    try {
      final source = await SoLoud.instance.loadAsset(assetPath);
      _sfxs[type] = source;
    } catch (e) {
      _log.severe('Failed to load SFX $type: $e');
    }
  }

  Future<void> _loadMusic() async {
    if (_musicSource != null) {
      SoLoud.instance.disposeSource(_musicSource!);
      _musicSource = null;
    }

    try {
      _log.info('Loading music...');
      _musicSource = await SoLoud.instance.loadAsset(
        'assets/music/cubedcanada.wav',
        mode: LoadMode.disk,
      );
    } catch (e) {
      _log.severe('Failed to load music: $e');
    }
  }

  Future<void> _initRingerModeListener() async {
    _ringerModeSubscription?.cancel();

    try {
      final initialMode = await RealVolume.getRingerMode();
      final isMuted = (initialMode == RingerMode.SILENT ||
          initialMode == RingerMode.VIBRATE);
      isSoundMutedNotifier.value = isMuted;
      isMusicMutedNotifier.value = isMuted;

      _ringerModeSubscription = RealVolume.onRingerModeChanged.listen((mode) {
        final bool isMuted =
            (mode == RingerMode.SILENT || mode == RingerMode.VIBRATE);
        isSoundMutedNotifier.value = isMuted;
        isMusicMutedNotifier.value = isMuted;
        _updateMusicState();
        if (isMuted) {
          _stopAllSfx();
        }
      });
    } catch (e) {
      _log.severe('Failed to initialize ringer mode listener: $e');
    }
  }

  void playSfx(SfxType type) async {
    _log.info('Now trying to play $type.');

    final soundsOn = _settings?.soundsOn.value ?? false;
    if (isSoundMutedNotifier.value ||
        !soundsOn ||
        !SoLoud.instance.isInitialized) {
      return;
    }

    final sound = _sfxs[type];
    if (sound != null) {
      try {
        final handle = await SoLoud.instance.play(sound, volume: 0.2);
        _activeSfxHandles.add(handle);
        sound.allInstancesFinished.first.then((_) {
          _activeSfxHandles.remove(handle);
        });
      } catch (e) {
        _log.severe('Error playing sound $type: $e');
      }
    } else {
      _log.warning('Tried to play sound $type, but it was not preloaded.');
    }
  }

  void _updateMusicState() async {
    if (!SoLoud.instance.isInitialized) return;

    final musicOn = _settings?.musicOn.value ?? false;
    final systemMuted = isMusicMutedNotifier.value;
    final shouldBePlaying = musicOn && !systemMuted;
    final bool isCurrentlyPlaying = _musicHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(_musicHandle!);

    if (shouldBePlaying && !isCurrentlyPlaying) {
      await _startMusic();
    } else if (!shouldBePlaying && isCurrentlyPlaying) {
      _stopMusic();
    }
  }

  Future<void> _startMusic() async {
    if (_musicSource == null) {
      _log.warning('Music source not loaded. Attempting to load...');
      await _loadMusic();
      if (_musicSource == null) {
        _log.severe('Failed to load music, cannot play.');
        return;
      }
    }

    _log.info('Playing music');
    _musicHandle = await SoLoud.instance.play(
      _musicSource!,
      volume: 0.1,
      looping: true,
    );
  }

  void _stopMusic() {
    if (_musicHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(_musicHandle!)) {
      _log.info('Stopping music');
      SoLoud.instance.stop(_musicHandle!);
    }
    _musicHandle = null;
  }

  void _stopAllSfx() {
    if (!SoLoud.instance.isInitialized) return;

    for (final handle in _activeSfxHandles) {
      if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
        SoLoud.instance.stop(handle);
      }
    }
    _activeSfxHandles.clear();
  }

  void _cleanupAudio() {
    if (!SoLoud.instance.isInitialized) return;
    _log.info('Cleaning up audio: Stopping all sounds...');
    _stopMusic();
    _stopAllSfx();
    _log.info('Disposing SFX sources...');
    for (final source in _sfxs.values) {
      SoLoud.instance.disposeSource(source);
    }
    _sfxs.clear();
    _log.info('Disposing music source...');
    if (_musicSource != null) {
      SoLoud.instance.disposeSource(_musicSource!);
      _musicSource = null;
    }
  }

  void _handleAppLifecycle() async {
    if (_lifecycleNotifier == null) return;
    switch (_lifecycleNotifier!.value) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (SoLoud.instance.isInitialized) {
          _log.info('App backgrounded, pausing audio.');
          if (_musicHandle != null &&
              SoLoud.instance.getIsValidVoiceHandle(_musicHandle!)) {
            SoLoud.instance.setPause(_musicHandle!, true);
          }
          for (final handle in _activeSfxHandles) {
            if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
              SoLoud.instance.setPause(handle, true);
            }
          }
        }
        break;
      case AppLifecycleState.resumed:
        if (SoLoud.instance.isInitialized) {
          _log.info('App resumed, unpausing audio.');
          if (_musicHandle != null &&
              SoLoud.instance.getIsValidVoiceHandle(_musicHandle!)) {
            SoLoud.instance.setPause(_musicHandle!, false);
          }
          for (final handle in _activeSfxHandles) {
            if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
              SoLoud.instance.setPause(handle, false);
            }
          }
        } else {
          _log.warning('Audio engine lost. Re-initializing...');
          await SoLoud.instance.init();
          await _loadAllSfx();
          await _loadMusic();
          _updateMusicState();
        }
        break;
      case AppLifecycleState.detached:
        _log.info('App detaching, cleaning up audio.');
        _cleanupAudio();
        if (SoLoud.instance.isInitialized) {
          SoLoud.instance.deinit();
        }
        break;
    }
  }

  void _soundsOnHandler() {
    final soundsOn = _settings?.soundsOn.value ?? false;
    if (!soundsOn) {
      _stopAllSfx();
    }
  }

  void _musicOnHandler() {
    _updateMusicState();
  }
}
