import React, { useState, useEffect } from 'react';
import { View, Text, ScrollView, TouchableOpacity, StyleSheet } from 'react-native';
import { DebugState, NavigationProviderInfo } from './ExpoMapboxNavigation.types';

interface DebugPanelProps {
  getDebugState: () => Promise<DebugState>;
  getDebugLogs: () => Promise<string[]>;
  clearDebugLogs: () => Promise<void>;
  forceCleanup: () => Promise<string>;
  getNavigationProviderInfo: () => Promise<NavigationProviderInfo>;
  refreshInterval?: number;
}

export const NavigationDebugPanel: React.FC<DebugPanelProps> = ({
  getDebugState,
  getDebugLogs,
  clearDebugLogs,
  forceCleanup,
  getNavigationProviderInfo,
  refreshInterval = 1000
}) => {
  const [debugState, setDebugState] = useState<DebugState | null>(null);
  const [logs, setLogs] = useState<string[]>([]);
  const [providerInfo, setProviderInfo] = useState<NavigationProviderInfo | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const refreshDebug = async () => {
    try {
      setIsRefreshing(true);
      const [state, debugLogs, provider] = await Promise.all([
        getDebugState(),
        getDebugLogs(),
        getNavigationProviderInfo()
      ]);
      
      setDebugState(state);
      setLogs(debugLogs);
      setProviderInfo(provider);
    } catch (error) {
      console.error('Failed to get debug info:', error);
    } finally {
      setIsRefreshing(false);
    }
  };

  const handleClearLogs = async () => {
    try {
      await clearDebugLogs();
      await refreshDebug();
    } catch (error) {
      console.error('Failed to clear logs:', error);
    }
  };

  const handleForceCleanup = async () => {
    try {
      const result = await forceCleanup();
      console.log('[Debug] Force cleanup result:', result);
      await refreshDebug();
    } catch (error) {
      console.error('Failed to force cleanup:', error);
    }
  };

  useEffect(() => {
    refreshDebug();
    const interval = setInterval(refreshDebug, refreshInterval);
    return () => clearInterval(interval);
  }, [refreshInterval]);

  const getStateColor = (state: string) => {
    switch (state) {
      case 'idle': return '#4CAF50';
      case 'calculating_route': return '#FF9800';
      case 'active_navigation': return '#2196F3';
      case 'cleaning_up': return '#FF5722';
      case 'route_error': return '#F44336';
      default: return '#9E9E9E';
    }
  };

  const getInitCleanupBalance = () => {
    if (!debugState) return 'Unknown';
    const balance = debugState.initCount - debugState.cleanupCount;
    return `${balance} (${balance === 0 ? 'Balanced' : balance > 0 ? 'Leaking' : 'Over-cleaned'})`;
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Navigation Debug</Text>
        <View style={styles.refreshIndicator}>
          <Text style={[styles.refreshText, { opacity: isRefreshing ? 1 : 0.3 }]}>
            {isRefreshing ? '●' : '○'}
          </Text>
        </View>
      </View>

      {debugState && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Current State</Text>
          <View style={styles.stateRow}>
            <Text style={styles.label}>Navigation State:</Text>
            <Text style={[styles.value, { color: getStateColor(debugState.navigationState) }]}>
              {debugState.navigationState}
            </Text>
          </View>
          <View style={styles.stateRow}>
            <Text style={styles.label}>View State:</Text>
            <Text style={styles.value}>{debugState.viewState}</Text>
          </View>
          <View style={styles.stateRow}>
            <Text style={styles.label}>Init/Cleanup:</Text>
            <Text style={[styles.value, { 
              color: debugState.initCount === debugState.cleanupCount ? '#4CAF50' : '#FF5722' 
            }]}>
              {debugState.initCount}/{debugState.cleanupCount} ({getInitCleanupBalance()})
            </Text>
          </View>
          <View style={styles.stateRow}>
            <Text style={styles.label}>Route Calculations:</Text>
            <Text style={styles.value}>{debugState.routeCalcCount}</Text>
          </View>
          <View style={styles.stateRow}>
            <Text style={styles.label}>Memory Warnings:</Text>
            <Text style={[styles.value, { color: debugState.memoryWarnings > 0 ? '#FF5722' : '#4CAF50' }]}>
              {debugState.memoryWarnings}
            </Text>
          </View>
          {debugState.lastError && (
            <View style={styles.stateRow}>
              <Text style={styles.label}>Last Error:</Text>
              <Text style={[styles.value, styles.errorText]} numberOfLines={2}>
                {debugState.lastError}
              </Text>
            </View>
          )}
        </View>
      )}

      {providerInfo && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Provider Info</Text>
          <View style={styles.stateRow}>
            <Text style={styles.label}>Static Provider:</Text>
            <Text style={[styles.value, { color: providerInfo.isStatic ? '#FF5722' : '#4CAF50' }]}>
              {providerInfo.isStatic ? 'Yes (Problem!)' : 'No'}
            </Text>
          </View>
          <View style={styles.stateRow}>
            <Text style={styles.label}>Instance Hash:</Text>
            <Text style={styles.value} numberOfLines={1}>
              {providerInfo.instanceHash.substring(0, 16)}...
            </Text>
          </View>
          <View style={styles.stateRow}>
            <Text style={styles.label}>Active Components:</Text>
            <Text style={styles.value}>
              Nav: {providerInfo.hasActiveNavigation ? '✓' : '✗'} |
              Trip: {providerInfo.hasTripSession ? '✓' : '✗'} |
              View: {providerInfo.hasNavigationView ? '✓' : '✗'}
            </Text>
          </View>
        </View>
      )}

      <View style={styles.buttonRow}>
        <TouchableOpacity style={styles.button} onPress={handleForceCleanup}>
          <Text style={styles.buttonText}>Force Cleanup</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.button} onPress={handleClearLogs}>
          <Text style={styles.buttonText}>Clear Logs</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.button} onPress={refreshDebug}>
          <Text style={styles.buttonText}>Refresh</Text>
        </TouchableOpacity>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Debug Logs ({logs.length})</Text>
        <ScrollView style={styles.logContainer} showsVerticalScrollIndicator={false}>
          {logs.slice(-20).map((log, index) => (
            <Text key={index} style={styles.logLine}>
              {log}
            </Text>
          ))}
          {logs.length === 0 && (
            <Text style={styles.noLogsText}>No debug logs available</Text>
          )}
        </ScrollView>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
    borderRadius: 8,
    padding: 12,
    margin: 10,
    maxHeight: 400,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#FFFFFF',
  },
  refreshIndicator: {
    width: 20,
    alignItems: 'center',
  },
  refreshText: {
    color: '#4CAF50',
    fontSize: 12,
  },
  section: {
    marginBottom: 12,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#BBBBBB',
    marginBottom: 6,
  },
  stateRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 4,
    flexWrap: 'wrap',
  },
  label: {
    fontSize: 12,
    color: '#CCCCCC',
    flex: 1,
  },
  value: {
    fontSize: 12,
    color: '#FFFFFF',
    flex: 1,
    textAlign: 'right',
    fontFamily: 'monospace',
  },
  errorText: {
    color: '#FF5722',
    fontSize: 10,
  },
  buttonRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    marginBottom: 12,
  },
  button: {
    backgroundColor: '#2196F3',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 4,
    minWidth: 80,
  },
  buttonText: {
    color: '#FFFFFF',
    fontSize: 11,
    textAlign: 'center',
    fontWeight: 'bold',
  },
  logContainer: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    borderRadius: 4,
    padding: 8,
    maxHeight: 120,
  },
  logLine: {
    fontSize: 10,
    color: '#E0E0E0',
    fontFamily: 'monospace',
    marginBottom: 2,
    lineHeight: 12,
  },
  noLogsText: {
    fontSize: 11,
    color: '#888888',
    textAlign: 'center',
    fontStyle: 'italic',
    marginTop: 20,
  },
});

export default NavigationDebugPanel;