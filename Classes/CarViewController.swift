//
//  CarViewController.swift
//  kraftstoff
//
//  Created by Ingmar Stein on 05.05.15.
//
//

import UIKit
import CoreSpotlight
import RealmSwift

private let maxEditHelpCounter = 1
private let carViewEditedObject = "CarViewEditedObject"

final class CarViewController: UITableViewController, UIDataSourceModelAssociation, UIGestureRecognizerDelegate, CarConfigurationControllerDelegate, UIDocumentPickerDelegate {

	var editedObject: Car!

	// swiftlint:disable:next force_try
	private let realm = try! Realm()
	private var notificationToken: NotificationToken?

	private lazy var cars: Results<Car> = {
		let results = DataManager.cars()
		self.notificationToken = results.observe { (changes) in
			self.tableView.applyChanges(changes: changes, with: .fade)

			self.updateHelp(true)
			self.checkEnableEditButton()
		}
		return results
	}()

	private var documentPickerViewController: UIDocumentPickerViewController!

	private var longPressRecognizer: UILongPressGestureRecognizer? {
		didSet {
			if let old = oldValue {
				tableView.removeGestureRecognizer(old)
			}
			if let new = longPressRecognizer {
				tableView.addGestureRecognizer(new)
			}
		}
	}

	var fuelEventController: FuelEventController!

	// MARK: - View Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()

		// Navigation Bar
		self.title = NSLocalizedString("Cars", comment: "")
		self.navigationItem.leftBarButtonItem = nil

