//
//  FuelEventEditorController.swift
//  kraftstoff
//
//  Created by Ingmar Stein on 04.05.15.
//
//

import UIKit
import CoreData

private let SRFuelEventCancelSheet     = "FuelEventCancelSheet"
private let SRFuelEventDataChanged     = "FuelEventDataChanged"
private let SRFuelEventSelectionIndex  = "FuelEventMostSelectionIndex"
private let SRFuelEventEventID         = "FuelEventEventID"
private let SRFuelEventCarID           = "FuelEventCarID"
private let SRFuelEventDate            = "FuelEventDate"
private let SRFuelEventDistance        = "FuelEventDistance"
private let SRFuelEventPrice           = "FuelEventPrice"
private let SRFuelEventVolume          = "FuelEventVolume "
private let SRFuelEventFilledUp        = "FuelEventFilledUp"
private let SRFuelEventEditing         = "FuelEventEditing"
private let SRFuelEventComment         = "FuelEventComment"

final class FuelEventEditorController: PageViewController, UIViewControllerRestoration, NSFetchedResultsControllerDelegate, EditablePageCellDelegate, EditablePageCellValidator {

	var event: FuelEvent! {
		didSet {
			restoreStateFromEvent()
		}
	}
	var car: Car!
	var date: Date!
	var distance: NSDecimalNumber!
	var price: NSDecimalNumber!
	var fuelVolume: NSDecimalNumber!
	var filledUp = false
	var comment: String?

	var editButton: UIBarButtonItem!
	var cancelButton: UIBarButtonItem!
	var doneButton: UIBarButtonItem!

	private var isShowingCancelSheet = false
	private var dataChanged = false
	private var restoredSelectionIndex: IndexPath?

