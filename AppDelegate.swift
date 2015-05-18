//
//  AppDelegate.swift
//  kraftstoff
//
//  Created by Ingmar Stein on 05.05.15.
//
//

import UIKit
import CoreData

let kraftstoffDeviceShakeNotification = "kraftstoffDeviceShakeNotification"

extension UIApplication {
	static var kraftstoffAppDelegate: AppDelegate {
		return sharedApplication().delegate as! AppDelegate
	}
}

@UIApplicationMain
public final class AppDelegate: NSObject, UIApplicationDelegate {
	public var window: UIWindow?

	// CoreData support
	static let managedObjectContext: NSManagedObjectContext! = {
		let managedObjectContext = NSManagedObjectContext(concurrencyType:.MainQueueConcurrencyType)
		managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator
		managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
		return managedObjectContext
	}()

	private static let managedObjectModel: NSManagedObjectModel = {
		let modelPath = NSBundle.mainBundle().pathForResource("Kraftstoffrechner", ofType:"momd")!
		return NSManagedObjectModel(contentsOfURL:NSURL(fileURLWithPath: modelPath)!)!
	}()

	private static let localStoreURL = NSURL(fileURLWithPath:applicationDocumentsDirectory)!.URLByAppendingPathComponent("Kraftstoffrechner.sqlite")
	private static let iCloudStoreURL = NSURL(fileURLWithPath:applicationDocumentsDirectory)!.URLByAppendingPathComponent("Fuel.sqlite")

	private static let iCloudStoreOptions = [
		NSMigratePersistentStoresAutomaticallyOption: true,
		NSInferMappingModelAutomaticallyOption: true,
		NSPersistentStoreUbiquitousContentNameKey: "Kraftstoff"
	]

	private static let persistentStoreCoordinator: NSPersistentStoreCoordinator = {
		var error: NSError?

		let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel:managedObjectModel)

