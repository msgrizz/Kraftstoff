//
//  StoreManager.swift
//  Kraftstoff
//
//  Created by Ingmar Stein on 01.09.15.
//
//

import Foundation
import StoreKit
import Security

final class StoreManager: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
	static let sharedInstance = StoreManager()

	private let twoCarsProductId = "com.github.ingmarstein.kraftstoff.iap.2cars"
	private let fiveCarsProductId = "com.github.ingmarstein.kraftstoff.iap.5cars"
	private let unlimitedCarsProductId = "com.github.ingmarstein.kraftstoff.iap.unlimitedCars"

	override init() {
		super.init()

		SKPaymentQueue.default().add(self)
	}

	private var maxCarCount: Int {
		return fiveCars ? 5 : (twoCars ? 2 : 1)
	}

	func checkCarCount() -> Bool {
		if ProcessInfo.processInfo.arguments.index(of: "-UNLIMITED") != nil {
			return true
		}
		return unlimitedCars || DataManager.cars().count < maxCarCount
	}

	func showBuyOptions(_ parent: UIViewController) {
		let alert = UIAlertController(title: NSLocalizedString("Car limit reached", comment: ""),
			message: NSLocalizedString("Would you like to buy more cars?", comment: ""), preferredStyle: .actionSheet)

		if maxCarCount < 2 {
			let twoCarsAction = UIAlertAction(title: NSLocalizedString("2 Cars", comment: ""), style: .default) { _ in
				self.buyProduct(self.twoCarsProductId)
			}
			alert.addAction(twoCarsAction)
		}

		if maxCarCount < 5 {
			let fiveCarsAction = UIAlertAction(title: NSLocalizedString("5 Cars", comment: ""), style: .default) { _ in
				self.buyProduct(self.fiveCarsProductId)
			}
			alert.addAction(fiveCarsAction)
		}

		let unlimitedCarsAction = UIAlertAction(title: NSLocalizedString("Unlimited Cars", comment: ""), style: .default) { _ in
			self.buyProduct(self.unlimitedCarsProductId)
		}
		alert.addAction(unlimitedCarsAction)

		let restoreAction = UIAlertAction(title: NSLocalizedString("Restore Purchases", comment: ""), style: .default) { _ in
			SKPaymentQueue.default().restoreCompletedTransactions()
		}
		alert.addAction(restoreAction)

		let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
		alert.addAction(cancelAction)

		alert.popoverPresentationController?.sourceView = parent.view
		alert.popoverPresentationController?.sourceRect = parent.view.bounds
		alert.popoverPresentationController?.permittedArrowDirections = []
		parent.present(alert, animated: true, completion: nil)
	}

	private func keychainItemForProduct(_ product: String) -> [String: Any] {
		return [
			String(kSecClass): kSecClassGenericPassword,
			String(kSecAttrService): "com.github.ingmarstein.kraftstoff",
			String(kSecAttrAccount): product,
			String(kSecAttrAccessible): kSecAttrAccessibleWhenUnlocked
		]
	}

	private func isProductPurchased(_ product: String) -> Bool {
		return UIApplication.kraftstoffAppDelegate.validReceiptForInAppPurchase(product) && SecItemCopyMatching(keychainItemForProduct(product) as CFDictionary, nil) == 0
	}

	private func setProductPurchased(_ product: String, purchased: Bool) {
		let keychainItem = keychainItemForProduct(product)
		if purchased {
			SecItemAdd(keychainItem as CFDictionary, nil)
		} else {
			SecItemDelete(keychainItem as CFDictionary)
		}
	}

	var twoCars: Bool {
		return isProductPurchased(twoCarsProductId)
	}

	var fiveCars: Bool {
		return isProductPurchased(fiveCarsProductId)
	}

	var unlimitedCars: Bool {
		return isProductPurchased(unlimitedCarsProductId)
	}

	private func buyProduct(_ productIdentifier: String) {
		if SKPaymentQueue.canMakePayments() {
			let productsRequest = SKProductsRequest(productIdentifiers: [productIdentifier])
			productsRequest.delegate = self
			productsRequest.start()
		}
	}

	func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
		if let product = response.products.first, response.products.count == 1 {
			let payment = SKPayment(product: product)
			SKPaymentQueue.default().add(payment)
		}
	}

	func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
		for transaction in transactions {
			switch transaction.transactionState {
			case .purchased, .restored:
				setProductPurchased(transaction.payment.productIdentifier, purchased: true)
				SKPaymentQueue.default().finishTransaction(transaction)
			case .failed:
				SKPaymentQueue.default().finishTransaction(transaction)
				print("Transaction failed: \(transaction.error!)")
			default: ()
			}
		}
	}

}
