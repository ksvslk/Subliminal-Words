class GameData {
  int progress;
  GameData(this.progress);

  factory GameData.fromJson(Map json) {
    return GameData(json["progress"]);
  }

  Map toJson() => {'progress': progress};
}
