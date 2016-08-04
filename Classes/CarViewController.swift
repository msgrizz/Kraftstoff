//
//  CarViewController.swift
//  kraftstoff
//
//  Created by Ingmar Stein on 05.05.15.
//
//

import UIKit
import CoreData
import CoreSpotlight

private let maxEditHelpCounter = 1
private let kSRCarViewEditedObject = "CarViewEditedObject"

final class CarViewController: UITableViewController, UIDataSourceModelAssociation, UIGestureRecognizerDelegate, NSFetchedResultsControllerDelegate, CarConfigurationControllerDelegate {

	var editedObject: Car!

	private lazy var fetchedResultsController: NSFetchedResultsController<Car> = {
		let fetchedResultsController = CoreDataManager.fetchedResultsControllerForCars()
		fetchedResultsController.delegate = self
		return fetchedResultsController
	}()

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

	private var changeIsUserDriven = false

	// MARK: - View Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()

		changeIsUserDriven = false

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
		backgroundView.backgroundColor = #colorLiteral(red: 0.937254902, green: 0.937254902, blue: 0.937254902, alpha: 1)
		let backgroundImage = UIImageView(image: #imageLiteral(resourceName: "Pumps"))
		backgroundImage.translatesAutoresizingMaskIntoConstraints = false
		backgroundView.addSubview(backgroundImage)
		backgroundView.addConstraint(NSLayoutConstraint(item: backgroundView, attribute: .bottom, relatedBy: .equal, toItem: backgroundImage, attribute: .bottom, multiplier: 1.0, constant: 90.0))
		backgroundView.addConstraint(NSLayoutConstraint(item: backgroundView, attribute: .centerX, relatedBy: .equal, toItem: backgroundImage, attribute: .centerX, multiplier: 1.0, constant: 0.0))
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
			coder.encode(CoreDataManager.modelIdentifierForManagedObject(editedObject) as NSString?, forKey: kSRCarViewEditedObject)
		}
		super.encodeRestorableState(with: coder)
	}

	override func decodeRestorableState(with coder: NSCoder) {
		super.decodeRestorableState(with: coder)

		if let modelIdentifier = coder.decodeObject(of: NSString.self, forKey: kSRCarViewEditedObject) as? String {
			self.editedObject = CoreDataManager.managedObjectForModelIdentifier(modelIdentifier)
		}

		// -> openradar #13438788
		self.tableView.reloadData()
	}

	// MARK: - Locale Handling

	func localeChanged(_ object: AnyObject) {
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
		let helpImageName: String?
		let helpViewFrame: CGRect
		let helpViewContentMode: UIViewContentMode

		let carCount = fetchedResultsController.fetchedObjects!.count

		if !self.isEditing && carCount == 0 {
			helpImageName = "StartFlat"
			helpViewFrame = CGRect(x: 0, y: 0, width: self.view.bounds.size.width, height: 70)
			helpViewContentMode = .right

			defaults.set(0, forKey: "editHelpCounter")
		} else if self.isEditing && 1 <= carCount && carCount <= 3 {
			let editCounter = defaults.integer(forKey: "editHelpCounter")

			if editCounter < maxEditHelpCounter {
				defaults.set(editCounter + 1, forKey: "editHelpCounter")
				helpImageName = "EditFlat"
				helpViewContentMode = .left
				helpViewFrame = CGRect(x: 0.0, y: CGFloat(carCount) * 91.0 - 16.0, width: self.view.bounds.size.width, height: 92.0)
			} else {
				helpImageName = nil
				helpViewContentMode = .left
				helpViewFrame = .zero
			}
		} else {
			helpImageName = nil
			helpViewContentMode = .left
			helpViewFrame = .zero
		}

		// Remove outdated help images
		var helpView = self.view.viewWithTag(100) as? UIImageView

		if helpImageName == nil || (helpView != nil && helpView!.frame != helpViewFrame) {
			if animated {
				UIView.animate(withDuration: 0.33, delay: 0.0, options: .curveEaseOut,
                             animations: { helpView?.alpha = 0.0 },
                             completion: { finished in helpView?.removeFromSuperview() })
			} else {
				helpView?.removeFromSuperview()
			}
		}

		// Add or update existing help image
		if let helpImageName = helpImageName {
			if let helpView = helpView {
				helpView.image = UIImage(named: helpImageName)
				helpView.frame = helpViewFrame
			} else {
				let helpImage   = UIImage(named: NSLocalizedString(helpImageName, comment: ""))!.withRenderingMode(.alwaysTemplate)

				helpView        = UIImageView(image: helpImage)
				helpView!.tag   = 100
				helpView!.frame = helpViewFrame
				helpView!.alpha = animated ? 0.0 : 1.0
				helpView!.contentMode = helpViewContentMode

				self.view.addSubview(helpView!)

				if animated {
					UIView.animate(withDuration: 0.33,
										delay: 0.8,
                                    options: .curveEaseOut,
                                 animations: { helpView!.alpha = 1.0 },
                                 completion: nil)
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
				UIView.animate(withDuration: 0.33,
                                  delay: 0.0,
                                options: .curveEaseOut,
                             animations: { helpView.alpha = 0.0 },
                             completion: { finished in helpView.removeFromSuperview() })
			} else {
				helpView.removeFromSuperview()
			}
		}
	}

	// MARK: - CarConfigurationControllerDelegate

	func carConfigurationController(_ controller: CarConfigurationController, didFinishWithResult result: CarConfigurationResult) {
		if result == .createSucceeded {
			var addDemoContents = false

			// Update order of existing objects
			changeIsUserDriven = true

			for car in self.fetchedResultsController.fetchedObjects! {
				car.order += 1
            }

            // Detect demo data request
            if controller.name!.lowercased() == "apple" && controller.plate!.lowercased() == "demo" {
                addDemoContents = true

                controller.name  = "Toyota IQ+"
                controller.plate = "SLS IOIOI"
            }

			changeIsUserDriven = false

			// Create a new instance of the entity managed by the fetched results controller.
			let newManagedObject = Car(context: CoreDataManager.managedObjectContext)

			newManagedObject.order = 0
			newManagedObject.timestamp = Date()
			newManagedObject.name = controller.name!
			newManagedObject.numberPlate = controller.plate!
			newManagedObject.odometerUnit = controller.odometerUnit!.int32Value

			newManagedObject.odometer = Units.kilometersForDistance(controller.odometer!,
														withUnit: .fromPersistentId(controller.odometerUnit!.int32Value))

			newManagedObject.fuelUnit = controller.fuelUnit!.int32Value
			newManagedObject.fuelConsumptionUnit = controller.fuelConsumptionUnit!.int32Value

			// Add demo contents
			if addDemoContents {
				DemoData.addDemoEvents(newManagedObject, inContext: CoreDataManager.managedObjectContext)
			}

			// Saving here is important here to get a stable objectID for the fuelEvent fetches
			CoreDataManager.saveContext()

		} else if result == .editSucceeded {

			editedObject.name = controller.name!
			editedObject.numberPlate = controller.plate!
			editedObject.odometerUnit = controller.odometerUnit!.int32Value

			let odometer = max(Units.kilometersForDistance(controller.odometer!,
                                                              withUnit: .fromPersistentId(controller.odometerUnit!.int32Value)), editedObject.distanceTotalSum)

			editedObject.odometer = odometer
			editedObject.fuelUnit = controller.fuelUnit!.int32Value
			editedObject.fuelConsumptionUnit = controller.fuelConsumptionUnit!.int32Value

			CoreDataManager.saveContext()

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
			CoreDataManager.saveContext()
		}
		*/
	}

	private func checkEnableEditButton() {
		self.editButtonItem.isEnabled = fetchedResultsController.fetchedObjects!.count > 0
	}

	func insertNewObject(_ sender: AnyObject) {
		if !StoreManager.sharedInstance.checkCarCount() {
			StoreManager.sharedInstance.showBuyOptions(self)
			return
		}

		setEditing(false, animated: true)

		if let configurator = self.storyboard!.instantiateViewController(withIdentifier: "CarConfigurationController") as? CarConfigurationController {
			configurator.delegate = self
			configurator.editingExistingObject = false

			let navController = UINavigationController(rootViewController: configurator)
			navController.restorationIdentifier = "CarConfigurationNavigationController"
			navController.navigationBar.tintColor = self.navigationController!.navigationBar.tintColor

			present(navController, animated: true, completion: nil)
		}
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

	func handleLongPress(_ sender: UILongPressGestureRecognizer) {
		if sender.state == .began {

			if let indexPath = self.tableView.indexPathForRow(at: sender.location(in: self.tableView)) {
				CoreDataManager.saveContext()
				self.editedObject = self.fetchedResultsController.object(at: indexPath)

				// Present modal car configurator
				guard let configurator = self.storyboard!.instantiateViewController(withIdentifier: "CarConfigurationController") as? CarConfigurationController else { return }
				configurator.delegate = self
				configurator.editingExistingObject = true

				configurator.name = editedObject.name

				if configurator.name!.characters.count > TextEditTableCell.DefaultMaximumTextFieldLength {
					configurator.name = ""
				}

				configurator.plate = editedObject.numberPlate

				if configurator.plate!.characters.count > TextEditTableCell.DefaultMaximumTextFieldLength {
					configurator.plate = ""
				}

				configurator.odometerUnit = NSNumber(value: editedObject.odometerUnit)
				configurator.odometer     = Units.distanceForKilometers(editedObject.odometer,
                                                                  withUnit: editedObject.ksOdometerUnit)

				configurator.fuelUnit            = NSNumber(value: editedObject.fuelUnit)
				configurator.fuelConsumptionUnit = NSNumber(value: editedObject.fuelConsumptionUnit)

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
		let deletedObject = self.fetchedResultsController.object(at: indexPath)
		let deletedObjectOrder = deletedObject.order

		// Invalidate preference for deleted car
		let preferredCarID = UserDefaults.standard.string(forKey: "preferredCarID")
		let deletedCarID = CoreDataManager.modelIdentifierForManagedObject(deletedObject)

		if deletedCarID == preferredCarID {
			UserDefaults.standard.set("", forKey: "preferredCarID")
		}

		// Delete the managed object for the given index path
		CoreDataManager.managedObjectContext.delete(deletedObject)
		CoreDataManager.saveContext()

		if let itemID = deletedCarID {
			CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [itemID], completionHandler: nil)
		}

		// Update order of existing objects
		changeIsUserDriven = true

		for managedObject in self.fetchedResultsController.fetchedObjects! {
			let order = managedObject.order

			if order > deletedObjectOrder {
                managedObject.order = order-1
			}
        }

		CoreDataManager.saveContext()

		changeIsUserDriven = false

		// Exit editing mode after last object is deleted
		if self.isEditing {
			if self.fetchedResultsController.fetchedObjects!.count == 0 {
				setEditing(false, animated: true)
			}
		}
	}

	// MARK: - UITableViewDataSource

	func configureCell(_ cell: UITableViewCell, atIndexPath indexPath: IndexPath) {

		guard let tableCell = cell as? QuadInfoCell else { return }
		let managedObject = self.fetchedResultsController.object(at: indexPath)

		tableCell.large = true

		// name and number plate
		tableCell.topLeftLabel.text = managedObject.name
		tableCell.topLeftAccessibilityLabel = nil

		tableCell.botLeftLabel.text = managedObject.numberPlate
		tableCell.topRightAccessibilityLabel = nil

		// Average consumption
		let avgConsumption: String
		let consumptionUnit = managedObject.ksFuelConsumptionUnit

		let distance   = managedObject.distanceTotalSum
		let fuelVolume = managedObject.fuelVolumeTotalSum

		if distance > .zero && fuelVolume > .zero {
			avgConsumption = Formatters.fuelVolumeFormatter.string(from: Units.consumptionForKilometers(distance, liters: fuelVolume, inUnit: consumptionUnit))!
			tableCell.topRightAccessibilityLabel = avgConsumption
			tableCell.botRightAccessibilityLabel = Formatters.shortMeasurementFormatter.string(from: consumptionUnit)
		} else {
			avgConsumption = NSLocalizedString("-", comment: "")
			tableCell.topRightAccessibilityLabel = NSLocalizedString("fuel mileage not available", comment: "")
			tableCell.botRightAccessibilityLabel = nil
		}

		tableCell.topRightLabel.text = avgConsumption
		tableCell.botRightLabel.text = Formatters.shortMeasurementFormatter.string(from: consumptionUnit)
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return self.fetchedResultsController.sections?.count ?? 0
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		let sectionInfo = self.fetchedResultsController.sections![section]

		return sectionInfo.numberOfObjects
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

		for i in from...to {
			let managedObject = self.fetchedResultsController.object(at: basePath.appending(i))
			var order = Int(managedObject.order)

			if cmpResult == .orderedAscending {
				order = (i != from) ? order-1 : to
			} else {
				order = (i != to)   ? order+1 : from
			}

			managedObject.order = Int32(order)
		}

		changeIsUserDriven = true
	}

	override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		return true
	}

	// MARK: - UIDataSourceModelAssociation

	func indexPathForElement(withModelIdentifier identifier: String, in view: UIView) -> IndexPath? {
		guard let object = CoreDataManager.managedObjectForModelIdentifier(identifier) as? Car else { return nil }

		return self.fetchedResultsController.indexPath(forObject: object)
	}

	func modelIdentifierForElement(at idx: IndexPath, in view: UIView) -> String? {
		let object = self.fetchedResultsController.object(at: idx)

		return CoreDataManager.modelIdentifierForManagedObject(object)
	}

	// MARK: - UITableViewDelegate

	override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
		return proposedDestinationIndexPath
	}

	override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
		return self.isEditing ? nil : indexPath
	}

	override func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
		editButtonItem.isEnabled = false
		hideHelp(true)
	}

	override func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
		checkEnableEditButton()
		updateHelp(true)
	}

	// MARK: - NSFetchedResultsControllerDelegate

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		self.tableView.beginUpdates()
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
		switch type {
        case .insert:
            self.tableView.insertSections(IndexSet(integer: sectionIndex), with: .fade)
        case .delete:
			self.tableView.deleteSections(IndexSet(integer: sectionIndex), with: .fade)
		case .move, .update:
			self.tableView.reloadSections(IndexSet(integer: sectionIndex), with: .fade)
		}
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: AnyObject, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
		guard !changeIsUserDriven else { return }

		switch type {
        case .insert:
			if let newIndexPath = newIndexPath {
				tableView.insertRows(at: [newIndexPath], with: .fade)
			}
        case .delete:
			if let indexPath = indexPath {
				tableView.deleteRows(at: [indexPath], with: .fade)
			}
        case .move:
			if let indexPath = indexPath, let newIndexPath = newIndexPath, indexPath != newIndexPath {
				tableView.deleteRows(at: [indexPath], with: .fade)
				tableView.insertRows(at: [newIndexPath], with: .fade)
			}
        case .update:
			if let indexPath = indexPath {
				tableView.reloadRows(at: [indexPath], with: .automatic)
			}
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		// FIXME: this seems to be necessary in iOS 10 (up to Beta 4)
		do {
			try fetchedResultsController.performFetch()
		} catch {
			// ignore
		}

		tableView.endUpdates()

		updateHelp(true)
		checkEnableEditButton()

		changeIsUserDriven = false
	}

	override func prepare(for segue: UIStoryboardSegue, sender: AnyObject?) {
		if let fuelEventController = segue.destination as? FuelEventController, let selection = tableView.indexPathForSelectedRow {
			let selectedCar = self.fetchedResultsController.object(at: selection)
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
		NotificationCenter.default.removeObserver(self)
	}
}