	// MARK: - View Lifecycle

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)

		self.restorationClass = type(of: self)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// Title bar
		self.editButton   = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(FuelEventEditorController.enterEditingMode(_:)))
		self.doneButton   = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(FuelEventEditorController.endEditingModeAndSave(_:)))
		self.cancelButton = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(FuelEventEditorController.endEditingModeAndRevert(_:)))

		self.editButton.accessibilityIdentifier = "edit"
		self.doneButton.accessibilityIdentifier = "done"
		self.cancelButton.accessibilityIdentifier = "cancel"

		self.title = Formatters.dateFormatter.string(from: self.event.ksTimestamp)
		self.navigationItem.rightBarButtonItem = self.editButton

		// Remove tint from navigation bar
		self.navigationController?.navigationBar.tintColor = nil

		// Table contents
		self.tableView.allowsSelection = false

		createTableContentsWithAnimation(.none)
		self.tableView.reloadData()

		NotificationCenter.default.addObserver(self, selector: #selector(FuelEventEditorController.localeChanged(_:)), name: NSLocale.currentLocaleDidChangeNotification, object: nil)
	}

	// MARK: - State Restoration

	static func viewController(withRestorationIdentifierPath identifierComponents: [Any], coder: NSCoder) -> UIViewController? {
		if let storyboard = coder.decodeObject(forKey: UIStateRestorationViewControllerStoryboardKey) as? UIStoryboard,
				let controller = storyboard.instantiateViewController(withIdentifier: "FuelEventEditor") as? FuelEventEditorController,
			let modelIdentifier = coder.decodeObject(of: NSString.self, forKey: SRFuelEventEventID) as String? {
			controller.event = CoreDataManager.managedObjectForModelIdentifier(modelIdentifier)

			if controller.event == nil {
				return nil
			}

			return controller
		}

		return nil
	}

	override func encodeRestorableState(with coder: NSCoder) {
		let indexPath = isShowingCancelSheet ? restoredSelectionIndex : self.tableView.indexPathForSelectedRow

		coder.encode(isShowingCancelSheet, forKey: SRFuelEventCancelSheet)
		coder.encode(dataChanged, forKey: SRFuelEventDataChanged)
		coder.encode(indexPath, forKey: SRFuelEventSelectionIndex)
		coder.encode(CoreDataManager.modelIdentifierForManagedObject(event) as NSString?, forKey: SRFuelEventEventID)
		coder.encode(CoreDataManager.modelIdentifierForManagedObject(car) as NSString?, forKey: SRFuelEventCarID)
		coder.encode(date, forKey: SRFuelEventDate)
		coder.encode(distance, forKey: SRFuelEventDistance)
		coder.encode(price, forKey: SRFuelEventPrice)
		coder.encode(fuelVolume, forKey: SRFuelEventVolume)
		coder.encode(filledUp, forKey: SRFuelEventFilledUp)
		coder.encode(comment as NSString?, forKey: SRFuelEventComment)
		coder.encode(self.isEditing, forKey: SRFuelEventEditing)

		super.encodeRestorableState(with: coder)
	}

	override func decodeRestorableState(with coder: NSCoder) {
		isShowingCancelSheet   = coder.decodeBool(forKey: SRFuelEventCancelSheet)
		dataChanged            = coder.decodeBool(forKey: SRFuelEventDataChanged)
		restoredSelectionIndex = coder.decodeObject(of: NSIndexPath.self, forKey: SRFuelEventSelectionIndex) as IndexPath?
		date                   = coder.decodeObject(of: NSDate.self, forKey: SRFuelEventDate) as Date?
		distance               = coder.decodeObject(of: NSDecimalNumber.self, forKey: SRFuelEventDistance)
		price                  = coder.decodeObject(of: NSDecimalNumber.self, forKey: SRFuelEventPrice)
		fuelVolume             = coder.decodeObject(of: NSDecimalNumber.self, forKey: SRFuelEventVolume)
		filledUp               = coder.decodeBool(forKey: SRFuelEventFilledUp)
		comment                = coder.decodeObject(of: NSString.self, forKey: SRFuelEventComment) as String?

		if let carId = coder.decodeObject(of: NSString.self, forKey: SRFuelEventCarID) as String? {
			car = CoreDataManager.managedObjectForModelIdentifier(carId)
		}

		if coder.decodeBool(forKey: SRFuelEventEditing) {
			setEditing(true, animated: false)

			if isShowingCancelSheet {
				showRevertActionSheet()
			} else {
				selectRowAtIndexPath(restoredSelectionIndex)
				restoredSelectionIndex = nil
			}
		}

		super.decodeRestorableState(with: coder)
	}

	// MARK: - Saving and Restoring the Fuel Event

	private func saveStateToEvent() {
		if dataChanged {
			dataChanged = false

			// Remove event from database
			CoreDataManager.removeEventFromArchive(event, forceOdometerUpdate: true)

			// Reinsert new version of event
			event = CoreDataManager.addToArchive(car: car,
                                                date: date,
                                            distance: distance,
                                               price: price,
                                          fuelVolume: fuelVolume,
                                            filledUp: filledUp,
									   	     comment: comment,
							     forceOdometerUpdate: true)

			CoreDataManager.saveContext()
		}
	}

	private func restoreStateFromEvent() {
		car = event.car

		let odometerUnit = car.ksOdometerUnit
		let fuelUnit     = car.ksFuelUnit

		self.title = Formatters.dateFormatter.string(from: event.ksTimestamp)
		date       = event.ksTimestamp
		distance   = Units.distanceForKilometers(event.ksDistance, withUnit: odometerUnit)
		price      = Units.pricePerUnit(event.ksPrice, withUnit: fuelUnit)
		fuelVolume = Units.volumeForLiters(event.ksFuelVolume, withUnit: fuelUnit)
		filledUp   = event.filledUp
		comment    = event.comment

		dataChanged = false
	}

	// MARK: - Mode Switching for Table Rows

	private func reconfigureRowAtIndexPath(_ indexPath: IndexPath) {
		if let cell = self.tableView.cellForRow(at: indexPath) as? PageCell, let cellData = dataForRow(indexPath.row, inSection: 0) {
			cell.configureForData(cellData,
                viewController: self,
                     tableView: self.tableView,
                     indexPath: indexPath)

			cell.setNeedsDisplay()
		}
    }

	override func setEditing(_ enabled: Bool, animated: Bool) {
		if self.isEditing != enabled {
			let animation: UITableViewRowAnimation = animated ? .fade : .none

			super.setEditing(enabled, animated: animated)

			if enabled {
				self.navigationItem.leftBarButtonItem  = self.doneButton
				self.navigationItem.rightBarButtonItem = self.cancelButton

				removeSectionAtIndex(1, withAnimation: animation)
			} else {
				self.navigationItem.leftBarButtonItem  = nil
				self.navigationItem.rightBarButtonItem = self.editButton

				createConsumptionRowWithAnimation(animation)
			}

			if animated {
				for row in 0...4 {
					reconfigureRowAtIndexPath(IndexPath(row: row, section: 0))
				}
			} else {
				self.tableView.reloadData()
			}

			self.tableView.allowsSelection = enabled
		}
	}

	// MARK: - Entering Editing Mode

	@IBAction func enterEditingMode(_ sender: AnyObject) {
		setEditing(true, animated: true)
		selectRowAtIndexPath(IndexPath(row: 0, section: 0))
	}

	// MARK: - Saving Edited Data

	@IBAction func endEditingModeAndSave(_ sender: AnyObject) {
		dismissKeyboardWithCompletion {
			self.saveStateToEvent()
			self.setEditing(false, animated: true)
		}
	}

	// MARK: - Aborting Editing Mode

	@IBAction func endEditingModeAndRevert(_ sender: AnyObject) {
		restoredSelectionIndex = self.tableView.indexPathForSelectedRow

		dismissKeyboardWithCompletion {
			if self.dataChanged {
				self.showRevertActionSheet()
			} else {
				self.endEditingModeAndRevertCompletion()
			}
		}
	}

	private func showRevertActionSheet() {
		let alertController = UIAlertController(title: NSLocalizedString("Revert Changes for Event?", comment: ""),
																			 message: nil,
																	  preferredStyle: .actionSheet)
		let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
			self.isShowingCancelSheet = false
			self.selectRowAtIndexPath(self.restoredSelectionIndex)
			self.restoredSelectionIndex = nil
		}
		let destructiveAction = UIAlertAction(title: NSLocalizedString("Revert", comment: ""), style: .destructive) { _ in
			self.isShowingCancelSheet = false
			self.endEditingModeAndRevertCompletion()
			self.restoredSelectionIndex = nil
		}

		alertController.addAction(cancelAction)
		alertController.addAction(destructiveAction)
		alertController.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem

		isShowingCancelSheet = true
		present(alertController, animated: true, completion: nil)
	}

	func endEditingModeAndRevertCompletion() {
		restoreStateFromEvent()
		setEditing(false, animated: true)

		restoredSelectionIndex = nil
	}

	// MARK: - Creating the Table Rows

	private func createConsumptionRowWithAnimation(_ animation: UITableViewRowAnimation) {
		// Don't add the section when no value can be computed
		if distance <= .zero || fuelVolume <= .zero {
			return
		}

		// Conversion units
		let odometerUnit    = car.ksOdometerUnit
		let fuelUnit        = car.ksFuelUnit
		let consumptionUnit = car.ksFuelConsumptionUnit

		// Compute the average consumption
		let cost = fuelVolume * price

		let liters      = Units.litersForVolume(fuelVolume, withUnit: fuelUnit)
		let kilometers  = Units.kilometersForDistance(distance, withUnit: odometerUnit)
		let consumption = Units.consumptionForKilometers(kilometers, liters: liters, inUnit: consumptionUnit)

		let consumptionString = "\(Formatters.currencyFormatter.string(from: cost)!) \(NSLocalizedString("/", comment: "")) \(Formatters.fuelVolumeFormatter.string(from: consumption)!) \(Formatters.shortMeasurementFormatter.string(from: consumptionUnit))"

		// Substrings for highlighting
		let highlightStrings = [Formatters.currencyFormatter.currencySymbol!,
                                  consumptionUnit.symbol]

		addSectionAtIndex(1, withAnimation: animation)

		addRowAtIndex(rowIndex: 0,
              inSection: 1,
              cellClass: ConsumptionTableCell.self,
               cellData: ["label": consumptionString,
                          "highlightStrings": highlightStrings],
          withAnimation: animation)
	}

	private func createTableContentsWithAnimation(_ animation: UITableViewRowAnimation) {
		addSectionAtIndex(0, withAnimation: animation)

		addRowAtIndex(rowIndex: 0,
              inSection: 0,
              cellClass: DateEditTableCell.self,
			   cellData: ["label": NSLocalizedString("Date", comment: ""),
                          "formatter": Formatters.dateTimeFormatter,
                          "valueIdentifier": "date"],
          withAnimation: animation)

		let odometerUnit = car.ksOdometerUnit

		addRowAtIndex(rowIndex: 1,
              inSection: 0,
              cellClass: NumberEditTableCell.self,
			   cellData: ["label": NSLocalizedString("Distance", comment: ""),
			              "suffix": " ".appending(Formatters.shortMeasurementFormatter.string(from: odometerUnit)),
                          "formatter": Formatters.distanceFormatter,
                          "valueIdentifier": "distance"],
          withAnimation: animation)

		let fuelUnit = car.ksFuelUnit

		addRowAtIndex(rowIndex: 2,
              inSection: 0,
              cellClass: NumberEditTableCell.self,
			   cellData: ["label": Units.fuelPriceUnitDescription(fuelUnit),
                          "formatter": Formatters.editPreciseCurrencyFormatter,
                          "alternateFormatter": Formatters.preciseCurrencyFormatter,
                          "valueIdentifier": "price"],
          withAnimation: animation)

		addRowAtIndex(rowIndex: 3,
              inSection: 0,
              cellClass: NumberEditTableCell.self,
               cellData: ["label": Units.fuelUnitDescription(fuelUnit, discernGallons: false, pluralization: true),
						  "suffix": " ".appending(Formatters.shortMeasurementFormatter.string(from: fuelUnit)),
                          "formatter": fuelUnit == UnitVolume.liters ? Formatters.fuelVolumeFormatter : Formatters.preciseFuelVolumeFormatter,
                          "valueIdentifier": "fuelVolume"],
          withAnimation: animation)

		addRowAtIndex(rowIndex: 4,
              inSection: 0,
              cellClass: SwitchTableCell.self,
			   cellData: ["label": NSLocalizedString("Full Fill-Up", comment: ""),
                          "valueIdentifier": "filledUp"],
          withAnimation: animation)

		addRowAtIndex(rowIndex: 5,
			inSection: 0,
			cellClass: TextEditTableCell.self,
			cellData: ["label": NSLocalizedString("Comment", comment: ""),
				 "valueIdentifier": "comment"],
			withAnimation: animation)

		if !self.isEditing {
			createConsumptionRowWithAnimation(animation)
		}
	}

	// MARK: - Locale Handling

	@objc func localeChanged(_ object: AnyObject) {
		let previousSelection = self.tableView.indexPathForSelectedRow

		dismissKeyboardWithCompletion {
			self.removeAllSectionsWithAnimation(.none)
			self.createTableContentsWithAnimation(.none)
			self.tableView.reloadData()

			self.selectRowAtIndexPath(previousSelection)
		}
	}

	// MARK: - Programmatically Selecting Table Rows

	private func textFieldAtIndexPath(_ indexPath: IndexPath) -> UITextField? {
		let cell = self.tableView.cellForRow(at: indexPath)!
		let field: UITextField?

		if let carCell = cell as? CarTableCell {
			field = carCell.textField
		} else if let dateCell = cell as? DateEditTableCell {
			field = dateCell.textField
		} else if let numberCell = cell as? NumberEditTableCell {
			field = numberCell.textField
		} else if let numberCell = cell as? TextEditTableCell {
			field = numberCell.textField
		} else {
			field = nil
		}
		return field
	}

	func activateTextFieldAtIndexPath(_ indexPath: IndexPath) {
		if let field = textFieldAtIndexPath(indexPath) {
			field.isUserInteractionEnabled = true
			field.becomeFirstResponder()
			DispatchQueue.main.async {
				self.tableView.beginUpdates()
				self.tableView.endUpdates()
			}
		}
	}

	private func selectRowAtIndexPath(_ path: IndexPath?) {
		if let path = path {
			self.tableView.selectRow(at: path, animated: false, scrollPosition: .none)
			self.tableView(self.tableView, didSelectRowAt: path)
		}
	}

	// MARK: - EditablePageCellDelegate

	func valueForIdentifier(_ valueIdentifier: String) -> Any? {
		switch valueIdentifier {
			case "date": return date
			case "distance": return distance
			case "price": return price
			case "fuelVolume": return fuelVolume
			case "filledUp": return filledUp
			case "comment": return comment
			case "showValueLabel": return !self.isEditing
			default: return nil
		}
	}

	func valueChanged(_ newValue: Any?, identifier valueIdentifier: String) {
		if valueIdentifier == "date" {
			if let dateValue = newValue as? Date {
				let newDate = Date.dateWithoutSeconds(dateValue)

				if date != newDate {
					date = newDate
					dataChanged = true
				}
			}
		} else if let newNumber = newValue as? NSDecimalNumber {
			if valueIdentifier == "distance" {
				if distance != newNumber {
					distance = newNumber
					dataChanged = true
				}
			} else if valueIdentifier == "price" {
				if price != newNumber {
					price = newNumber
					dataChanged = true
				}
			} else if valueIdentifier == "fuelVolume" {
				if fuelVolume != newNumber {
					fuelVolume = newNumber
					dataChanged = true
				}
			}
		} else if valueIdentifier == "filledUp" {
			if let newBoolValue = newValue as? Bool {
				if filledUp != newBoolValue {
					filledUp = newBoolValue
					dataChanged = true
				}
			}
		} else if valueIdentifier == "comment" {
			if let newValue = newValue as? String {
				if comment != newValue {
					comment = newValue
					dataChanged = true
				}
			}
		}

		// Validation of Done button
		var canBeSaved = true

		if !(distance > .zero && fuelVolume > .zero) {
			canBeSaved = false
		} else if date != event.ksTimestamp {
			if CoreDataManager.containsEventWithCar(car, andDate: date) {
				canBeSaved = false
			}
		}

		self.doneButton.isEnabled = canBeSaved
	}

	// MARK: - EditablePageCellValidator

	func valueValid(_ newValue: Any?, identifier valueIdentifier: String) -> Bool {
		// Date must be collision free
		if let date = newValue as? Date {
			if valueIdentifier == "date" {
				if date != event.ksTimestamp {
					if CoreDataManager.containsEventWithCar(car, andDate: date) {
						return false
					}
				}
			}
		}

		// DecimalNumbers <= 0.0 are invalid
		if let decimalNumber = newValue as? NSDecimalNumber {
			if valueIdentifier != "price" {
				if decimalNumber <= .zero {
					return false
				}
			}
		}

		return true
	}

	// MARK: - UITableViewDataSource

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return nil
	}

	// MARK: - UITableViewDelegate

	override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
		let cell = tableView.cellForRow(at: indexPath)

		if cell is SwitchTableCell || cell is ConsumptionTableCell {
			return nil
		} else {
			return indexPath
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		activateTextFieldAtIndexPath(indexPath)
		tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
	}

	override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
		if let field = textFieldAtIndexPath(indexPath) {
			field.resignFirstResponder()
			DispatchQueue.main.async {
				tableView.beginUpdates()
				tableView.endUpdates()
			}
		}
	}

	// MARK: - Memory Management

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}
