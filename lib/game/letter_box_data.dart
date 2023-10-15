import 'package:flutter/foundation.dart';
import 'package:operation_hermes/game/letter_box_state.dart';

class LetterBoxData with ChangeNotifier {
  LetterBoxState _state;
  String _letter;

  LetterBoxData.solutionSlot() 
    : _state = LetterBoxState.solutionSlot,
      _letter = '';

  LetterBoxData.fieldSlot() 
    : _state = LetterBoxState.fieldSlot,
      _letter = '';

  LetterBoxData.solutionPick(String letter) 
      : _state = LetterBoxState.solutionPick,
        _letter = letter;

  LetterBoxData.fieldPick(String letter) 
    : _state = LetterBoxState.fieldPick,
      _letter = letter;

  LetterBoxData.removed(String letter) 
    : _state = LetterBoxState.removed,
      _letter = letter;

  LetterBoxData({LetterBoxState? state, String? letter}) 
    : _state = state ?? LetterBoxState.fieldSlot,
      _letter = letter ?? '';

  // Getter for state
  LetterBoxState get state => _state;

  // Setter for state
  set state(LetterBoxState value) {
    if(_state != value) {
      _state = value;
      notifyListeners();
    }
  }

  // Getter for letter
  String get letter => _letter;

  // Setter for letter
  set letter(String value) {
    if(_letter != value) {
      _letter = value;
      //notifyListeners();
    }
  }
}
