List<String> soundTypeToFilename(SfxType type) {
  switch (type) {
    case SfxType.pickLetter:
      return const ['pickLetter.wav'];
    case SfxType.freeLetter:
      return const ['freeLetter.wav'];
    case SfxType.notAllowed:
      return const ['notAllowed.wav'];
    case SfxType.wrong:
      return const ['wrong.wav'];
    case SfxType.win:
      return const ['win.wav'];
  
  }
}

/// Allows control over loudness of different SFX types.
double soundTypeToVolume(SfxType type) {
  switch (type) {
    case SfxType.pickLetter:
      return 0.4;
    case SfxType.freeLetter:
      return 0.2;
    case SfxType.notAllowed:
      return 0.1;
    case SfxType.wrong:
      return 0.2;
    case SfxType.win:
      return 0.4;
  }
}

enum SfxType { pickLetter, freeLetter, wrong, win, notAllowed }
