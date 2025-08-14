import ExpoModulesCore

public class ExpoMapboxNavigationModule: Module {

  public func definition() -> ModuleDefinition {
    Name("ExpoMapboxNavigation")

    View(ExpoMapboxNavigationView.self) {
      Events("onRouteProgressChanged", "onCancelNavigation", "onWaypointArrival", "onFinalDestinationArrival", "onRouteChanged", "onUserOffRoute", "onRoutesLoaded", "onRouteFailedToLoad")

      Prop("coordinates") { (view: ExpoMapboxNavigationView, coordinates: Array<Dictionary<String, Any>>) in
         var points: Array<CLLocationCoordinate2D> = []
         for coordinate in coordinates {
            let longValue = coordinate["longitude"]
            let latValue = coordinate["latitude"]
            if let long = longValue as? Double, let lat = latValue as? Double {
                points.append(CLLocationCoordinate2D(latitude: lat, longitude: long))
            }
          }
          view.controller.setCoordinates(coordinates: points) 
      }

      Prop("vehicleMaxHeight") { (view: ExpoMapboxNavigationView, maxHeight: Double?) in
          view.controller.setVehicleMaxHeight(maxHeight: maxHeight)
      }

      Prop("vehicleMaxWidth") { (view: ExpoMapboxNavigationView, maxWidth: Double?) in
          view.controller.setVehicleMaxWidth(maxWidth: maxWidth)
      }

      Prop("locale") { (view: ExpoMapboxNavigationView, locale: String?) in
          view.controller.setLocale(locale: locale) 
      }

      Prop("useRouteMatchingApi"){ (view: ExpoMapboxNavigationView, useRouteMatchingApi: Bool?) in
          view.controller.setIsUsingRouteMatchingApi(useRouteMatchingApi: useRouteMatchingApi) 
      }

      Prop("waypointIndices"){ (view: ExpoMapboxNavigationView, indices: Array<Int>?) in
          view.controller.setWaypointIndices(waypointIndices: indices) 
      }

      Prop("routeProfile"){ (view: ExpoMapboxNavigationView, profile: String?) in
          view.controller.setRouteProfile(profile: profile) 
      }

      Prop("routeExcludeList"){ (view: ExpoMapboxNavigationView, excludeList: Array<String>?) in
          view.controller.setRouteExcludeList(excludeList: excludeList) 
      }

      Prop("mapStyle"){ (view: ExpoMapboxNavigationView, style: String?) in
          view.controller.setMapStyle(style: style) 
      }

      Prop("mute"){ (view: ExpoMapboxNavigationView, isMuted: Bool?) in
          view.controller.setIsMuted(isMuted: isMuted) 
      }

      Prop("initialLocation") { (view: ExpoMapboxNavigationView, location: Dictionary<String, Any>?) in
        if(location != nil){
          let longValue = location!["longitude"]
          let latValue = location!["latitude"]
          let zoomValue = location!["zoom"]
          if let long = longValue as? Double, let lat = latValue as? Double, let zoom = zoomValue as? Double? {
              view.controller.setInitialLocation(location: CLLocationCoordinate2D(latitude: lat, longitude: long), zoom: zoom)
          }
        }
      }

      AsyncFunction("recenterMap") { (view: ExpoMapboxNavigationView) in
        view.controller.recenterMap()
      }

      // Debug Bridge Methods
      AsyncFunction("getDebugState") { (view: ExpoMapboxNavigationView) -> [String: Any] in
        return [
          "navigationState": view.controller.navigationState,
          "lastError": view.controller.lastError ?? NSNull(),
          "initCount": view.controller.initializationCount,
          "cleanupCount": view.controller.cleanupCount,
          "routeCalcCount": view.controller.routeCalculationCount,
          "viewState": view.controller.viewLifecycleState,
          "providerStatus": view.controller.getProviderStatus(),
          "sessionStatus": view.controller.getSessionStatus(),
          "memoryWarnings": view.controller.memoryWarningCount,
          "providerInstanceHash": view.controller.providerInstanceHash
        ]
      }

      AsyncFunction("getDebugLogs") { (view: ExpoMapboxNavigationView) -> [String] in
        return view.controller.debugLog
      }

      AsyncFunction("clearDebugLogs") { (view: ExpoMapboxNavigationView) -> Void in
        view.controller.debugLog.removeAll()
        view.controller.addDebugLog("Debug logs cleared")
      }

      AsyncFunction("forceCleanup") { (view: ExpoMapboxNavigationView) -> String in
        view.controller.forceCleanup()
        return "Cleanup initiated"
      }

      AsyncFunction("getNavigationProviderInfo") { (view: ExpoMapboxNavigationView) -> [String: Any] in
        return [
          "isStatic": true, // Since it's currently static
          "instanceHash": view.controller.providerInstanceHash,
          "hasActiveNavigation": view.controller.navigation != nil,
          "hasTripSession": view.controller.tripSession != nil,
          "hasNavigationView": view.controller.navigationViewController != nil
        ]
      }

      AsyncFunction("testRouteCalculation") { (view: ExpoMapboxNavigationView, coords: [[Double]]) -> String in
        view.controller.testRouteCalculation(coords)
        return "Route calculation test initiated"
      }
    }
  }
}