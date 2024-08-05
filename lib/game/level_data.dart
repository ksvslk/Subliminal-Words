class LevelData {
  int nr;
  String word;
  String story;
  String picturePath;
  String svgPath;
  String tooltipStart;
  String tooltipEnd;
  bool manipulationEnabled;
  int disabledLettersCount;
  bool levelCompleted;
  bool unlocked;

  LevelData(
    this.nr,
    this.word,
    this.story,
    this.picturePath,
    this.svgPath,
    this.tooltipStart,
    this.tooltipEnd,
    this.manipulationEnabled,
    this.levelCompleted,
    this.disabledLettersCount,
    this.unlocked,
  );

  LevelData.from((String, List<String>) level):
    nr = int.parse(level.$1),
    word = level.$2[0],
    story = level.$2[1],
    picturePath = level.$2[2],
    svgPath = level.$2[3],
    tooltipStart = level.$2[4],
    tooltipEnd = level.$2[5],
    manipulationEnabled = bool.parse(level.$2[6]),
    levelCompleted = bool.parse(level.$2[7]),
    disabledLettersCount = int.parse(level.$2[8]),
    unlocked = bool.parse(level.$2[9]);


  (String, List<String>) getLevelDataBasic() {
    return (nr.toString(), <String>[
      word,
      story,
      picturePath,
      svgPath,
      tooltipStart,
      tooltipEnd,
      manipulationEnabled.toString(),
      levelCompleted.toString(),
      disabledLettersCount.toString(),
      unlocked.toString()
    ]);
  }

  @override
  bool operator == (Object other) {
    if (other is LevelData) {
      return nr == other.nr;
    }
    return false;
  }
  

}
