import ExpoModulesCore
import MapboxNavigationCore
import MapboxMaps
import MapboxNavigationUIKit
import MapboxDirections
import Combine


class ExpoMapboxNavigationView: ExpoView {
    private let onRouteProgressChanged = EventDispatcher()
    private let onCancelNavigation = EventDispatcher()
    private let onWaypointArrival = EventDispatcher()
    private let onFinalDestinationArrival = EventDispatcher()
    private let onRouteChanged = EventDispatcher()
    private let onUserOffRoute = EventDispatcher()
    private let onRoutesLoaded = EventDispatcher()
    private let onRouteFailedToLoad = EventDispatcher()

    let controller = ExpoMapboxNavigationViewController()

    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        clipsToBounds = true
        addSubview(controller.view)

        controller.onRouteProgressChanged = onRouteProgressChanged
        controller.onCancelNavigation = onCancelNavigation
        controller.onWaypointArrival = onWaypointArrival
        controller.onFinalDestinationArrival = onFinalDestinationArrival
        controller.onRouteChanged = onRouteChanged
        controller.onUserOffRoute = onUserOffRoute
        controller.onRoutesLoaded = onRoutesLoaded
        controller.onRouteFailedToLoad = onRouteFailedToLoad
    }

    override func layoutSubviews() {
        controller.view.frame = bounds
    }
}


class ExpoMapboxNavigationViewController: UIViewController {
    static let navigationProvider: MapboxNavigationProvider = MapboxNavigationProvider(coreConfig: .init(locationSource: .live))
    var mapboxNavigation: MapboxNavigation? = nil
    var routingProvider: RoutingProvider? = nil
    var navigation: NavigationController? = nil
    var tripSession: SessionController? = nil
    var navigationViewController: NavigationViewController? = nil
    
    var currentCoordinates: Array<CLLocationCoordinate2D>? = nil
    var initialLocation: CLLocationCoordinate2D? = nil
    var initialLocationZoom: Double? = nil
    var currentWaypointIndices: Array<Int>? = nil
    var currentLocale: Locale = Locale.current
    var currentRouteProfile: String? = nil
    var currentRouteExcludeList: Array<String>? = nil
    var currentMapStyle: String? = nil
    var isUsingRouteMatchingApi: Bool = false
    var vehicleMaxHeight: Double? = nil
    var vehicleMaxWidth: Double? = nil

    // Debug state tracking
    var debugLog: [String] = []
    var navigationState: String = "idle"
    var lastError: String? = nil
    var initializationCount: Int = 0
    var cleanupCount: Int = 0
    var routeCalculationCount: Int = 0
    var viewLifecycleState: String = "unknown"
    var memoryWarningCount: Int = 0
    var providerInstanceHash: String = ""

    var onRouteProgressChanged: EventDispatcher? = nil
    var onCancelNavigation: EventDispatcher? = nil
    var onWaypointArrival: EventDispatcher? = nil
    var onFinalDestinationArrival: EventDispatcher? = nil
    var onRouteChanged: EventDispatcher? = nil
    var onUserOffRoute: EventDispatcher? = nil
    var onRoutesLoaded: EventDispatcher? = nil
    var onRouteFailedToLoad: EventDispatcher? = nil

    var calculateRoutesTask: Task<Void, Error>? = nil
    private var routeProgressCancellable: AnyCancellable? = nil
    private var waypointArrivalCancellable: AnyCancellable? = nil
    private var reroutingCancellable: AnyCancellable? = nil
    private var sessionCancellable: AnyCancellable? = nil

    // Debug helper methods
    func addDebugLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        debugLog.append(logEntry)
        
        // Keep only last 100 entries to prevent memory buildup
        if debugLog.count > 100 {
            debugLog.removeFirst()
        }
        
