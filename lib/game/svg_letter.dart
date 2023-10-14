class SvgLetter {
  String path;
  String letter;
  bool hintGiven = false;
  bool show = false;

  SvgLetter({required String letterPath,required String letterName}) 
    :
      path = letterPath,
      letter = letterName;

}