//
//  FuelCalculatorController.swift
//  kraftstoff
//
//  Created by Ingmar Stein on 04.05.15.
//
//

import UIKit
import CoreData

private struct FuelCalculatorDataRow: OptionSet {
	let rawValue: UInt

	static let Distance = FuelCalculatorDataRow(rawValue: 0b0001)
	static let Price = FuelCalculatorDataRow(rawValue: 0b0010)
	static let Amount = FuelCalculatorDataRow(rawValue: 0b0100)
	static let All = FuelCalculatorDataRow(rawValue: 0b0111)
}

final class FuelCalculatorController: PageViewController, NSFetchedResultsControllerDelegate, EditablePageCellDelegate, EditablePageCellValidator {

	var changeIsUserDriven = false
	var isShowingConvertSheet = false
	var selectedCarId : String?

	private var _fetchedResultsController: NSFetchedResultsController?
	private var fetchedResultsController: NSFetchedResultsController {
		if _fetchedResultsController == nil {
			let fetchedResultsController = CoreDataManager.fetchedResultsControllerForCars()
			fetchedResultsController.delegate = self
			_fetchedResultsController = fetchedResultsController
		}
		return _fetchedResultsController!
	}

	var restoredSelectionIndex: NSIndexPath?
	var car: Car?
	var date: NSDate?
	var lastChangeDate: NSDate?
	var distance: NSDecimalNumber?
	var price: NSDecimalNumber?
	var fuelVolume: NSDecimalNumber?
	var filledUp: Bool?
	var comment: String?

