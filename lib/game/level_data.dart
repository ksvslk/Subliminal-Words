class LevelData {
  int nr;
  String word;
  String story;
  String picturePath;
  String svgPath;
  bool zoomRewarded;
  int disabledLettersCount;
  bool levelCompleted;

  LevelData(
    this.nr,
    this.word,
    this.story,
    this.picturePath,
    this.svgPath,
    this.zoomRewarded,
    this.levelCompleted,
    this.disabledLettersCount,
  );

  LevelData.from((String, List<String>) level):
    nr = int.parse(level.$1),
    word = level.$2[0],
    story = level.$2[1],
    picturePath = level.$2[2],
    svgPath = level.$2[3],
    zoomRewarded = bool.parse(level.$2[4]),
    levelCompleted = bool.parse(level.$2[5]),
    disabledLettersCount = int.parse(level.$2[6]);


  (String, List<String>) getLevelDataBasic() {
    return (nr.toString(), <String>[
      word,
      story,
      picturePath,
      svgPath,
      zoomRewarded.toString(),
      levelCompleted.toString(),
      disabledLettersCount.toString()
    ]);
  }

  @override
  bool operator == (Object other) {
    if (other is LevelData) {
      return nr == other.nr;
    }
    return false;
  }
  
  @override
  int get hashCode => super.hashCode;

}
