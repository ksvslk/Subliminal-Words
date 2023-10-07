List<String> soundTypeToFilename(SfxType type) {
  switch (type) {
    case SfxType.pickLetter:
      return const [
        'pickLetter.wav'
      ];
    case SfxType.freeLetter:
      return const [
        'freeLetter.wav'
      ];
  }
}

/// Allows control over loudness of different SFX types.
double soundTypeToVolume(SfxType type) {
  switch (type) {
    case SfxType.pickLetter:
      return 0.4;
    case SfxType.freeLetter:
      return 0.2;
  }
}

enum SfxType {
  pickLetter, freeLetter,
}