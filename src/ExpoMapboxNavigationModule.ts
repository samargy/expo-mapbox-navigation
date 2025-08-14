import { requireNativeModule } from "expo-modules-core";

const ExpoMapboxNavigationModule = requireNativeModule("ExpoMapboxNavigation");

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

export interface MapboxNavigationModule {
  // Debug methods
  getDebugState(): Promise<DebugState>;
  getDebugLogs(): Promise<string[]>;
  clearDebugLogs(): Promise<void>;
  forceCleanup(): Promise<string>;
  getNavigationProviderInfo(): Promise<NavigationProviderInfo>;
  testRouteCalculation(coordinates: number[][]): Promise<string>;
  
  // Original method
  recenterMap(): Promise<void>;
}

export default ExpoMapboxNavigationModule as MapboxNavigationModule;
