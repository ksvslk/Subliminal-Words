import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';

void showJoinCompetitionDialog(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (BuildContext buildContext, Animation<double> animation,
        Animation secondaryAnimation) {
      return ScaleTransition(
        scale: Tween<double>(begin: 0.5, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.fastOutSlowIn,
          ),
        ),
        child: JoinCompetitionDialog(),
      );
    },
  );
}

class JoinCompetitionDialog extends StatefulWidget {
  @override
  _JoinCompetitionDialogState createState() => _JoinCompetitionDialogState();
}

class _JoinCompetitionDialogState extends State<JoinCompetitionDialog>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isJoining = false;
  late AnimationController _confettiController;

  // Assuming there's a field that tracks the remaining prizes
  int remainingPrizes = 10; // Example value

  @override
  void initState() {
    super.initState();
    _confettiController =
        AnimationController(duration: const Duration(seconds: 3), vsync: this);
    // You can load the actual remaining prizes value from Firestore here
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _joinCompetition() async {
    setState(() {
      _isJoining = true;
    });

    try {
      String userId = 'current_user_id'; // Replace with actual user ID
      DocumentSnapshot userDoc =
          await _firestore.collection('players').doc(userId).get();

      if (userDoc.exists && userDoc.get('registered') == true) {
        _showSnackBar('You have already joined the competition!');
        Navigator.of(context).pop();
      } else {
        await _firestore.collection('players').doc(userId).set({
          'registered': true,
          'current_level': 1,
          'promo_code': null,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Decrease the remaining prizes count
        setState(() {
          remainingPrizes--;
        });

        _confettiController.forward();
        await Future.delayed(const Duration(seconds: 2));
        _showSnackBar('Successfully joined the competition!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error joining competition: $e');
      _showSnackBar('Failed to join the competition. Please try again.');
    } finally {
      setState(() {
        _isJoining = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final maxDialogWidth = MediaQuery.of(context).size.width * 0.9;
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.9;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            padding: const EdgeInsets.all(20),
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: maxDialogHeight,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primaryContainer,
                  Theme.of(context).colorScheme.surfaceContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  flex: 1,
                  child: Lottie.network(
                    'https://assets1.lottiefiles.com/packages/lf20_xyadoh9h.json',
                    width: constraints.maxWidth * 0.6,
                    height: constraints.maxHeight * 0.25,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  flex: 1,
                  child: Text(
                    'Level Completion Challenge',
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.headlineMedium?.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  flex: 1,
                  child: Text(
                    'Be among the first players to complete the first 50 levels and win an exclusive prize!',
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                      color: Theme.of(context)
                          .colorScheme
                          .onSecondaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  flex: 1,
                  child: ElevatedButton(
                    onPressed: _isJoining ? null : _joinCompetition,
                    style: ElevatedButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.onPrimary,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _isJoining
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white)),
                          )
                        : Text('Join the Challenge',
                            style: TextStyle(fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize)),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  flex: 1,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Maybe Later',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  flex: 1,
                  child: Text(
                    'Prizes left: $remainingPrizes',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  flex: 1,
                  child: Lottie.network(
                    'https://assets9.lottiefiles.com/packages/lf20_u4yrau.json',
                    controller: _confettiController,
                    width: constraints.maxWidth * 0.8,
                    height: constraints.maxHeight * 0.35,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
