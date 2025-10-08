class GameData {
  int progress;
  int? questProgress;
  GameData(this.progress, this.questProgress);

  factory GameData.fromJson(Map json) {
    return GameData(json["progress"], json["questProgress"]);
  }

  Map toJson() => {
    'progress': progress,
    'questProgress': questProgress
    };
}
