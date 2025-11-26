import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/config/C.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class MoneyController extends ChangeNotifier {
  final Logger _log = Logger('money_controller.dart');

  CustomerInfo? _customerInfo;

  MoneyController() {
    _queryCustomerInfo();
    _listenCustomerInfoUpdates();
  }

  void _queryCustomerInfo() async {
    try {
      _customerInfo = await Purchases.getCustomerInfo();
      notifyListeners();
    } on PlatformException catch (e) {
      _log.severe("Error getting customer info: $e");
    }
  }

  void _listenCustomerInfoUpdates() {
    Purchases.addCustomerInfoUpdateListener((info) {
      _customerInfo = info;
      notifyListeners();
    });
  }

  String getEntitlementName(String entitlementId) {
    switch (entitlementId) {
      case C.entitlementHighlightId:
        return "Highlight";
      case C.entitlementManipulateId:
        return "Manipulate";
      case C.entitlementRemove3Id:
        return "Remove 3";
      default:
        return "Unknown";
    }
  }

  bool hasEntitlement(String entitlementId) {
    return _customerInfo?.entitlements.all[entitlementId]?.isActive == true;
  }

  bool hasAllAccess() {
    if (_customerInfo?.entitlements.all[C.entitlementPropassId]?.isActive ==
            true ||
        _customerInfo
                ?.entitlements.all[C.entitlementLifetimeUnlockId]?.isActive ==
            true) {
      return true;
    } else {
      return false;
    }
  }

  void restorePurchases(BuildContext context) async {
    try {
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      if (customerInfo.entitlements.active.isNotEmpty) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Success'),
                content: const Text(
                  'Your purchases have been restored successfully.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        }
      } else {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('No Purchases Found'),
                content: const Text(
                  'No previous purchases were found to restore.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        }
      }
    } on PlatformException catch (e) {
      _log.severe("Error restoring purchases: $e");
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Error'),
              content: const Text(
                'Failed to restore purchases. Please try again later.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    }
  }
}