        // Also log to console for immediate debugging
        print("[Navigation Debug] \(logEntry)")
    }
    
    func getProviderStatus() -> String {
        return "static_provider_active"
    }
    
    func getSessionStatus() -> String {
        guard let session = tripSession?.session else { return "no_session" }
        return "\(session)"
    }
    
    func forceCleanup() {
        addDebugLog("forceCleanup() called")
        cleanupCount += 1
        navigationState = "force_cleaning"
        
        // Force stop active guidance
        Task { @MainActor in 
            tripSession?.setToIdle()
            navigationState = "idle"
            addDebugLog("Force cleanup completed")
        }
    }
    
    func testRouteCalculation(_ coordinates: [[Double]]) {
        addDebugLog("testRouteCalculation called with \(coordinates.count) coordinates")
        routeCalculationCount += 1
        
        // Convert coordinates and test route calculation
        let testCoordinates = coordinates.map { coord in
            CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
        }
        
        let waypoints = testCoordinates.map { Waypoint(coordinate: $0) }
        let routeOptions = NavigationRouteOptions(waypoints: waypoints)
        
        Task {
            do {
                addDebugLog("Starting test route calculation")
                let routes = try await routingProvider!.calculateRoutes(options: routeOptions).value
                addDebugLog("Test route calculation succeeded: 1 main + \(routes.alternativeRoutes.count) alternatives")
            } catch {
                addDebugLog("Test route calculation failed: \(error.localizedDescription)")
                lastError = error.localizedDescription
            }
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        
        // Debug: Track initialization
        initializationCount += 1
        viewLifecycleState = "initializing"
        providerInstanceHash = String(describing: Unmanaged.passUnretained(ExpoMapboxNavigationViewController.navigationProvider).toOpaque())
        addDebugLog("ExpoMapboxNavigationViewController initialized #\(initializationCount)")
        addDebugLog("Provider instance hash: \(providerInstanceHash)")
        
        mapboxNavigation = ExpoMapboxNavigationViewController.navigationProvider.mapboxNavigation
        routingProvider = mapboxNavigation!.routingProvider()
        navigation = mapboxNavigation!.navigation()
        tripSession = mapboxNavigation!.tripSession()
        
        navigationState = "initialized"
        addDebugLog("Navigation components initialized")

        routeProgressCancellable = navigation!.routeProgress.sink { progressState in
            if(progressState != nil){
               self.onRouteProgressChanged?([
                    "distanceRemaining": progressState!.routeProgress.distanceRemaining,
                    "distanceTraveled": progressState!.routeProgress.distanceTraveled,
                    "durationRemaining": progressState!.routeProgress.durationRemaining,
                    "fractionTraveled": progressState!.routeProgress.fractionTraveled,
                ])
            }
        }

        waypointArrivalCancellable = navigation!.waypointsArrival.sink { arrivalStatus in
            let event = arrivalStatus.event
            if event is WaypointArrivalStatus.Events.ToFinalDestination {
                self.onFinalDestinationArrival?()
            } else if event is WaypointArrivalStatus.Events.ToWaypoint {
                self.onWaypointArrival?()
            }
        }

        reroutingCancellable = navigation!.rerouting.sink { rerouteStatus in
            self.onRouteChanged?()            
        }

        sessionCancellable = tripSession!.session.sink { session in 
            let state = session.state
            switch state {
                case .activeGuidance(let activeGuidanceState):
                    switch(activeGuidanceState){
                        case .offRoute:
                            self.onUserOffRoute?()
                        default: break
                    }
                default: break
            }
        }

    }

    deinit {
        addDebugLog("ExpoMapboxNavigationViewController deinit called")
        viewLifecycleState = "deinitializing"
        
        routeProgressCancellable?.cancel()
        waypointArrivalCancellable?.cancel()
        reroutingCancellable?.cancel()
        sessionCancellable?.cancel()
        
        addDebugLog("ExpoMapboxNavigationViewController deinit completed")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        addDebugLog("viewDidDisappear called (animated: \(animated))")
        viewLifecycleState = "disappeared"
        cleanupCount += 1
        navigationState = "cleaning_up"
        
        Task { @MainActor in 
            tripSession?.setToIdle() // Stops navigation
            navigationState = "idle"
            addDebugLog("Navigation stopped via viewDidDisappear")
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        memoryWarningCount += 1
        addDebugLog("Memory warning received (count: \(memoryWarningCount))")
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        fatalError("This controller should not be loaded through a story board")
    }


    func setCoordinates(coordinates: Array<CLLocationCoordinate2D>) {
        addDebugLog("setCoordinates called with \(coordinates.count) points")
        
        // Log first, last, and any invalid coordinates
        if coordinates.count > 0 {
            addDebugLog("First coord: lat=\(coordinates[0].latitude), lng=\(coordinates[0].longitude)")
            addDebugLog("Last coord: lat=\(coordinates[coordinates.count-1].latitude), lng=\(coordinates[coordinates.count-1].longitude)")
            
            // Check for invalid coordinates
            var invalidCount = 0
            for (index, coord) in coordinates.enumerated() {
                if !CLLocationCoordinate2DIsValid(coord) {
                    addDebugLog("❌ Invalid coord at index \(index): lat=\(coord.latitude), lng=\(coord.longitude)")
                    invalidCount += 1
                }
                // Check for suspicious values
                if abs(coord.latitude) > 90 || abs(coord.longitude) > 180 {
                    addDebugLog("⚠️ Out of range coord at index \(index): lat=\(coord.latitude), lng=\(coord.longitude)")
                }
                // Check for zero/null island
                if coord.latitude == 0 && coord.longitude == 0 {
                    addDebugLog("⚠️ Null island coord at index \(index)")
                }
            }
            
            if invalidCount > 0 {
                addDebugLog("❌ Total invalid coordinates: \(invalidCount)/\(coordinates.count)")
                lastError = "Invalid coordinates detected: \(invalidCount)/\(coordinates.count)"
            }
        }
        
        currentCoordinates = coordinates
        update()
    }

    func setVehicleMaxHeight(maxHeight: Double?) {
        vehicleMaxHeight = maxHeight
        update()
    }

    func setVehicleMaxWidth(maxWidth: Double?) {
        vehicleMaxWidth = maxWidth
        update()
    }

    func setLocale(locale: String?) {
        if(locale != nil){
            currentLocale = Locale(identifier: locale!)
        } else {
            currentLocale = Locale.current
        }
        update()
    }

    func setIsUsingRouteMatchingApi(useRouteMatchingApi: Bool?){
        isUsingRouteMatchingApi = useRouteMatchingApi ?? false
        update()
    }

    func setWaypointIndices(waypointIndices: Array<Int>?){
        currentWaypointIndices = waypointIndices
        update()
    }

    func setRouteProfile(profile: String?){
        currentRouteProfile = profile
        update()
    }

    func setRouteExcludeList(excludeList: Array<String>?){
        currentRouteExcludeList = excludeList
        update()
    }

    func setMapStyle(style: String?){
        currentMapStyle = style
        update()
    }

    func recenterMap(){
        let navigationMapView = navigationViewController?.navigationMapView
        navigationMapView?.navigationCamera.update(cameraState: .following)
    }

    func setIsMuted(isMuted: Bool?){
        if(isMuted != nil){
            ExpoMapboxNavigationViewController.navigationProvider.routeVoiceController.speechSynthesizer.muted = isMuted!
        }
    }

    func setInitialLocation(location: CLLocationCoordinate2D, zoom: Double?){
        initialLocation = location
        initialLocationZoom = zoom
        let navigationMapView = navigationViewController?.navigationMapView
        if(initialLocation != nil && navigationMapView != nil){
            navigationMapView!.mapView.mapboxMap.setCamera(to: CameraOptions(center: initialLocation!, zoom: initialLocationZoom ?? 15))
        }
    }

    func update(){
        calculateRoutesTask?.cancel()

        if(currentCoordinates != nil){
            let coordinatesCount = currentCoordinates!.count
            let waypoints = currentCoordinates!.enumerated().map {
                let index = $0
                let coordinate = $1
                var waypoint = Waypoint(coordinate: coordinate) 
                // Only mark as separate leg if: it's the first, last, or explicitly specified in waypointIndices
                waypoint.separatesLegs = index == 0 || index == coordinatesCount - 1 || 
                                        (currentWaypointIndices != nil && currentWaypointIndices!.contains(index))
                return waypoint
            }

            if(isUsingRouteMatchingApi){
                calculateMapMatchingRoutes(waypoints: waypoints)
            } else {
                calculateRoutes(waypoints: waypoints)
            }
        }
    }

    func calculateRoutes(waypoints: Array<Waypoint>){
        addDebugLog("calculateRoutes() called with \(waypoints.count) waypoints")
        
        // Log waypoint details
        for (index, waypoint) in waypoints.enumerated() {
            let coord = waypoint.coordinate
            addDebugLog("Waypoint \(index): lat=\(coord.latitude), lng=\(coord.longitude), separatesLegs=\(waypoint.separatesLegs)")
        }
        
        // Log route options
        addDebugLog("Route profile: \(currentRouteProfile ?? "default")")
        addDebugLog("Exclude list: \(currentRouteExcludeList?.joined(separator: ",") ?? "none")")
        addDebugLog("Vehicle max height: \(vehicleMaxHeight ?? 0.0)")
        addDebugLog("Vehicle max width: \(vehicleMaxWidth ?? 0.0)")
        addDebugLog("Locale: \(currentLocale.identifier)")
        
        routeCalculationCount += 1
        navigationState = "calculating_route"
        
        let routeOptions = NavigationRouteOptions(
            waypoints: waypoints, 
            profileIdentifier: currentRouteProfile != nil ? ProfileIdentifier(rawValue: currentRouteProfile!) : nil,
            queryItems: [
                URLQueryItem(name: "exclude", value: currentRouteExcludeList?.joined(separator: ",")),
                URLQueryItem(name: "max_height", value: String(format: "%.1f", vehicleMaxHeight ?? 0.0)),
                URLQueryItem(name: "max_width", value: String(format: "%.1f", vehicleMaxWidth ?? 0.0))
            ],
            locale: currentLocale, 
            distanceUnit: currentLocale.usesMetricSystem ? LengthFormatter.Unit.meter : LengthFormatter.Unit.mile
        )
        
        // Disable alternative routes for better performance
        routeOptions.includesAlternativeRoutes = false

        // Log the actual API request details
        addDebugLog("Route options locale: \(routeOptions.locale)")
        addDebugLog("Route options distance unit: \(routeOptions.distanceUnit)")

        calculateRoutesTask = Task {
            addDebugLog("📡 Sending route calculation request to Mapbox API...")
            let startTime = Date()
            
            switch await self.routingProvider!.calculateRoutes(options: routeOptions).result {
            case .failure(let error):
                let duration = Date().timeIntervalSince(startTime)
                addDebugLog("❌ Route calculation failed after \(String(format: "%.2f", duration))s")
                addDebugLog("Error type: \(type(of: error))")
                addDebugLog("Error description: \(error.localizedDescription)")
                
                // Log more error details if available
                if let nsError = error as NSError? {
                    addDebugLog("Error code: \(nsError.code)")
                    addDebugLog("Error domain: \(nsError.domain)")
                    addDebugLog("Error userInfo: \(nsError.userInfo)")
                }
                
                lastError = error.localizedDescription
                navigationState = "route_error"
                onRouteFailedToLoad?([
                    "errorMessage": error.localizedDescription
                ])
                print(error.localizedDescription)
            case .success(let navigationRoutes):
                let duration = Date().timeIntervalSince(startTime)
                addDebugLog("✅ Route calculation succeeded in \(String(format: "%.2f", duration))s")
                addDebugLog("Main route legs: \(navigationRoutes.mainRoute.route.legs.count)")
                addDebugLog("Alternative routes: \(navigationRoutes.alternativeRoutes.count)")
                
                // Log route details
                let mainRoute = navigationRoutes.mainRoute.route
                addDebugLog("Route distance: \(String(format: "%.0f", mainRoute.distance))m")
                addDebugLog("Route duration: \(String(format: "%.0f", mainRoute.expectedTravelTime))s")
                
                // Log legs info
                for (index, leg) in mainRoute.legs.enumerated() {
                    addDebugLog("Leg \(index): distance=\(String(format: "%.0f", leg.distance))m, duration=\(String(format: "%.0f", leg.expectedTravelTime))s")
                    if let source = leg.source {
                        addDebugLog("  Source: lat=\(source.coordinate.latitude), lng=\(source.coordinate.longitude)")
                    }
                    if let dest = leg.destination {
                        addDebugLog("  Dest: lat=\(dest.coordinate.latitude), lng=\(dest.coordinate.longitude)")
                    }
                }
                
                navigationState = "route_calculated"
                onRoutesCalculated(navigationRoutes: navigationRoutes)
            }
        }
    }

    func calculateMapMatchingRoutes(waypoints: Array<Waypoint>){
        addDebugLog("calculateMapMatchingRoutes() called with \(waypoints.count) waypoints")
        
        // Log waypoint details for map matching
        for (index, waypoint) in waypoints.enumerated() {
            let coord = waypoint.coordinate
            addDebugLog("MapMatch Waypoint \(index): lat=\(coord.latitude), lng=\(coord.longitude), separatesLegs=\(waypoint.separatesLegs)")
        }
        
        addDebugLog("Map matching route profile: \(currentRouteProfile ?? "default")")
        addDebugLog("Map matching exclude list: \(currentRouteExcludeList?.joined(separator: ",") ?? "none")")
        addDebugLog("Map matching locale: \(currentLocale.identifier)")
        
        routeCalculationCount += 1
        navigationState = "calculating_map_matching_route"
        
        let matchOptions = NavigationMatchOptions(
            waypoints: waypoints, 
            profileIdentifier: currentRouteProfile != nil ? ProfileIdentifier(rawValue: currentRouteProfile!) : nil,
            queryItems: [URLQueryItem(name: "exclude", value: currentRouteExcludeList?.joined(separator: ","))],
            distanceUnit: currentLocale.usesMetricSystem ? LengthFormatter.Unit.meter : LengthFormatter.Unit.mile
        )
        matchOptions.locale = currentLocale

        addDebugLog("Map matching options locale: \(matchOptions.locale)")
        addDebugLog("Map matching options distance unit: \(matchOptions.distanceUnit)")

        calculateRoutesTask = Task {
            addDebugLog("📡 Sending map matching request to Mapbox API...")
            let startTime = Date()
            
            switch await self.routingProvider!.calculateRoutes(options: matchOptions).result {
            case .failure(let error):
                let duration = Date().timeIntervalSince(startTime)
                addDebugLog("❌ Map matching failed after \(String(format: "%.2f", duration))s")
                addDebugLog("MapMatch Error type: \(type(of: error))")
                addDebugLog("MapMatch Error description: \(error.localizedDescription)")
                
                // Log more error details for map matching
                if let nsError = error as NSError? {
                    addDebugLog("MapMatch Error code: \(nsError.code)")
                    addDebugLog("MapMatch Error domain: \(nsError.domain)")
                    addDebugLog("MapMatch Error userInfo: \(nsError.userInfo)")
                }
                
                lastError = error.localizedDescription
                navigationState = "route_error"
                onRouteFailedToLoad?([
                    "errorMessage": error.localizedDescription
                ])
                print(error.localizedDescription)
            case .success(let navigationRoutes):
                let duration = Date().timeIntervalSince(startTime)
                addDebugLog("✅ Map matching succeeded in \(String(format: "%.2f", duration))s")
                addDebugLog("MapMatch Main route legs: \(navigationRoutes.mainRoute.route.legs.count)")
                addDebugLog("MapMatch Alternative routes: \(navigationRoutes.alternativeRoutes.count)")
                
                // Log map matching route details
                let mainRoute = navigationRoutes.mainRoute.route
                addDebugLog("MapMatch Route distance: \(String(format: "%.0f", mainRoute.distance))m")
                addDebugLog("MapMatch Route duration: \(String(format: "%.0f", mainRoute.expectedTravelTime))s")
                
                navigationState = "route_calculated"
                onRoutesCalculated(navigationRoutes: navigationRoutes)
            }
        }
    }

    @objc func cancelButtonClicked(_ sender: AnyObject?) {
        onCancelNavigation?()
    }

    func convertRoute(route: Route) -> Any {
        return [
            "distance": route.distance,
            "expectedTravelTime": route.expectedTravelTime,
            "legs": route.legs.map { leg in
                return [
                    "source": leg.source != nil ? [
                        "latitude": leg.source!.coordinate.latitude,
                        "longitude": leg.source!.coordinate.longitude
                    ] : nil,
                    "destination": leg.destination != nil ? [
                        "latitude": leg.destination!.coordinate.latitude,
                        "longitude": leg.destination!.coordinate.longitude
                    ] : nil,
                    "steps": leg.steps.map { step in
                        return [
                            "shape": step.shape != nil ? [
                                "coordinates": step.shape!.coordinates.map { coordinate in
                                    return [
                                        "latitude": coordinate.latitude,
                                        "longitude": coordinate.longitude,
                                    ]
                                }
                            ] : nil
                        ]
                    }
                ]
            }
        ]
    }

    func onRoutesCalculated(navigationRoutes: NavigationRoutes){
        addDebugLog("=== onRoutesCalculated - Beginning Navigation Setup ===")
        addDebugLog("Current state before setup: \(navigationState)")
        addDebugLog("NavigationViewController exists: \(navigationViewController != nil)")
        
        navigationState = "setting_up_navigation"
        
        onRoutesLoaded?([
            "routes": [
                "mainRoute": convertRoute(route: navigationRoutes.mainRoute.route),
                "alternativeRoutes": navigationRoutes.alternativeRoutes.map { convertRoute(route: $0.route) }
            ]
        ])

        let topBanner = TopBannerViewController()
        topBanner.instructionsBannerView.distanceFormatter.locale = currentLocale
        let bottomBanner = BottomBannerViewController()
        bottomBanner.distanceFormatter.locale = currentLocale
        bottomBanner.dateFormatter.locale = currentLocale

        let navigationOptions = NavigationOptions(
            mapboxNavigation: self.mapboxNavigation!,
            voiceController: ExpoMapboxNavigationViewController.navigationProvider.routeVoiceController,
            eventsManager: ExpoMapboxNavigationViewController.navigationProvider.eventsManager(),
            topBanner: topBanner,
            bottomBanner: bottomBanner
        )

        let newNavigationControllerRequired = navigationViewController == nil
        addDebugLog("New controller required: \(newNavigationControllerRequired)")

        if(newNavigationControllerRequired){
            addDebugLog("Creating new NavigationViewController")
            navigationViewController = NavigationViewController(
                navigationRoutes: navigationRoutes,
                navigationOptions: navigationOptions
            )
            addDebugLog("NavigationViewController created at address: \(Unmanaged.passUnretained(navigationViewController!).toOpaque())")
        } else {
            addDebugLog("Reusing existing NavigationViewController")
            addDebugLog("Existing controller address: \(Unmanaged.passUnretained(navigationViewController!).toOpaque())")
            navigationViewController!.prepareViewLoading(
                navigationRoutes: navigationRoutes,
                navigationOptions: navigationOptions
            )
        }
        
        let navigationViewController = navigationViewController!

        navigationViewController.usesNightStyleWhileInTunnel = false

        let navigationMapView = navigationViewController.navigationMapView
        navigationMapView!.puckType = .puck2D(.navigationDefault)

        if(initialLocation != nil && newNavigationControllerRequired){
            navigationMapView!.mapView.mapboxMap.setCamera(to: CameraOptions(center: initialLocation!, zoom: initialLocationZoom ?? 15))
        }

        let style = currentMapStyle != nil ? StyleURI(rawValue: currentMapStyle!) : StyleURI.streets
        navigationMapView!.mapView.mapboxMap.loadStyle(style!, completion: { _ in
            navigationMapView!.localizeLabels(locale: self.currentLocale)
            do{
                try navigationMapView!.mapView.mapboxMap.localizeLabels(into: self.currentLocale)
            } catch {}
        })
 

        let cancelButton = navigationViewController.navigationView.bottomBannerContainerView.findViews(subclassOf: CancelButton.self)[0]
        cancelButton.addTarget(self, action: #selector(cancelButtonClicked), for: .touchUpInside)

        navigationViewController.delegate = self
        addChild(navigationViewController)
        view.addSubview(navigationViewController.view)
        navigationViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navigationViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            navigationViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
            navigationViewController.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            navigationViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0),
        ])
        didMove(toParent: self)
        addDebugLog("Starting active guidance...")
        mapboxNavigation!.tripSession().startActiveGuidance(with: navigationRoutes, startLegIndex: 0)
        
        navigationState = "active_navigation"
        addDebugLog("=== Navigation Setup Complete ===")
        addDebugLog("Final state: \(navigationState)")
        viewLifecycleState = "navigating"
    }
}
extension ExpoMapboxNavigationViewController: NavigationViewControllerDelegate {
    func navigationViewController(_ navigationViewController: NavigationViewController, didRerouteAlong route: Route) {
        onRoutesLoaded?([
            "routes": [
                "mainRoute": convertRoute(route: route),
                "alternativeRoutes": []
            ]
        ])
    }

    func navigationViewControllerDidDismiss(
        _ navigationViewController: NavigationViewController,
        byCanceling canceled: Bool
    ) { }
}

extension UIView {
    func findViews<T: UIView>(subclassOf: T.Type) -> [T] {
        return recursiveSubviews.compactMap { $0 as? T }
    }

    var recursiveSubviews: [UIView] {
        return subviews + subviews.flatMap { $0.recursiveSubviews }
    }
}
