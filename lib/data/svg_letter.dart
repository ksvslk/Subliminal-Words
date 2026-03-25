class SvgLetter {
  bool initialLoad = true;
  String path;
  String letter;
  bool hintGiven = false;
  bool show = false;
  String? text;
  double? x;
  double? y;
  double? fontSize;
  double rotationDegrees;
  double scaleX;
  double scaleY;
  double skewXDegrees;
  double skewYDegrees;
  double opacity;
  int fontWeightValue;

  SvgLetter({
    required this.path,
    required this.letter,
    this.text,
    this.x,
    this.y,
    this.fontSize,
    this.rotationDegrees = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.skewXDegrees = 0,
    this.skewYDegrees = 0,
    this.opacity = 1,
    this.fontWeightValue = 900,
  });

  bool get usesTextOverlay =>
      (text?.isNotEmpty ?? false) && x != null && y != null && fontSize != null;
}
