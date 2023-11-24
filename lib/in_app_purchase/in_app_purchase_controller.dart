// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:logging/logging.dart';
import 'package:operation_hermes/C.dart';
import 'package:operation_hermes/in_app_purchase/purchases/purchasable_product.dart';

/// Allows buying in-app. Facade of `package:in_app_purchase`.
class InAppPurchaseController extends ChangeNotifier {
  static final Logger _log = Logger('InAppPurchaseController');

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  InAppPurchase inAppPurchaseInstance;

  /// Creates a new [InAppPurchaseController] with an injected
  /// [InAppPurchase] instance.
  ///
  /// Example usage:
  ///
  ///     var controller = InAppPurchaseController(InAppPurchase.instance);
  InAppPurchaseController(this.inAppPurchaseInstance);

  List<PurchasableProduct> products = [];

  // This is a stupid variable because cancelled purchases ids's will come up empty.
  // So each time we try to buy something we add the purchase to this variable and
  // when the purchase is cancelled (empty id) we set this to purchasable.
  PurchasableProduct? _currentPendingPurchase;

  /// Launches the platform UI for buying an in-app purchase.
  ///
  /// Currently, the only supported in-app purchase is no ad breaks.
  /// To support more, ad additional classes similar to [NoAdBreaksPurchase]
  /// and modify this method.
  Future<void> buy(String productId) async {
    if (!await inAppPurchaseInstance.isAvailable()) {
      _reportError('InAppPurchase.instance not available');
      return;
    }

    final product =
        products.firstWhereOrNull((element) => element.id == productId);
    if (product == null) return;
    product.status = ProductStatus.pending;
    _currentPendingPurchase = product;
    notifyListeners();

    _log.info('Making the purchase for: ${product.productDetails.id}');
    final purchaseParam = PurchaseParam(productDetails: product.productDetails);
    try {
      final success = await inAppPurchaseInstance.buyNonConsumable(
          purchaseParam: purchaseParam);
      _log.info('buyNonConsumable() request was sent with success: $success');
      // The result of the purchase will be reported in the purchaseStream,
      // which is handled in [_listenToPurchaseUpdated].
    } catch (e) {
      _log.severe(
          'Problem with calling inAppPurchaseInstance.buyNonConsumable(): '
          '$e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Asks the underlying platform to list purchases that have been already
  /// made (for example, in a previous session of the game).
  Future<void> restorePurchases() async {
    _reportError('Trying to restore purchases!');

    if (!await inAppPurchaseInstance.isAvailable()) {
      _reportError('InAppPurchase.instance not available');
      return;
    }

    try {
      await inAppPurchaseInstance.restorePurchases();
    } catch (e) {
      _log.severe('Could not restore in-app purchases: $e');
    }
    _log.info('In-app purchases restored');
  }

  /// Subscribes to the [inAppPurchaseInstance.purchaseStream].
  void subscribe() {
    /*  _test_unlock_purchases();
  return; */
    _subscription?.cancel();
    _subscription =
        inAppPurchaseInstance.purchaseStream.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription?.cancel();
    }, onError: (dynamic error) {
      _log.severe('Error occurred on the purchaseStream: $error');
    });
    _loadPurchases();
  }

/*
  void _test_unlock_purchases()
  {
        products.add(
      PurchasableProduct(ProductDetails(id: "com.indest.subliminalwords.remove_3", title: "Remove 3", description: "", price: "price", rawPrice: 2.0, currencyCode: "currencyCode"))
    );
      products.add(
      PurchasableProduct(ProductDetails(id: "com.indest.subliminalwords.highlight", title: "Highlight", description: "", price: "price", rawPrice: 2.0, currencyCode: "currencyCode"))
    );
    products.add(
      PurchasableProduct(ProductDetails(id: "com.indest.subliminalwords.manipulate", title: "Manipulate", description: "", price: "price", rawPrice: 2.0, currencyCode: "currencyCode"))
    );
    products.forEach((element) {
      if (element.id == C.HIGHLIGHT_IOS || element.id == C.MANIPULATE_IOS || element.id == C.REMOVE_3_IOS)
      {
        setProductStatus(ProductStatus.purchased, element.id);
      }
      
    });
    notifyListeners();
  }
  */

  Future<void> _loadPurchases() async {
    if (!await inAppPurchaseInstance.isAvailable()) {
      _reportError('InAppPurchase.instance not available');
      //_test_unlock_purchases();
      return;
    }

    final ids = <String>{
      Platform.isAndroid ? C.ALL_IN_PACK : C.ALL_IN_PACK_IOS,
      Platform.isAndroid ? C.HIGHLIGHT : C.HIGHLIGHT_IOS,
      Platform.isAndroid ? C.MANIPULATE : C.MANIPULATE_IOS,
      Platform.isAndroid ? C.REMOVE_3 : C.REMOVE_3_IOS,
      Platform.isAndroid ? C.NO_AD_BREAKS : C.NO_AD_BREAKS_IOS,
    };

    final response = await inAppPurchaseInstance.queryProductDetails(ids);
    for (var element in response.notFoundIDs) {
      debugPrint('Purchase $element not found');
    }
    products =
        response.productDetails.map((e) => PurchasableProduct(e)).toList();
    _log.info('Loaded products:');
    for (var element in products) {
      _log.info('${element.id} - ${element.status.name}');
    }
    restorePurchases();
    notifyListeners();
  }

  Future<void> _listenToPurchaseUpdated(
      List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      _log.info(() => 'New PurchaseDetails instance received: '
          'productID=${purchaseDetails.productID}, '
          'status=${purchaseDetails.status}, '
          'purchaseID=${purchaseDetails.purchaseID}, '
          'error=${purchaseDetails.error}, '
          'pendingCompletePurchase=${purchaseDetails.pendingCompletePurchase}');

      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          _log.severe('Purchase is pending: $purchaseDetails');
          setProductStatus(ProductStatus.pending, purchaseDetails.productID);
        case PurchaseStatus.purchased:
          _log.severe('Purchase is purchased: $purchaseDetails');
          setProductStatus(ProductStatus.purchased, purchaseDetails.productID);
        case PurchaseStatus.restored:
          bool valid = await _verifyPurchase(purchaseDetails);
          if (valid) {
            _log.severe('Purchase is restored: $purchaseDetails');
            setProductStatus(
                ProductStatus.purchased, purchaseDetails.productID);
          } else {
            _log.severe('Purchase verification failed: $purchaseDetails');
            setProductStatus(
                ProductStatus.purchasable, purchaseDetails.productID);
          }
        case PurchaseStatus.error:
          _log.severe('Error with purchase: ${purchaseDetails.error}');
          setProductStatus(
              ProductStatus.purchasable, purchaseDetails.productID);
        case PurchaseStatus.canceled:
          _log.severe('Purchase is canceled: $purchaseDetails');
          final product = products.firstWhereOrNull(
              (element) => element.id == purchaseDetails.productID);
          if (product == null) {
            _tempWorkaroundForCancelledPurchases();
            return;
          }
          product.status = ProductStatus.purchasable;
          notifyListeners();
      }

      if (purchaseDetails.pendingCompletePurchase) {
        // Confirm purchase back to the store.
        await inAppPurchaseInstance.completePurchase(purchaseDetails);
      }
    }
  }

  void setProductStatus(ProductStatus productStatus, String productId) {
    final product =
        products.firstWhereOrNull((element) => element.id == productId);
    if (product == null) return;
    product.status = productStatus;
    notifyListeners();
  }

  // This is going to be solved by the [in_app_purchase] plugin team
  // in the future hopefully.
  void _tempWorkaroundForCancelledPurchases() {
    if (_currentPendingPurchase != null) {
      final currentProduct = products.firstWhereOrNull((element) =>
          element.id == _currentPendingPurchase?.productDetails.id);
      currentProduct?.status = ProductStatus.purchasable;
      _log.info(
          'Setting status ${ProductStatus.purchasable} to ${currentProduct?.productName}');
      _currentPendingPurchase = null;
      notifyListeners();
    }
  }

  void _reportError(String message) {
    _log.severe(message);
    notifyListeners();
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    _log.info('Verifying purchase: ${purchaseDetails.verificationData}');
    // TODO: verify the purchase.
    // See the info in [purchaseDetails.verificationData] to learn more.
    // There's also a codelab that explains purchase verification
    // on the backend:
    // https://codelabs.developers.google.com/codelabs/flutter-in-app-purchases#9
    return true;
  }

  bool isNoAdsPurchased() {
    return products
        .where((element) =>
            (element.id == C.NO_AD_BREAKS ||
                element.id == C.NO_AD_BREAKS_IOS ||
                element.id == C.ALL_IN_PACK ||
                element.id == C.ALL_IN_PACK_IOS) &&
            element.status == ProductStatus.purchased)
        .isNotEmpty;
  }
}