	var doneButton: UIBarButtonItem!
	var saveButton: UIBarButtonItem!

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)

		userActivity = NSUserActivity(activityType: "com.github.m-schmidt.Kraftstoff.fillup")
		userActivity?.title = NSLocalizedString("Fill-Up", comment:"")
		userActivity?.keywords = [ NSLocalizedString("Fill-Up", comment:"") ]
		userActivity?.isEligibleForSearch = true

		// Title bar
		self.doneButton = UIBarButtonItem(barButtonSystemItem: .done, target:self, action:#selector(FuelCalculatorController.endEditingMode(_:)))
		self.doneButton.accessibilityIdentifier = "done"
		self.saveButton = UIBarButtonItem(barButtonSystemItem: .save, target:self, action:#selector(FuelCalculatorController.saveAction(_:)))
		self.saveButton.accessibilityIdentifier = "save"
		self.title = NSLocalizedString("Fill-Up", comment:"")
	}

	//MARK: - View Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()

		// Remove tint from navigation bar
		self.navigationController?.navigationBar.tintColor = nil

		// Table contents
		createTableContentsWithAnimation(.none)
		self.tableView.reloadData()
		updateSaveButtonState()

		NSNotificationCenter.default().addObserver(self, selector:#selector(FuelCalculatorController.localeChanged(_:)), name:NSCurrentLocaleDidChangeNotification, object:nil)
		NSNotificationCenter.default().addObserver(self, selector:#selector(FuelCalculatorController.willEnterForeground(_:)), name:UIApplicationWillEnterForegroundNotification, object:nil)
		NSNotificationCenter.default().addObserver(self, selector:#selector(FuelCalculatorController.storesDidChange(_:)), name: NSPersistentStoreCoordinatorStoresDidChangeNotification, object: CoreDataManager.managedObjectContext.persistentStoreCoordinator!)
	}

	//MARK: - State Restoration

	private let kSRCalculatorSelectedIndex = "FuelCalculatorSelectedIndex"
	private let kSRCalculatorConvertSheet  = "FuelCalculatorConvertSheet"
	private let kSRCalculatorEditing       = "FuelCalculatorEditing"

	override func encodeRestorableState(with coder: NSCoder) {
		if let indexPath = self.restoredSelectionIndex ?? self.tableView.indexPathForSelectedRow {
			coder.encode(indexPath, forKey: kSRCalculatorSelectedIndex)
		}

		coder.encode(isShowingConvertSheet, forKey:kSRCalculatorConvertSheet)
		coder.encode(self.isEditing, forKey:kSRCalculatorEditing)

		super.encodeRestorableState(with: coder)
	}

	override func decodeRestorableState(with coder: NSCoder) {
		self.restoredSelectionIndex = coder.decodeObjectOfClass(NSIndexPath.self, forKey: kSRCalculatorSelectedIndex)
		self.isShowingConvertSheet = coder.decodeBool(forKey: kSRCalculatorConvertSheet)
    
		if coder.decodeBool(forKey: kSRCalculatorEditing) {
			self.setEditing(true, animated:false)

			if isShowingConvertSheet {
				showOdometerConversionAlert()
			} else {
				selectRowAtIndexPath(self.restoredSelectionIndex)
				self.restoredSelectionIndex = nil
			}
		}

		super.decodeRestorableState(with: coder)
	}

	//MARK: - Modeswitching for Table Rows

	override func setEditing(_ enabled: Bool, animated: Bool) {
		if self.isEditing != enabled {

			let animation: UITableViewRowAnimation = animated ? .fade : .none
        
			super.setEditing(enabled, animated:animated)
        
			if enabled {
				self.navigationItem.leftBarButtonItem = self.doneButton
				self.navigationItem.rightBarButtonItem = nil

				removeSectionAtIndex(1, withAnimation:animation)
			} else {
				self.navigationItem.leftBarButtonItem = nil
            
				if consumptionRowNeeded() {
					createConsumptionRowWithAnimation(animation)
				}

				updateSaveButtonState()
			}
        
			if !animated {
				self.tableView.reloadData()
			}
		}
	}

	//MARK: - Shake Events

	override func canBecomeFirstResponder() -> Bool {
		return true
	}

	override func motionEnded(_ motion: UIEventSubtype, with event: UIEvent?)	{
		if motion == .motionShake {
			handleShake()
		} else {
			super.motionEnded(motion, with: event)
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		self.userActivity?.becomeCurrent()
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)

		userActivity?.resignCurrent()
	}

	func handleShake() {
		if self.isEditing {
			return
		}

		let zero = NSDecimalNumber.zero()

		if (distance == nil || distance! == zero) && (fuelVolume == nil || fuelVolume! == zero) && (price == nil || price! == zero) {
			return
		}

		UIView.animate(withDuration: 0.3,
                     animations: {
                         self.removeSectionAtIndex(1, withAnimation: .fade)
                     }, completion: { finished in

                         let now = NSDate()

                         self.valueChanged(NSDate.dateWithoutSeconds(date: now), identifier:"date")
                         self.valueChanged(now,  identifier:"lastChangeDate")
                         self.valueChanged(zero, identifier:"distance")
                         self.valueChanged(zero, identifier:"price")
                         self.valueChanged(zero, identifier:"fuelVolume")
                         self.valueChanged(true, identifier:"filledUp")
						 self.valueChanged("", identifier:"comment")

                         self.recreateTableContentsWithAnimation(.left)
                         self.updateSaveButtonState()
                     })
	}

	//MARK: - Creating the Table Rows

	func consumptionRowNeeded() -> Bool {

		if self.isEditing {
			return false
		}

		let zero = NSDecimalNumber.zero()

		if (distance == nil || distance! <= zero) || (fuelVolume == nil || fuelVolume! <= zero) {
			return false
		}

		return true
	}

	func createConsumptionRowWithAnimation(_ animation: UITableViewRowAnimation) {
		// Conversion units
		let odometerUnit: KSDistance
		let fuelUnit: KSVolume
		let consumptionUnit: KSFuelConsumption

		if let car = self.car {
			odometerUnit    = car.ksOdometerUnit
			fuelUnit        = car.ksFuelUnit
			consumptionUnit = car.ksFuelConsumptionUnit
		} else {
			odometerUnit    = Units.distanceUnitFromLocale
			fuelUnit        = Units.volumeUnitFromLocale
			consumptionUnit = Units.fuelConsumptionUnitFromLocale
		}

		// Compute the average consumption
		let cost = fuelVolume! * price!

		let liters      = Units.litersForVolume(fuelVolume!, withUnit:fuelUnit)
		let kilometers  = Units.kilometersForDistance(distance!, withUnit:odometerUnit)
		let consumption = Units.consumptionForKilometers(kilometers, liters:liters, inUnit:consumptionUnit)

		let consumptionString = String(format:"%@ %@ %@ %@",
                                        Formatters.sharedCurrencyFormatter.string(from: cost)!,
										NSLocalizedString("/", comment:""),
                                        Formatters.sharedFuelVolumeFormatter.string(from: consumption)!,
                                        consumptionUnit.localizedString)


		// Substrings for highlighting
		let highlightStrings = [Formatters.sharedCurrencyFormatter.currencySymbol!,
								consumptionUnit.localizedString]

		addSectionAtIndex(1, withAnimation:animation)

		addRowAtIndex(rowIndex: 0,
              inSection:1,
              cellClass:ConsumptionTableCell.self,
               cellData:["label":consumptionString,
                         "highlightStrings":highlightStrings],
          withAnimation:animation)
	}

	private func createDataRows(_ rowMask: FuelCalculatorDataRow, withAnimation animation: UITableViewRowAnimation) {
		let odometerUnit: KSDistance
		let fuelUnit: KSVolume

		if let car = self.car {
			odometerUnit = car.ksOdometerUnit
			fuelUnit     = car.ksFuelUnit
		} else {
			odometerUnit = Units.distanceUnitFromLocale
			fuelUnit     = Units.volumeUnitFromLocale
		}

		let rowOffset = (self.fetchedResultsController.fetchedObjects!.count < 2) ? 1 : 2

		if rowMask.contains(.Distance) {
			if self.distance == nil {
				self.distance = NSDecimalNumber(decimal: (NSUserDefaults.standard().object(forKey: "recentDistance")! as! NSNumber).decimalValue)
			}

			addRowAtIndex(rowIndex: 0 + rowOffset,
                  inSection:0,
                  cellClass:NumberEditTableCell.self,
				   cellData:["label": NSLocalizedString("Distance", comment:""),
                             "suffix": " ".appending(odometerUnit.description),
                             "formatter": Formatters.sharedDistanceFormatter,
                             "valueIdentifier": "distance"],
              withAnimation:animation)
		}

		if rowMask.contains(.Price) {
			if self.price == nil {
				self.price = NSDecimalNumber(decimal: (NSUserDefaults.standard().object(forKey: "recentPrice")! as! NSNumber).decimalValue)
			}

			addRowAtIndex(rowIndex: 1 + rowOffset,
                  inSection:0,
                  cellClass:NumberEditTableCell.self,
                   cellData:["label": Units.fuelPriceUnitDescription(fuelUnit),
							 "formatter": Formatters.sharedEditPreciseCurrencyFormatter,
                             "alternateFormatter": Formatters.sharedPreciseCurrencyFormatter,
                             "valueIdentifier": "price"],
              withAnimation:animation)
		}

		if rowMask.contains(.Amount) {
			if self.fuelVolume == nil {
				self.fuelVolume = NSDecimalNumber(decimal: (NSUserDefaults.standard().object(forKey: "recentFuelVolume")! as! NSNumber).decimalValue)
			}

			addRowAtIndex(rowIndex: 2 + rowOffset,
                  inSection:0,
                  cellClass:NumberEditTableCell.self,
                   cellData:["label": Units.fuelUnitDescription(fuelUnit, discernGallons:false, pluralization:true),
                             "suffix": " ".appending(fuelUnit.description),
                             "formatter": fuelUnit.isMetric
                                                ? Formatters.sharedFuelVolumeFormatter
                                                : Formatters.sharedPreciseFuelVolumeFormatter,
                             "valueIdentifier": "fuelVolume"],
              withAnimation:animation)
		}
	}

	private func createTableContentsWithAnimation(_ animation: UITableViewRowAnimation) {
		addSectionAtIndex(0, withAnimation:animation)

		// Car selector (optional)
		self.car = nil

		if self.fetchedResultsController.fetchedObjects?.count ?? 0 > 0 {
			if let selectedCar = selectedCarId {
				self.car = CoreDataManager.managedObjectForModelIdentifier(selectedCar) as? Car
			} else if let preferredCar = NSUserDefaults.standard().string(forKey: "preferredCarID") {
				self.car = CoreDataManager.managedObjectForModelIdentifier(preferredCar) as? Car
			}

			if self.car == nil {
				self.car = self.fetchedResultsController.fetchedObjects!.first as? Car
			}

			if self.fetchedResultsController.fetchedObjects!.count > 1 {
				addRowAtIndex(rowIndex: 0,
                      inSection:0,
                      cellClass:CarTableCell.self,
					   cellData:["label": NSLocalizedString("Car", comment:""),
                                 "valueIdentifier": "car",
                                 "fetchedObjects": self.fetchedResultsController.fetchedObjects!],
                  withAnimation:animation)
			}
		}


		// Date selector
		if self.date == nil {
			self.date = NSDate.dateWithoutSeconds(date: NSDate())
		}

		if self.lastChangeDate == nil {
			self.lastChangeDate = NSDate()
		}

		addRowAtIndex(rowIndex: self.car != nil ? 1 : 0,
              inSection:0,
              cellClass:DateEditTableCell.self,
			   cellData:["label": NSLocalizedString("Date", comment:""),
                         "formatter": Formatters.sharedDateTimeFormatter,
                         "valueIdentifier": "date",
                         "valueTimestamp": "lastChangeDate",
                         "autorefresh": true],
          withAnimation:animation)

		// Data rows for distance, price, fuel amount
		createDataRows(.All, withAnimation:animation)

		// Full-fillup selector
		self.filledUp = NSUserDefaults.standard().bool(forKey: "recentFilledUp")

		if self.car != nil {
			addRowAtIndex(rowIndex: 5,
                  inSection:0,
                  cellClass:SwitchTableCell.self,
				   cellData:["label": NSLocalizedString("Full Fill-Up", comment:""),
                             "valueIdentifier": "filledUp"],
              withAnimation:animation)

			if self.comment == nil {
				self.comment = NSUserDefaults.standard().string(forKey: "recentComment")!
			}

			addRowAtIndex(rowIndex: 6,
				inSection:0,
				cellClass:TextEditTableCell.self,
				cellData:["label": NSLocalizedString("Comment", comment:""),
					"valueIdentifier": "comment",
					"maximumTextFieldLength": 0],
				withAnimation:animation)
		}

		// Consumption info (optional)
		if consumptionRowNeeded() {
			createConsumptionRowWithAnimation(animation)
		}
	}

	//MARK: - Updating the Table Rows

	func recreateTableContentsWithAnimation(_ anim: UITableViewRowAnimation) {
		// Update model contents
		let animation: UITableViewRowAnimation
		if tableSections.isEmpty {
			animation = .none
		} else {
			animation = anim
			removeAllSectionsWithAnimation(.none)
		}

		createTableContentsWithAnimation(.none)

		// Update the tableview
		if animation == .none {
			self.tableView?.reloadData()
		} else {
			self.tableView?.reloadSections(NSIndexSet(indexesIn: NSRange(location: 0, length: self.tableView.numberOfSections)),
                      with:animation)
		}
	}

	private func recreateDataRowsWithPreviousCar(_ oldCar: Car?) {
		// Replace data rows in the internal data model
		for row in 2...4 {
			removeRow(at: row, inSection:0, withAnimation: .none)
		}

		createDataRows(.All, withAnimation: .none)

		// Update the tableview
		let odoChanged = oldCar == nil || oldCar!.odometerUnit != self.car!.odometerUnit

		let fuelChanged = oldCar == nil || oldCar!.ksFuelUnit.isMetric != self.car!.ksFuelUnit.isMetric

		var count = 0

		for row in 2...4 {
			let animation: UITableViewRowAnimation
			if (row == 2 && odoChanged) || (row != 2 && fuelChanged) {
				animation = (count % 2) == 0 ? .right : .left
				count += 1
			} else {
				animation = .none
			}

			self.tableView.reloadRows(at: [NSIndexPath(forRow:row, inSection:0)], with:animation)
		}

		// Reload date row too to get colors updates
		self.tableView.reloadRows(at: [NSIndexPath(forRow:1, inSection:0)], with: .none)
	}

	private func recreateDistanceRowWithAnimation(_ animation: UITableViewRowAnimation) {
		let rowOffset = (self.fetchedResultsController.fetchedObjects!.count < 2) ? 1 : 2

		// Replace distance row in the internal data model
		removeRow(at: rowOffset, inSection:0, withAnimation: .none)
		createDataRows(.Distance, withAnimation: .none)

		// Update the tableview
		if animation != .none {
			self.tableView.reloadRows(at: [NSIndexPath(forRow:rowOffset, inSection:0)], with: animation)
		} else {
			self.tableView.reloadData()
		}
	}

	//MARK: - Locale Handling

	func localeChanged(_ object: AnyObject) {
		let previousSelection = self.tableView.indexPathForSelectedRow
    
		dismissKeyboardWithCompletion {
			self.recreateTableContentsWithAnimation(.none)
			self.selectRowAtIndexPath(previousSelection)
		}
	}

	//MARK: - System Events

	func willEnterForeground(_ notification: NSNotification) {
		if tableSections.isEmpty {
			return
		}

		// Last update must be longer than 5 minutes ago
		let noChangeInterval: NSTimeInterval

		if let lastChangeDate = self.lastChangeDate {
			noChangeInterval = NSDate().timeIntervalSince(lastChangeDate)
		} else {
			noChangeInterval = -1
		}

		if self.lastChangeDate == nil || noChangeInterval >= 300 || noChangeInterval < 0 {

			// Reset date to current time
			let now = NSDate()
			self.date = NSDate.dateWithoutSeconds(date: now)
			self.lastChangeDate = now

			// Update table
			let rowOffset = (self.fetchedResultsController.fetchedObjects?.count ?? 0 < 2) ? 0 : 1

			self.tableView.reloadRows(at: [NSIndexPath(forRow:rowOffset, inSection:0)], with: .none)
		}
	}

	func storesDidChange(_ notification: NSNotification) {
		_fetchedResultsController = nil
		NSFetchedResultsController.deleteCache(withName: nil)
		recreateTableContentsWithAnimation(.none)
		updateSaveButtonState()
	}

	//MARK: - Programmatically Selecting Table Rows

	private func textFieldAtIndexPath(_ indexPath: NSIndexPath) -> UITextField? {
		let cell = self.tableView.cellForRow(at: indexPath)!
		let field : UITextField?

		if let carCell = cell as? CarTableCell {
			field = carCell.textField
		} else if let dateCell = cell as? DateEditTableCell {
			field = dateCell.textField
		} else if let numberCell = cell as? NumberEditTableCell {
			field = numberCell.textField
		} else if let textCell = cell as? TextEditTableCell {
			field = textCell.textField
		} else {
			field = nil
		}
		return field
	}

	private func activateTextFieldAtIndexPath(_ indexPath: NSIndexPath) {
		if let field = textFieldAtIndexPath(indexPath) {
			field.isUserInteractionEnabled = true
			field.becomeFirstResponder()
			dispatch_async(dispatch_get_main_queue()) {
				self.tableView.beginUpdates()
				self.tableView.endUpdates()
			}
		}
	}

	private func selectRowAtIndexPath(_ indexPath: NSIndexPath?) {
		if let path = indexPath {
			self.tableView.selectRow(at: path, animated:false, scrollPosition: .none)
			self.tableView(self.tableView, didSelectRowAt:path)
		}
	}

	//MARK: - Storing Information in the Database

	func saveAction(_ sender: AnyObject) {
		self.navigationItem.rightBarButtonItem = nil
        
		UIView.animate(withDuration: 0.3,
                     animations: {
                         // Remove consumption row
                         self.removeSectionAtIndex(1, withAnimation: .fade)
                     },
                     completion: { finished in
                         // Add new event object
                         self.changeIsUserDriven = true

                         CoreDataManager.addToArchive(car: self.car!,
                                                     date: self.date!,
                                                 distance: self.distance!,
                                                    price: self.price!,
                                               fuelVolume: self.fuelVolume!,
                                                 filledUp: self.filledUp ?? false,
												  comment: self.comment,
                                      forceOdometerUpdate: false)

                         // Reset calculator table
                         let zero = NSDecimalNumber.zero()

                         self.valueChanged(zero, identifier:"distance")
                         self.valueChanged(zero, identifier:"price")
                         self.valueChanged(zero, identifier:"fuelVolume")
                         self.valueChanged(true, identifier:"filledUp")
						 self.valueChanged("", identifier:"comment")

						 CoreDataManager.saveContext()
                     })
	}

	private func updateSaveButtonState() {
		var saveValid = true

		if self.car == nil {
			saveValid = false
		} else if (distance == nil || distance! == NSDecimalNumber.zero()) || (fuelVolume == nil || fuelVolume! == NSDecimalNumber.zero()) {
			saveValid = false
		} else if date == nil || CoreDataManager.containsEventWithCar(self.car!, andDate:self.date!) {
			saveValid = false
		}

		self.navigationItem.rightBarButtonItem = saveValid ? self.saveButton : nil
	}


	//MARK: - Conversion for Odometer

	// A simple heuristic when to ask for distance conversion
	func needsOdometerConversionSheet() -> Bool {
		guard let car = self.car else { return false }
		guard let distance = self.distance else { return false }

		guard car.odometer != NSDecimalNumber.notANumber() else { return false }

		// 1.) entered "distance" must be larger than car odometer
		let odometerUnit = car.ksOdometerUnit

		let rawDistance  = Units.kilometersForDistance(distance, withUnit:odometerUnit)
		let convDistance = rawDistance - car.odometer
    
		if convDistance <= NSDecimalNumber.zero() {
			return false
		}
    
		// 2.) consumption with converted distances is more 'logical'
		let liters = Units.litersForVolume(fuelVolume!, withUnit:car.ksFuelUnit)
    
		if liters <= NSDecimalNumber.zero() {
			return false
		}

		let rawConsumption = Units.consumptionForKilometers(rawDistance,
                                                                      liters: liters,
                                                                      inUnit: .litersPer100km)

		if rawConsumption == NSDecimalNumber.notANumber() {
			return false
		}

		let convConsumption = Units.consumptionForKilometers(convDistance,
                                                                      liters: liters,
                                                                      inUnit: .litersPer100km)
    
		if convConsumption == NSDecimalNumber.notANumber() {
			return false
		}

		let avgConsumption = Units.consumptionForKilometers(car.distanceTotalSum,
                                                                     liters: car.fuelVolumeTotalSum,
                                                                     inUnit: .litersPer100km)
    
		let loBound: NSDecimalNumber
		let hiBound: NSDecimalNumber

		if avgConsumption == NSDecimalNumber.notANumber() {
			loBound = NSDecimalNumber(mantissa: 2, exponent:0, isNegative:false)
			hiBound = NSDecimalNumber(mantissa:20, exponent:0, isNegative:false)
		} else {
			loBound = avgConsumption * NSDecimalNumber(mantissa:5, exponent: -1, isNegative:false)
			hiBound = avgConsumption * NSDecimalNumber(mantissa:5, exponent:  0, isNegative:false)
		}
    
		// conversion only when rawConsumption <= lowerBound
		if rawConsumption > loBound {
			return false
		}

		// conversion only when lowerBound <= convConversion <= highBound
		if convConsumption < loBound || convConsumption > hiBound {
			return false
		}
    
		// 3.) the event must be the youngest one
		let youngerEvents = CoreDataManager.objectsForFetchRequest(CoreDataManager.fetchRequestForEvents(car: car,
																								afterDate:self.date!,
																							  dateMatches:false))
    
		if youngerEvents.count > 0 {
			return false
		}
    
		// => ask for a conversion
		return true
	}

	func showOdometerConversionAlert() {
		let odometerUnit = self.car!.ksOdometerUnit
		let rawDistance  = Units.kilometersForDistance(self.distance!, withUnit:odometerUnit)
		let convDistance = rawDistance - self.car!.odometer

		let distanceFormatter = Formatters.sharedDistanceFormatter

		let rawButton = String(format: "%@ %@",
                                distanceFormatter.string(from: Units.distanceForKilometers(rawDistance, withUnit:odometerUnit))!,
                                odometerUnit.description)

		let convButton = String(format:"%@ %@",
                                distanceFormatter.string(from: Units.distanceForKilometers(convDistance, withUnit:odometerUnit))!,
								odometerUnit.description)

		let alertController = UIAlertController(title:NSLocalizedString("Convert from odometer reading into distance? Please choose the distance driven:", comment:""),
																			 message: nil,
																	  preferredStyle: .actionSheet)
		let cancelAction = UIAlertAction(title:rawButton, style: .`default`) { _ in
			self.isShowingConvertSheet = false
			self.setEditing(false, animated:true)
		}

		let destructiveAction = UIAlertAction(title:convButton, style: .destructive) { _ in
			self.isShowingConvertSheet = false

			// Replace distance in table with difference to car odometer
			let odometerUnit = self.car!.ksOdometerUnit
			let rawDistance  = Units.kilometersForDistance(self.distance!, withUnit:odometerUnit)
			let convDistance = rawDistance - self.car!.odometer

			self.distance = Units.distanceForKilometers(convDistance, withUnit:odometerUnit)
			self.valueChanged(self.distance, identifier:"distance")

			self.recreateDistanceRowWithAnimation(.right)

			self.setEditing(false, animated:true)
		}

		alertController.addAction(cancelAction)
		alertController.addAction(destructiveAction)
		alertController.popoverPresentationController?.barButtonItem = self.navigationItem.leftBarButtonItem
		isShowingConvertSheet = true
		present(alertController, animated:true, completion:nil)
	}

	//MARK: - Leaving Editing Mode

	@IBAction func endEditingMode(_ sender: AnyObject) {
		dismissKeyboardWithCompletion {
			if self.needsOdometerConversionSheet() {
				self.showOdometerConversionAlert()
			} else {
				self.setEditing(false, animated:true)
			}
		}
    }

	//MARK: - EditablePageCellDelegate

	func valueForIdentifier(_ valueIdentifier: String) -> AnyObject? {
		switch valueIdentifier {
		case "car": return self.car
		case "date": return self.date
		case "lastChangeDate": return self.lastChangeDate
		case "distance": return self.distance
		case "price": return self.price
		case "fuelVolume": return self.fuelVolume
		case "filledUp": return self.filledUp
		case "comment": return self.comment
		default: return nil
		}
	}

	func valueChanged(_ newValue: AnyObject?, identifier valueIdentifier: String) {
		if let date = newValue as? NSDate {

			if valueIdentifier == "date" {
				self.date = NSDate.dateWithoutSeconds(date: date)
			} else if valueIdentifier == "lastChangeDate" {
				self.lastChangeDate = date
			}

		} else if let decimalNumber = newValue as? NSDecimalNumber {
			let recentKey: String?

			if valueIdentifier == "distance" {
				self.distance = decimalNumber
				recentKey = "recentDistance"
			} else if valueIdentifier == "fuelVolume" {
				self.fuelVolume = decimalNumber
				recentKey = "recentFuelVolume"
			} else if valueIdentifier == "price" {
				self.price = decimalNumber
				recentKey = "recentPrice"
			} else {
				recentKey = nil
			}

			if let recentKey = recentKey {
				let defaults = NSUserDefaults.standard()

				defaults.set(newValue, forKey:recentKey)
				defaults.synchronize()
			}

		} else if valueIdentifier == "filledUp" {
			self.filledUp = newValue!.boolValue

			let defaults = NSUserDefaults.standard()

			defaults.set(newValue, forKey:"recentFilledUp")
			defaults.synchronize()

		} else if valueIdentifier == "comment" {
			comment = newValue as? String

			let defaults = NSUserDefaults.standard()

			defaults.set(newValue, forKey:"recentComment")
			defaults.synchronize()

		} else if valueIdentifier == "car" {
			if self.car == nil || !self.car!.isEqual(newValue) {
				let oldCar = self.car
				self.car = newValue as? Car
				recreateDataRowsWithPreviousCar(oldCar)
			}

			if !self.car!.objectID.isTemporaryID {
				let defaults = NSUserDefaults.standard()

				defaults.set(CoreDataManager.modelIdentifierForManagedObject(self.car!), forKey:"preferredCarID")
				defaults.synchronize()
			}
		}
	}

	// MARK: - EditablePageCellValidator

	func valueValid(_ newValue: AnyObject?, identifier valueIdentifier: String) -> Bool {
		// Validate only when there is a car for saving
		guard let car = self.car else { return true }

		// Date must be collision free
		if let date = newValue as? NSDate {
			if valueIdentifier == "date" {
				if CoreDataManager.containsEventWithCar(car, andDate:date) {
					return false
				}
			}
		}

		// DecimalNumbers <= 0.0 are invalid
		if let decimalNumber = newValue as? NSDecimalNumber {
			if valueIdentifier != "price" {
				if decimalNumber <= NSDecimalNumber.zero() {
					return false
				}
			}
		}

		return true
	}

	//MARK: - NSFetchedResultsControllerDelegate

	@objc(controllerDidChangeContent:) func controllerDidChangeContent(_ controller: NSFetchedResultsController) {
		recreateTableContentsWithAnimation(changeIsUserDriven ? .right : .none)
		updateSaveButtonState()

		changeIsUserDriven = false
	}

	//MARK: - UITableViewDataSource

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return nil
	}

	//MARK: - UITableViewDelegate

	override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: NSIndexPath) -> NSIndexPath? {
		let cell = tableView.cellForRow(at: indexPath)

		if cell is SwitchTableCell || cell is ConsumptionTableCell {
			return nil
		}

		setEditing(true, animated:true)
		return indexPath
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: NSIndexPath) {
		activateTextFieldAtIndexPath(indexPath)
		tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
	}

	override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: NSIndexPath) {
		if let field = textFieldAtIndexPath(indexPath) {
			field.resignFirstResponder()
			dispatch_async(dispatch_get_main_queue()) {
				tableView.beginUpdates()
				tableView.endUpdates()
			}
		}
	}

	//MARK: -

	deinit {
		NSNotificationCenter.default().removeObserver(self)
	}

}