		let rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(CarViewController.insertNewObject(_:)))
		rightBarButtonItem.accessibilityIdentifier = "add"
		self.navigationItem.rightBarButtonItem = rightBarButtonItem

		// Gesture recognizer for touch and hold
		self.longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(CarViewController.handleLongPress(_:)))
		self.longPressRecognizer!.delegate = self

		// Reset tint color
		self.navigationController?.navigationBar.tintColor = nil

		// Background image
		let backgroundView = UIView(frame: .zero)
		backgroundView.backgroundColor = self.tableView.backgroundColor
		let backgroundImage = UIImageView(image: #imageLiteral(resourceName: "Pumps"))
		backgroundImage.translatesAutoresizingMaskIntoConstraints = false
		backgroundView.addSubview(backgroundImage)
		NSLayoutConstraint.activate([
			NSLayoutConstraint(item: backgroundView, attribute: .bottom, relatedBy: .equal, toItem: backgroundImage, attribute: .bottom, multiplier: 1.0, constant: 90.0),
			NSLayoutConstraint(item: backgroundView, attribute: .centerX, relatedBy: .equal, toItem: backgroundImage, attribute: .centerX, multiplier: 1.0, constant: 0.0)
		])
		self.tableView.backgroundView = backgroundView

		self.tableView.estimatedRowHeight = self.tableView.rowHeight
		self.tableView.rowHeight = UITableViewAutomaticDimension

		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(CarViewController.localeChanged(_:)),
		                                       name: NSLocale.currentLocaleDidChangeNotification,
		                                       object: nil)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		updateHelp(true)
		checkEnableEditButton()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		hideHelp(animated)
	}

	// MARK: - State Restoration

	override func encodeRestorableState(with coder: NSCoder) {
		if let editedObject = editedObject {
			coder.encode(editedObject.id, forKey: carViewEditedObject)
		}
		super.encodeRestorableState(with: coder)
	}

	override func decodeRestorableState(with coder: NSCoder) {
		super.decodeRestorableState(with: coder)

		if let modelIdentifier = coder.decodeObject(of: NSString.self, forKey: carViewEditedObject) as String? {
			self.editedObject = realm.object(ofType: Car.self, forPrimaryKey: modelIdentifier)
		}

		// -> openradar #13438788
		self.tableView.reloadData()
	}

	// MARK: - Locale Handling

	@objc func localeChanged(_ object: AnyObject) {
		// Invalidate fuelEvent-controller and any precomputed statistics
		if self.navigationController!.topViewController === self {
			fuelEventController = nil
		}

		self.tableView.reloadData()
	}

	// MARK: - Help Badge

	private func updateHelp(_ animated: Bool) {
		let defaults = UserDefaults.standard

		// Number of cars determines the help badge
		let helpViewFrame: CGRect
		let helpViewContentMode: UIViewContentMode
		let helpImage: UIImage?

		let carCount = cars.count

		if !self.isEditing && carCount == 0 {
			helpImage = StyleKit.imageOfStartHelpCanvas(text: NSLocalizedString("StartHelp", comment: "")).withRenderingMode(.alwaysTemplate)
			helpViewFrame = CGRect(x: 0, y: 0, width: self.view.bounds.size.width, height: 70)
			helpViewContentMode = .right

			defaults.set(0, forKey: "editHelpCounter")
		} else if self.isEditing && 1 <= carCount && carCount <= 3 {
			let editCounter = defaults.integer(forKey: "editHelpCounter")

			if editCounter < maxEditHelpCounter {
				defaults.set(editCounter + 1, forKey: "editHelpCounter")
				helpImage = StyleKit.imageOfEditHelpCanvas(line1: NSLocalizedString("EditHelp1", comment: ""), line2: NSLocalizedString("EditHelp2", comment: "")).withRenderingMode(.alwaysTemplate)
				helpViewContentMode = .left
				helpViewFrame = CGRect(x: 0.0, y: CGFloat(carCount) * 91.0 - 16.0, width: self.view.bounds.size.width, height: 92.0)
			} else {
				helpImage = nil
				helpViewContentMode = .left
				helpViewFrame = .zero
			}
		} else {
			helpImage = nil
			helpViewContentMode = .left
			helpViewFrame = .zero
		}

		// Remove outdated help images
		var helpView = self.view.viewWithTag(100) as? UIImageView

		if helpImage == nil || (helpView != nil && helpView!.frame != helpViewFrame) {
			if animated {
				UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.33, delay: 0, options: [.curveEaseOut], animations: {
					helpView?.alpha = 0.0
				}) { _ in
					helpView?.removeFromSuperview()
				}
			} else {
				helpView?.removeFromSuperview()
			}
		}

		// Add or update existing help image
		if let helpImage = helpImage {
			if let helpView = helpView {
				helpView.image = helpImage
				helpView.frame = helpViewFrame
			} else {
				helpView        = UIImageView(image: helpImage)
				helpView!.tag   = 100
				helpView!.frame = helpViewFrame
				helpView!.alpha = animated ? 0.0 : 1.0
				helpView!.contentMode = helpViewContentMode

				self.view.addSubview(helpView!)

				if animated {
					UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.33, delay: 0.8, options: [.curveEaseOut], animations: {
						helpView?.alpha = 1.0
					})
				}
			}
		}

		// Update the toolbar button
		self.navigationItem.leftBarButtonItem = (carCount == 0) ? nil : self.editButtonItem
		checkEnableEditButton()
	}

	private func hideHelp(_ animated: Bool) {
		if let helpView = self.view.viewWithTag(100) as? UIImageView {
			if animated {
				UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.33, delay: 0.8, options: [.curveEaseOut], animations: {
					helpView.alpha = 0.0
				}, completion: { _ in
					helpView.removeFromSuperview()
				})
			} else {
				helpView.removeFromSuperview()
			}
		}
	}

	// MARK: - CarConfigurationControllerDelegate

	func carConfigurationController(_ controller: CarConfigurationController, didFinishWithResult result: CarConfigurationResult) {
		if result == .createSucceeded {
			// Create new car
			let newCar = Car()
			newCar.order = 0
			newCar.timestamp = Date()
			newCar.odometerUnit = .fromPersistentId(controller.odometerUnit!.intValue)

			newCar.odometer = Units.kilometersForDistance(controller.odometer!,
														  withUnit: .fromPersistentId(controller.odometerUnit!.intValue))

			newCar.fuelUnit = .fromPersistentId(controller.fuelUnit!.intValue)
			newCar.fuelConsumptionUnit = .fromPersistentId(controller.fuelConsumptionUnit!.intValue)

			let addDemoEvents: Bool
			let enteredName = controller.name!
			let enteredPlate = controller.plate!
			if enteredName.lowercased() == "apple" && enteredPlate.lowercased() == "demo" {
				addDemoEvents = true
				newCar.name = "Toyota IQ+"
				newCar.numberPlate = "SLS IOIOI"
			} else {
				addDemoEvents = false
				newCar.name = enteredName
				newCar.numberPlate = enteredPlate
			}

			// swiftlint:disable:next force_try
			try! realm.write {
				// Update order of existing cars
				for car in cars {
					car.order += 1
				}

				realm.add(newCar)

				if addDemoEvents {
					// add demo data
					newCar.addDemoEvents()
				}
			}

		} else if result == .editSucceeded {

			// swiftlint:disable:next force_try
			try! realm.write {
				editedObject.name = controller.name!
				editedObject.numberPlate = controller.plate!
				editedObject.odometerUnit = .fromPersistentId(controller.odometerUnit!.intValue)

				let odometer = max(Units.kilometersForDistance(controller.odometer!,
															   withUnit: .fromPersistentId(controller.odometerUnit!.intValue)), editedObject.distanceTotalSum)

				editedObject.odometer = odometer
				editedObject.fuelUnit = .fromPersistentId(controller.fuelUnit!.intValue)
				editedObject.fuelConsumptionUnit = .fromPersistentId(controller.fuelConsumptionUnit!.intValue)
			}

			// Invalidate fuelEvent-controller and any precomputed statistics
			fuelEventController = nil
		}

		self.editedObject = nil
		checkEnableEditButton()

		dismiss(animated: result != .aborted, completion: nil)
	}

	// MARK: - Adding a new object

	override func setEditing(_ editing: Bool, animated: Bool) {
		super.setEditing(editing, animated: animated)

		checkEnableEditButton()
		updateHelp(animated)

		// Force Core Data save after editing mode is finished
		/*
		if !editing {
			DataManager.saveContext()
		}
		*/
	}

	private func checkEnableEditButton() {
		self.editButtonItem.isEnabled = cars.count > 0
	}

	@objc func insertNewObject(_ sender: UIBarButtonItem) {
		if !StoreManager.sharedInstance.checkCarCount() {
			StoreManager.sharedInstance.showBuyOptions(self)
			return
		}

		setEditing(false, animated: true)

		let alertController = UIAlertController(title: NSLocalizedString("New Car", comment: ""),
		                                        message: nil,
		                                        preferredStyle: .actionSheet)
		let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
		}
		let newAction = UIAlertAction(title: NSLocalizedString("New Car", comment: ""), style: .default) { [unowned self] _ in
			if let configurator = self.storyboard!.instantiateViewController(withIdentifier: "CarConfigurationController") as? CarConfigurationController {
				configurator.delegate = self
				configurator.editingExistingObject = false

				let navController = UINavigationController(rootViewController: configurator)
				navController.restorationIdentifier = "CarConfigurationNavigationController"
				navController.navigationBar.tintColor = self.navigationController!.navigationBar.tintColor

				self.present(navController, animated: true, completion: nil)
			}
		}
		let importAction = UIAlertAction(title: NSLocalizedString("Import", comment: ""), style: .default) { [unowned self] _ in
			self.documentPickerViewController = UIDocumentPickerViewController(documentTypes: ["public.comma-separated-values-text"], in: .`import`)
			self.documentPickerViewController.delegate = self

			self.present(self.documentPickerViewController, animated: true, completion: nil)
		}
		alertController.addAction(cancelAction)
		alertController.addAction(newAction)
		alertController.addAction(importAction)
		alertController.popoverPresentationController?.barButtonItem = sender

		present(alertController, animated: true, completion: nil)
	}

	// MARK: - UIDocumentPickerDelegate

	func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
		documentPickerViewController = nil
	}

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
		UIApplication.kraftstoffAppDelegate.importCSV(at: url)

		documentPickerViewController = nil
	}

	// MARK: - UIGestureRecognizerDelegate

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		// Editing mode must be enabled
		if self.isEditing {
			var view: UIView? = touch.view

			// Touch must hit the contentview of a tableview cell
			while view != nil {
				if let tableViewCell = view as? UITableViewCell {
					return tableViewCell.contentView === touch.view
				}

				view = view!.superview
			}
		}

		return false
	}

	// MARK: - Gesture Recognizer for Editing an Existing Object

	@objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {

			if let indexPath = self.tableView.indexPathForRow(at: sender.location(in: self.tableView)) {
				self.editedObject = cars[indexPath.row]

				// Present modal car configurator
				guard let configurator = self.storyboard!.instantiateViewController(withIdentifier: "CarConfigurationController") as? CarConfigurationController else { return }
				configurator.delegate = self
				configurator.editingExistingObject = true

				configurator.name = editedObject.name

				if configurator.name!.count > TextEditTableCell.DefaultMaximumTextFieldLength {
					configurator.name = ""
				}

				configurator.plate = editedObject.numberPlate

				if configurator.plate!.count > TextEditTableCell.DefaultMaximumTextFieldLength {
					configurator.plate = ""
				}

				configurator.odometerUnit = NSNumber(value: editedObject.odometerUnit.persistentId)
				configurator.odometer     = Units.distanceForKilometers(editedObject.odometer,
                                                                  withUnit: editedObject.odometerUnit)

				configurator.fuelUnit            = NSNumber(value: editedObject.fuelUnit.persistentId)
				configurator.fuelConsumptionUnit = NSNumber(value: editedObject.fuelConsumptionUnit.persistentId)

				let navController = UINavigationController(rootViewController: configurator)
				navController.restorationIdentifier = "CarConfigurationNavigationController"
				navController.navigationBar.tintColor = self.navigationController!.navigationBar.tintColor

				present(navController, animated: true, completion: nil)

				// Edit started => prevent edit help from now on
				UserDefaults.standard.set(maxEditHelpCounter, forKey: "editHelpCounter")

				// Quit editing mode
				setEditing(false, animated: true)
			}
		}
	}

	// MARK: - Removing an Existing Object

	func removeExistingObject(at indexPath: IndexPath) {
		let deletedCar = cars[indexPath.row]
		let deletedCarOrder = deletedCar.order

		// Invalidate preference for deleted car
		let preferredCarID = UserDefaults.standard.string(forKey: "preferredCarID")
		let deletedCarID = deletedCar.id

		if deletedCarID == preferredCarID {
			UserDefaults.standard.set("", forKey: "preferredCarID")
		}

		CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [deletedCarID], completionHandler: nil)

		// swiftlint:disable:next force_try
		try! realm.write {
			// Delete the managed object for the given index path
			deletedCar.isDeleted = true

			// Update order of existing objects
			for car in cars where car.order > deletedCarOrder {
				car.order -= 1
			}
        }

		// Exit editing mode after last object is deleted
		if self.isEditing {
			if cars.count == 0 {
				setEditing(false, animated: true)
			}
		}
	}

	// MARK: - UITableViewDataSource

	func configureCell(_ cell: UITableViewCell, atIndexPath indexPath: IndexPath) {

		guard let tableCell = cell as? QuadInfoCell else { return }
		let car = cars[indexPath.row]

		tableCell.large = true

		// name and number plate
		tableCell.topLeftLabel.text = car.name
		tableCell.topLeftAccessibilityLabel = nil

		tableCell.botLeftLabel.text = car.numberPlate
		tableCell.topRightAccessibilityLabel = nil

		// Average consumption
		let avgConsumption: String
		let consumptionUnit = car.fuelConsumptionUnit

		let distance   = car.distanceTotalSum
		let fuelVolume = car.fuelVolumeTotalSum

		if distance > 0 && fuelVolume > 0 {
			avgConsumption = Formatters.fuelVolumeFormatter.string(from: Units.consumptionForKilometers(distance, liters: fuelVolume, inUnit: consumptionUnit) as NSNumber)!
			tableCell.topRightAccessibilityLabel = avgConsumption
			tableCell.botRightAccessibilityLabel = Formatters.mediumMeasurementFormatter.string(from: consumptionUnit)
		} else {
			avgConsumption = NSLocalizedString("-", comment: "")
			tableCell.topRightAccessibilityLabel = NSLocalizedString("fuel mileage not available", comment: "")
			tableCell.botRightAccessibilityLabel = nil
		}

		tableCell.topRightLabel.text = avgConsumption
		tableCell.botRightLabel.text = Formatters.shortMeasurementFormatter.string(from: consumptionUnit)
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return cars.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "QuadInfoCell", for: indexPath)

		configureCell(cell, atIndexPath: indexPath)

		return cell
	}

	override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
		if editingStyle == .delete {
			removeExistingObject(at: indexPath)
		}
	}

	override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
		let basePath = sourceIndexPath.dropLast()

		if basePath.compare(destinationIndexPath.dropLast()) != .orderedSame {
			fatalError("Invalid index path for moveRow")
		}

		let cmpResult = sourceIndexPath.compare(destinationIndexPath)
		let length = sourceIndexPath.count
		let from: Int
		let to: Int

		if cmpResult == .orderedAscending {
			from = sourceIndexPath[length - 1]
			to   = destinationIndexPath[length - 1]
		} else if cmpResult == .orderedDescending {
			to   = sourceIndexPath[length - 1]
			from = destinationIndexPath[length - 1]
		} else {
			return
		}

		// swiftlint:disable:next force_try
		try! realm.write {
			for i in from...to {
				let car = cars[i]
				var order = car.order

				if cmpResult == .orderedAscending {
					order = (i != from) ? order-1 : to
				} else {
					order = (i != to)   ? order+1 : from
				}

				car.order = order
			}
		}
	}

	override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		return true
	}

	// MARK: - UIDataSourceModelAssociation

	func indexPathForElement(withModelIdentifier identifier: String, in view: UIView) -> IndexPath? {
		guard let car = realm.object(ofType: Car.self, forPrimaryKey: identifier) else { return nil }
		guard let row = cars.index(of: car) else { return nil }

		return IndexPath(row: row, section: 0)
	}

	func modelIdentifierForElement(at idx: IndexPath, in view: UIView) -> String? {
		return cars[idx.row].id
	}

	// MARK: - UITableViewDelegate

	override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
		return proposedDestinationIndexPath
	}

	override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
		return self.isEditing ? nil : indexPath
	}

	override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
		print("test")
	}

	override func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
		editButtonItem.isEnabled = false
		hideHelp(true)
	}

	override func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
		checkEnableEditButton()
		updateHelp(true)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		let selection: IndexPath?
		if let cell = sender as? UITableViewCell {
			selection = tableView.indexPath(for: cell)
		} else {
			selection = tableView.indexPathForSelectedRow
		}

		if let fuelEventController = segue.destination as? FuelEventController, let selection = selection {
			let selectedCar = cars[selection.row]
			fuelEventController.selectedCar = selectedCar
		}
	}

	// MARK: - Memory Management

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()

		if self.navigationController!.topViewController === self {
			fuelEventController = nil
		}
	}

	deinit {
		notificationToken?.invalidate()
		NotificationCenter.default.removeObserver(self)
	}
}