		if persistentStoreCoordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration:nil, URL:iCloudStoreURL, options:iCloudStoreOptions, error:&error) == nil {
			let alertController = UIAlertController(title:NSLocalizedString("Can't Open Database", comment:""),
				message:NSLocalizedString("Sorry, the application database cannot be opened. Please quit the application with the Home button.", comment:""),
				preferredStyle:.Alert)
			let defaultAction = UIAlertAction(title:NSLocalizedString("OK", comment:""), style:.Default) { _ in
				fatalError(error!.localizedDescription)
			}
			alertController.addAction(defaultAction)
			UIApplication.sharedApplication().keyWindow?.rootViewController?.presentViewController(alertController, animated:true, completion:nil)
		}

		return persistentStoreCoordinator
	}()

	private var importAlert: UIAlertController?

	//MARK: - Application Lifecycle

	override init() {
		NSUserDefaults.standardUserDefaults().registerDefaults(
		   ["statisticTimeSpan": 6,
			"preferredStatisticsPage": 1,
			"preferredCarID": "",
			"recentDistance": NSDecimalNumber.zero(),
			"recentPrice": NSDecimalNumber.zero(),
			"recentFuelVolume": NSDecimalNumber.zero(),
			"recentFilledUp": true,
			"editHelpCounter": 0,
			"firstStartup": true])

		self.window = AppWindow(frame: UIScreen.mainScreen().bounds)

		super.init()
	}

	private var launchInitPred: dispatch_once_t = 0

	private func commonLaunchInitialization(launchOptions: [NSObject : AnyObject]?) {
		dispatch_once(&launchInitPred) {
			self.window?.makeKeyAndVisible()

			self.migrateToiCloud()
			self.registerForiCloudNotifications()

			// Switch once to the car view for new users
			if launchOptions?[UIApplicationLaunchOptionsURLKey] == nil {
				let defaults = NSUserDefaults.standardUserDefaults()

				if defaults.boolForKey("firstStartup") {
					if defaults.stringForKey("preferredCarID") == "" {
						if let tabBarController = self.window?.rootViewController as? UITabBarController {
							tabBarController.selectedIndex = 1
						}
					}

					defaults.setObject(false, forKey:"firstStartup")
				}
			}
		}
	}


	public func application(application: UIApplication, willFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {
		commonLaunchInitialization(launchOptions)
		return true
	}

	public func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {
		commonLaunchInitialization(launchOptions)
		return true
	}

	public func applicationDidEnterBackground(application: UIApplication) {
		saveContext(AppDelegate.managedObjectContext)
	}

	public func applicationWillTerminate(application: UIApplication) {
		saveContext(AppDelegate.managedObjectContext)
	}

	//MARK: - State Restoration

	public func application(application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
		return true
	}

	public func application(application: UIApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
		let bundleVersion = NSBundle.mainBundle().infoDictionary?[kCFBundleVersionKey as String] as? Int ?? 0
		let stateVersion = coder.decodeObjectOfClass(NSNumber.self, forKey:UIApplicationStateRestorationBundleVersionKey) as? Int ?? 0

		// we don't restore from iOS6 compatible or future versions of the App
		return stateVersion >= 1572 && stateVersion <= bundleVersion
	}

	//MARK: - Data Import

	private func showImportAlert() {
		if self.importAlert == nil {
			self.importAlert = UIAlertController(title:NSLocalizedString("Importing", comment:""), message:"", preferredStyle:.Alert)

			let progress = UIActivityIndicatorView(frame:self.importAlert!.view.bounds)
			progress.autoresizingMask = .FlexibleWidth | .FlexibleHeight
			progress.userInteractionEnabled = false
			progress.activityIndicatorViewStyle = .WhiteLarge
			progress.startAnimating()

			self.importAlert!.view.addSubview(progress)

			self.window?.rootViewController?.presentViewController(self.importAlert!, animated:true, completion:nil)
		}
	}

	private func hideImportAlert() {
		self.window?.rootViewController?.dismissViewControllerAnimated(true, completion:nil)
		self.importAlert = nil
	}

	// Read file contents from given URL, guess file encoding
	private func contentsOfURL(url: NSURL) -> String? {
		var enc: NSStringEncoding = NSUTF8StringEncoding
		var error: NSError?
		let string = String(contentsOfURL: url, usedEncoding: &enc, error: &error)

		if string == nil || error != nil {
			error = nil
			return String(contentsOfURL:url, encoding:NSMacOSRomanStringEncoding, error:&error)
		} else {
			return string
		}
	}

	// Removes files from the inbox
	private func removeFileItemAtURL(url: NSURL) {
		if url.fileURL {
			var error: NSError?

			NSFileManager.defaultManager().removeItemAtURL(url, error:&error)

			if let error = error {
				NSLog("%@", error.localizedDescription)
			}
		}
	}

	private func pluralizedImportMessageForCarCount(carCount: Int, eventCount: Int) -> String {
		let format: String
    
		if carCount == 1 {
			format = NSLocalizedString(((eventCount == 1) ? "Imported %d car with %d fuel event."  : "Imported %d car with %d fuel events."), comment:"")
		} else {
			format = NSLocalizedString(((eventCount == 1) ? "Imported %d cars with %d fuel event." : "Imported %d cars with %d fuel events."), comment:"")
		}

		return String(format:format, carCount, eventCount)
	}

	public func application(application: UIApplication, openURL url: NSURL, sourceApplication: String?, annotation: AnyObject?) -> Bool {
		// Ugly, but don't allow nested imports
		if self.importAlert != nil {
			removeFileItemAtURL(url)
			return false
		}

		// Show modal activity indicator while importing
		showImportAlert()

		// Import in context with private queue
		let parentContext = AppDelegate.managedObjectContext
		let importContext = NSManagedObjectContext(concurrencyType:.PrivateQueueConcurrencyType)
		importContext.parentContext = parentContext

		importContext.performBlock {
			// Read file contents from given URL, guess file encoding
			let CSVString = self.contentsOfURL(url)
			self.removeFileItemAtURL(url)

			if let CSVString = CSVString {
				// Try to import data from CSV file
				let importer = CSVImporter()

				var numCars   = 0
				var numEvents = 0

				let success = importer.importFromCSVString(CSVString,
                                            detectedCars:&numCars,
                                          detectedEvents:&numEvents,
                                               sourceURL:url,
                                              inContext:importContext)

				// On success propagate changes to parent context
				if success {
					self.saveContext(importContext)
					parentContext.performBlock { self.saveContext(parentContext) }
				}

				dispatch_async(dispatch_get_main_queue()) {
					self.hideImportAlert()

					let title = success ? NSLocalizedString("Import Finished", comment:"") : NSLocalizedString("Import Failed", comment:"")

					let message = success
						? self.pluralizedImportMessageForCarCount(numCars, eventCount:numEvents)
						: NSLocalizedString("No valid CSV-data could be found.", comment:"")

					let alertController = UIAlertController(title:title, message:message, preferredStyle:.Alert)
					let defaultAction = UIAlertAction(title:NSLocalizedString("OK", comment:""), style:.Default) { _ in () }
					alertController.addAction(defaultAction)
					self.window?.rootViewController?.presentViewController(alertController, animated:true, completion:nil)
				}
			} else {
				dispatch_async(dispatch_get_main_queue()) {
					self.hideImportAlert()

					let alertController = UIAlertController(title:NSLocalizedString("Import Failed", comment:""),
						message:NSLocalizedString("Can't detect file encoding. Please try to convert your CSV-file to UTF8 encoding.", comment:""),
						preferredStyle:.Alert)
					let defaultAction = UIAlertAction(title:NSLocalizedString("OK", comment:""), style:.Default, handler: nil)
					alertController.addAction(defaultAction)
					self.window?.rootViewController?.presentViewController(alertController, animated:true, completion:nil)
				}
			}
		}

		// Treat imports as successful first startups
		NSUserDefaults.standardUserDefaults().setObject(false, forKey:"firstStartup")
		return true
	}

	//MARK: - Application's Documents Directory

	private static let applicationDocumentsDirectory: String = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).last as! String

	//MARK: - Shared Color Gradients

	static let blueGradient: CGGradientRef = {
		let colorComponentsFlat: [CGFloat] = [ 0.360, 0.682, 0.870, 0.0,  0.466, 0.721, 0.870, 0.9 ]

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let blueGradient = CGGradientCreateWithColorComponents(colorSpace, colorComponentsFlat, nil, 2)

		return blueGradient
	}()

	static let greenGradient: CGGradientRef = {
		let colorComponentsFlat: [CGFloat] = [ 0.662, 0.815, 0.502, 0.0,  0.662, 0.815, 0.502, 0.9 ]

        let colorSpace = CGColorSpaceCreateDeviceRGB()
		let greenGradient = CGGradientCreateWithColorComponents(colorSpace, colorComponentsFlat, nil, 2)

		return greenGradient
    }()

	static let orangeGradient: CGGradientRef = {
		let colorComponentsFlat: [CGFloat] = [ 0.988, 0.662, 0.333, 0.0,  0.988, 0.662, 0.333, 0.9 ]

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let orangeGradient = CGGradientCreateWithColorComponents(colorSpace, colorComponentsFlat, nil, 2)

		return orangeGradient
    }()

	//MARK: - Core Data Support

	func saveContext(context: NSManagedObjectContext?) -> Bool {
		if let context = context where context.hasChanges {
			var error : NSError?

			if !context.save(&error) {
				let alertController = UIAlertController(title:NSLocalizedString("Can't Save Database", comment:""),
					message:NSLocalizedString("Sorry, the application database cannot be saved. Please quit the application with the Home button.", comment:""),
					preferredStyle:.Alert)
				let defaultAction = UIAlertAction(title:NSLocalizedString("OK", comment:""), style:.Default) { _ in
					fatalError(error!.localizedDescription)
				}
				alertController.addAction(defaultAction)
				self.window?.rootViewController?.presentViewController(alertController, animated:true, completion:nil)
			}

			return true
		}

		return false
	}

	static func modelIdentifierForManagedObject(object: NSManagedObject) -> String? {
		if !object.objectID.temporaryID {
			return object.objectID.URIRepresentation().absoluteString
		} else {
			return nil
		}
	}

	static func managedObjectForModelIdentifier(identifier: String) -> NSManagedObject? {
		let objectURL = NSURL(string:identifier)!

		if objectURL.scheme == "x-coredata" {
			if let objectID = AppDelegate.persistentStoreCoordinator.managedObjectIDForURIRepresentation(objectURL) {
				return AppDelegate.managedObjectContext.existingObjectWithID(objectID, error:nil)
			}
		}

		return nil
	}

	static func existingObject(object: NSManagedObject, inManagedObjectContext moc: NSManagedObjectContext) -> NSManagedObject? {
		if object.deleted {
			return nil
		} else {
			return moc.existingObjectWithID(object.objectID, error:nil)
		}
	}

	//MARK: - iCloud support

	private func migrateToiCloud() {
		let fileURL = AppDelegate.localStoreURL
		let fileManager = NSFileManager.defaultManager()

		if fileManager.fileExistsAtPath(fileURL.path!) {
			let migrationPSC = NSPersistentStoreCoordinator(managedObjectModel: AppDelegate.managedObjectModel)

			let options = [
				NSMigratePersistentStoresAutomaticallyOption: true,
				NSInferMappingModelAutomaticallyOption: true,
				NSReadOnlyPersistentStoreOption: true
			]

			// Open the existing local store
			var error: NSError?
			if let sourceStore = migrationPSC.addPersistentStoreWithType(NSSQLiteStoreType, configuration:nil, URL:fileURL, options:options as [NSObject : AnyObject], error:&error) {
				if let newStore = migrationPSC.migratePersistentStore(sourceStore, toURL:AppDelegate.iCloudStoreURL, options:AppDelegate.iCloudStoreOptions, withType:NSSQLiteStoreType, error:&error) {

					dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
						let fileCoordinator = NSFileCoordinator()
						fileCoordinator.coordinateWritingItemAtURL(fileURL, options: .ForMoving, error: &error) { writingURL in
							var renameError: NSError?
							let targetURL = fileURL.URLByAppendingPathExtension("migrated")
							if !fileManager.moveItemAtURL(fileURL, toURL: targetURL, error: &renameError) {
								if let error = renameError {
									NSLog("error renaming store after migration: %@", error.localizedDescription)
								}
							}
						}
					}
				} else  {
					if let error = error {
						NSLog("error while migrating to iCloud: %@", error.localizedDescription)
					}
				}
			} else {
				if let error = error {
					NSLog("failed to open local store for migration: %@", error.localizedDescription)
				}
			}
		}
	}

	private func registerForiCloudNotifications() {
		let notificationCenter = NSNotificationCenter.defaultCenter()

		notificationCenter.addObserver(self,
			selector: "storesWillChange:",
			name: NSPersistentStoreCoordinatorStoresWillChangeNotification,
			object: AppDelegate.persistentStoreCoordinator)

		notificationCenter.addObserver(self,
			selector: "storesDidChange:",
			name: NSPersistentStoreCoordinatorStoresDidChangeNotification,
			object: AppDelegate.persistentStoreCoordinator)

		notificationCenter.addObserver(self,
			selector: "persistentStoreDidImportUbiquitousContentChanges:",
			name: NSPersistentStoreDidImportUbiquitousContentChangesNotification,
			object: AppDelegate.persistentStoreCoordinator)
	}

	func persistentStoreDidImportUbiquitousContentChanges(changeNotification: NSNotification) {
		let context = AppDelegate.managedObjectContext

		context.performBlock {
			context.mergeChangesFromContextDidSaveNotification(changeNotification)
		}
	}

	func storesWillChange(notification: NSNotification) {
		let context = AppDelegate.managedObjectContext

		context.performBlockAndWait {
			if context.hasChanges {
				var error: NSError?
				let success = context.save(&error)

				if let error = error where !success {
					// perform error handling
					NSLog("%@", error.localizedDescription)
				}
			}

			context.reset()
		}
	}

	func storesDidChange(notification: NSNotification) {
	}

	//MARK: - Preconfigured Core Data Fetches

	static func fetchRequestForCarsInManagedObjectContext(moc: NSManagedObjectContext) -> NSFetchRequest {
		let fetchRequest = NSFetchRequest()

		// Entity name
		let entity = NSEntityDescription.entityForName("car", inManagedObjectContext:moc)
		fetchRequest.entity = entity
		fetchRequest.fetchBatchSize = 32

		// Sorting keys
		let sortDescriptor = NSSortDescriptor(key:"order", ascending:true)
		fetchRequest.sortDescriptors = [sortDescriptor]

		return fetchRequest
	}

	static func fetchRequestForEventsForCar(car: Car,
                                       andDate date: NSDate?,
                                dateComparator dateCompare: String,
                                     fetchSize: Int,
                        inManagedObjectContext moc: NSManagedObjectContext) -> NSFetchRequest {
		let fetchRequest = NSFetchRequest()

		// Entity name
		let entity = NSEntityDescription.entityForName("fuelEvent", inManagedObjectContext:moc)
		fetchRequest.entity = entity
		fetchRequest.fetchBatchSize = fetchSize

		// Predicates
		let parentPredicate = NSPredicate(format:"car == %@", car)

		if let date = date {
			let dateDescription = NSExpression(forConstantValue:date).description
			let datePredicate = NSPredicate(format:String(format:"timestamp %@ %@", dateCompare, dateDescription))

			fetchRequest.predicate = NSCompoundPredicate.andPredicateWithSubpredicates([parentPredicate, datePredicate])
		} else {
			fetchRequest.predicate = parentPredicate
		}

		// Sorting keys
		let sortDescriptor = NSSortDescriptor(key:"timestamp", ascending:false)
		fetchRequest.sortDescriptors = [sortDescriptor]

		return fetchRequest
	}

	static func fetchRequestForEventsForCar(car: Car,
                                     afterDate date: NSDate?,
                                   dateMatches: Bool,
                        inManagedObjectContext moc: NSManagedObjectContext) -> NSFetchRequest {
		return fetchRequestForEventsForCar(car,
                                     andDate:date,
                              dateComparator:dateMatches ? ">=" : ">",
                                   fetchSize:128,
                      inManagedObjectContext:moc)
	}

	public static func fetchRequestForEventsForCar(car: Car,
                                    beforeDate date: NSDate?,
                                   dateMatches: Bool,
                        inManagedObjectContext moc: NSManagedObjectContext) -> NSFetchRequest {
		return fetchRequestForEventsForCar(car,
                                     andDate:date,
                              dateComparator:dateMatches ? "<=" : "<",
                                   fetchSize:8,
                      inManagedObjectContext:moc)
	}

	static func fetchedResultsControllerForCarsInContext(moc: NSManagedObjectContext) -> NSFetchedResultsController {
		let fetchRequest = fetchRequestForCarsInManagedObjectContext(moc)

		// No section names; perform fetch without cache
		let fetchedResultsController = NSFetchedResultsController(fetchRequest:fetchRequest,
			managedObjectContext:moc,
			sectionNameKeyPath:nil,
            cacheName:nil)

		// Perform the Core Data fetch
		var error: NSError?
		if !fetchedResultsController.performFetch(&error) {
			fatalError(error!.localizedDescription)
		}

		return fetchedResultsController
	}

	public static func objectsForFetchRequest(fetchRequest: NSFetchRequest, inManagedObjectContext moc: NSManagedObjectContext) -> [NSManagedObject] {
		var error: NSError?
		let fetchedObjects = moc.executeFetchRequest(fetchRequest, error:&error)

		if let error = error {
			fatalError(error.localizedDescription)
		}

		return fetchedObjects as! [NSManagedObject]
	}

	static func managedObjectContext(moc: NSManagedObjectContext, containsEventWithCar car: Car, andDate date: NSDate) -> Bool {
		let fetchRequest = NSFetchRequest()

		// Entity name
		let entity = NSEntityDescription.entityForName("fuelEvent", inManagedObjectContext:moc)
		fetchRequest.entity = entity
		fetchRequest.fetchBatchSize = 2

		// Predicates
		let parentPredicate = NSPredicate(format:"car == %@", car)

		let dateDescription = NSExpression(forConstantValue:date).description
		let datePredicate = NSPredicate(format:String(format:"timestamp == %@", dateDescription))

		fetchRequest.predicate = NSCompoundPredicate.andPredicateWithSubpredicates([parentPredicate, datePredicate])

		// Check whether fetch would reveal any event objects
		var error: NSError?
		let objectCount = moc.countForFetchRequest(fetchRequest, error:&error)

		if let error = error {
			fatalError(error.localizedDescription)
		}

		return objectCount > 0
	}

	//MARK: - Core Data Updates

	static func addToArchiveWithCar(car: Car, date: NSDate, distance: NSDecimalNumber, price: NSDecimalNumber, fuelVolume: NSDecimalNumber, filledUp: Bool, inManagedObjectContext moc: NSManagedObjectContext, var forceOdometerUpdate: Bool) -> FuelEvent {
		let zero = NSDecimalNumber.zero()

		// Convert distance and fuelvolume to SI units
		let fuelUnit     = car.ksFuelUnit
		let odometerUnit = car.ksOdometerUnit

		let liters        = Units.litersForVolume(fuelVolume, withUnit:fuelUnit)
		let kilometers    = Units.kilometersForDistance(distance, withUnit:odometerUnit)
		let pricePerLiter = Units.pricePerLiter(price, withUnit:fuelUnit)

		var inheritedCost       = zero
		var inheritedDistance   = zero
		var inheritedFuelVolume = zero

		// Compute inherited data from older element

		// Fetch older events
        let olderEvents = objectsForFetchRequest(fetchRequestForEventsForCar(car,
                                                                                    beforeDate:date,
                                                                                   dateMatches:false,
                                                                        inManagedObjectContext:moc),
                                     inManagedObjectContext:moc) as! [FuelEvent]

        if olderEvents.count > 0 {
			let olderEvent = olderEvents.first!

            if !olderEvent.filledUp {
                let cost = olderEvent.cost

                inheritedCost       = cost + olderEvent.inheritedCost
                inheritedDistance   = olderEvent.distance + olderEvent.inheritedDistance
                inheritedFuelVolume = olderEvent.fuelVolume + olderEvent.inheritedFuelVolume
            }
		}

		// Update inherited distance/volume for younger events, probably mark the car odometer for an update
        // Fetch younger events
        let youngerEvents = objectsForFetchRequest(fetchRequestForEventsForCar(car,
                                                                                       afterDate:date,
                                                                                     dateMatches:false,
                                                                          inManagedObjectContext:moc),
                                       inManagedObjectContext:moc) as! [FuelEvent]

        if youngerEvents.count > 0 {

            let deltaCost = filledUp
                ? -inheritedCost
                : liters * pricePerLiter

            let deltaDistance = filledUp
                ? -inheritedDistance
                : kilometers

            let deltaFuelVolume = filledUp
                ? -inheritedFuelVolume
                : liters

            for var row = youngerEvents.count; row > 0; {
				let youngerEvent = youngerEvents[--row]

				youngerEvent.inheritedCost = max(youngerEvent.inheritedCost + deltaCost, zero)
				youngerEvent.inheritedDistance = max(youngerEvent.inheritedDistance + deltaDistance, zero)
				youngerEvent.inheritedFuelVolume = max(youngerEvent.inheritedFuelVolume + deltaFuelVolume, zero)

				if youngerEvent.filledUp {
                    break
				}
            }
		} else {
			// New event will be the youngest one => update odometer too
            forceOdometerUpdate = true
		}

		// Create new managed object for this event
		let newEvent = NSEntityDescription.insertNewObjectForEntityForName("fuelEvent", inManagedObjectContext:moc) as! FuelEvent

		newEvent.car = car
		newEvent.timestamp = date
		newEvent.distance = kilometers
		newEvent.price = pricePerLiter
		newEvent.fuelVolume = liters

		if !filledUp {
			newEvent.filledUp = filledUp
		}

		if inheritedCost != zero {
			newEvent.inheritedCost = inheritedCost
		}

		if inheritedDistance != zero {
			newEvent.inheritedDistance = inheritedDistance
		}

		if inheritedFuelVolume != zero {
			newEvent.inheritedFuelVolume = inheritedFuelVolume
		}

		// Conditions for update of global odometer:
		// - when the new event is the youngest one
		// - when sum of all events equals the odometer value
		// - when forced to do so
		if !forceOdometerUpdate {
			if car.odometer <= car.distanceTotalSum {
				forceOdometerUpdate = true
			}
		}

		// Update total car statistics
		car.distanceTotalSum = car.distanceTotalSum + kilometers
		car.fuelVolumeTotalSum = car.fuelVolumeTotalSum + liters

		if forceOdometerUpdate {
			// Update global odometer
			car.odometer = max(car.odometer + kilometers, car.distanceTotalSum)
		}

		return newEvent
	}

	static func removeEventFromArchive(event: FuelEvent!, inManagedObjectContext moc: NSManagedObjectContext, forceOdometerUpdate odometerUpdate: Bool) {
		// catch nil events
		if event == nil {
			return
		}

		var forceOdometerUpdate = odometerUpdate
		let car = event.car
		let distance = event.distance
		let fuelVolume = event.fuelVolume
		let zero = NSDecimalNumber.zero()

		// Event will be deleted: update inherited distance/fuelVolume for younger events
		let youngerEvents = objectsForFetchRequest(fetchRequestForEventsForCar(car,
                                                                                  afterDate:event.timestamp,
                                                                                dateMatches:false,
                                                                     inManagedObjectContext:moc),
                                   inManagedObjectContext:moc) as! [FuelEvent]

		var row = youngerEvents.count
		if row > 0 {
			// Fill-up event deleted => propagate its inherited distance/volume
			if event.filledUp {
				let inheritedCost       = event.inheritedCost
				let inheritedDistance   = event.inheritedDistance
				let inheritedFuelVolume = event.inheritedFuelVolume

				if inheritedCost > zero || inheritedDistance > zero || inheritedFuelVolume > zero {
					while row > 0 {
						let youngerEvent = youngerEvents[--row]

						youngerEvent.inheritedCost = youngerEvent.inheritedCost + inheritedCost
						youngerEvent.inheritedDistance = youngerEvent.inheritedDistance + inheritedDistance
						youngerEvent.inheritedFuelVolume = youngerEvent.inheritedFuelVolume + inheritedFuelVolume

						if youngerEvent.filledUp {
							break
						}
					}
				}
			} else {
				// Intermediate event deleted => remove distance/volume from inherited data

				while row > 0 {
					let youngerEvent = youngerEvents[--row]
					let cost = event.price

					youngerEvent.inheritedCost = max(youngerEvent.inheritedCost - cost, zero)
					youngerEvent.inheritedDistance = max(youngerEvent.inheritedDistance - distance, zero)
					youngerEvent.inheritedFuelVolume = max(youngerEvent.inheritedFuelVolume - fuelVolume, zero)

					if youngerEvent.filledUp {
						break
					}
				}
			}
		} else {
			forceOdometerUpdate = true
		}

		// Conditions for update of global odometer:
		// - when youngest element gets deleted
		// - when sum of all events equals the odometer value
		// - when forced to do so
		if !forceOdometerUpdate {
			if car.odometer <= car.distanceTotalSum {
				forceOdometerUpdate = true
			}
		}

		// Update total car statistics
		car.distanceTotalSum = max(car.distanceTotalSum - distance, zero)
		car.fuelVolumeTotalSum = max(car.fuelVolumeTotalSum - fuelVolume, zero)

		// Update global odometer
		if forceOdometerUpdate {
			car.odometer = max(car.odometer - distance, zero)
		}

		// Delete the managed event object
		moc.deleteObject(event)
	}
}
