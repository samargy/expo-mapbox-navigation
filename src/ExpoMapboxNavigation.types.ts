import { ViewStyle, StyleProp } from "react-native/types";
import { Ref } from "react";

type ProgressEvent = {
  distanceRemaining: number;
  distanceTraveled: number;
  durationRemaining: number;
  fractionTraveled: number;
};

type Route = {
  distance: number;
  expectedTravelTime: number;
  legs: Array<{
    source?: { latitude: number; longitude: number };
    destination?: { latitude: number; longitude: number };
    steps: Array<{
      shape?: {
        coordinates: Array<{ latitude: number; longitude: number }>;
      };
    }>;
  }>;
};

type Routes = {
  mainRoute: Route;
  alternativeRoutes: Route[];
};

export type ExpoMapboxNavigationViewRef = {
  recenterMap: () => void;
  // Debug methods
  getDebugState: () => Promise<DebugState>;
  getDebugLogs: () => Promise<string[]>;
  clearDebugLogs: () => Promise<void>;
  forceCleanup: () => Promise<string>;
  getNavigationProviderInfo: () => Promise<NavigationProviderInfo>;
  testRouteCalculation: (coordinates: number[][]) => Promise<string>;
};

export interface DebugState {
  navigationState: string;
  lastError: string | null;
  initCount: number;
  cleanupCount: number;
  routeCalcCount: number;
  viewState: string;
  providerStatus: string;
  sessionStatus: string;
  memoryWarnings: number;
  providerInstanceHash: string;
}

export interface NavigationProviderInfo {
  isStatic: boolean;
  instanceHash: string;
  hasActiveNavigation: boolean;
  hasTripSession: boolean;
  hasNavigationView: boolean;
}

export type ExpoMapboxNavigationViewProps = {
  ref?: Ref<ExpoMapboxNavigationViewRef>;
  coordinates: Array<{ latitude: number; longitude: number }>;
  waypointIndices?: number[];
  useRouteMatchingApi?: boolean;
  locale?: string;
  routeProfile?: string;
  routeExcludeList?: string[];
  mapStyle?: string;
  mute?: boolean;
  vehicleMaxHeight?: number;
  vehicleMaxWidth?: number;
  initialLocation?: { latitude: number; longitude: number; zoom?: number };
  onRouteProgressChanged?: (event: { nativeEvent: ProgressEvent }) => void;
  onCancelNavigation?: () => void;
  onWaypointArrival?: (event: {
    nativeEvent: ProgressEvent | undefined;
  }) => void;
  onFinalDestinationArrival?: () => void;
  onRouteChanged?: () => void;
  onUserOffRoute?: () => void;
  onRoutesLoaded?: (event: { nativeEvent: { routes: Routes } }) => void;
  onRouteFailedToLoad?: (event: {
    nativeEvent: { errorMessage: string };
  }) => void;
  style?: StyleProp<ViewStyle>;
};
