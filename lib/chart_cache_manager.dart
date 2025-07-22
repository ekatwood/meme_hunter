// chart_cache_manager.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // For error logging via firestore_functions
import 'firestore_functions.dart'; // For errorLogger

class ChartCacheManager {
  static const String _cacheKeyPrefix = 'chart_data_';
  static const int _cacheDurationHours = 1; // Chart data updated once an hour
  static const int _maxCachedCharts = 10; // Limit to 10 cached charts

  // Structure for cached chart entry
  // { "data": [ { "timestamp": ..., "open": ... } ], "timestamp": "ISO8601String" }

  /// Saves chart data to cache, managing LRU and cache size limit.
  static Future<void> saveChartData(String contractAddress, List<Map<String, dynamic>> data) async {
    if (contractAddress.isEmpty || contractAddress == 'N/A') return;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String();

    final Map<String, dynamic> cacheEntry = {
      'data': data,
      'timestamp': now,
      'accessTimestamp': now, // Keep track of last access for LRU
    };
    final String encodedEntry = json.encode(cacheEntry);

    try {
      // Get all current cached chart keys to manage LRU
      final Set<String> allKeys = prefs.getKeys().where((key) => key.startsWith(_cacheKeyPrefix)).toSet();

      // If we are about to exceed the limit, find and remove the oldest
      if (allKeys.length >= _maxCachedCharts && !allKeys.contains(_cacheKeyPrefix + contractAddress)) {
        String? oldestKey;
        DateTime? oldestAccessTime;

        for (final key in allKeys) {
          final cachedString = prefs.getString(key);
          if (cachedString != null) {
            try {
              final Map<String, dynamic> decoded = json.decode(cachedString);
              final String? accessTimestampString = decoded['accessTimestamp'] as String?;
              if (accessTimestampString != null) {
                final accessTime = DateTime.parse(accessTimestampString);
                if (oldestAccessTime == null || accessTime.isBefore(oldestAccessTime)) {
                  oldestAccessTime = accessTime;
                  oldestKey = key;
                }
              }
            } catch (e) {
              // Log error but continue to process other keys
              errorLogger('Error decoding cached chart entry for LRU: $key, Error: $e', 'ChartCacheManager.saveChartData');
            }
          }
        }
        if (oldestKey != null) {
          await prefs.remove(oldestKey);
          print('Removed oldest chart from cache: $oldestKey');
        }
      }

      await prefs.setString(_cacheKeyPrefix + contractAddress, encodedEntry);
      print('Cached chart data for $contractAddress');
    } catch (e) {
      errorLogger('Error saving chart data to cache for $contractAddress: $e', 'ChartCacheManager.saveChartData');
      // If saving fails, the app will just rely on fetching from Firestore next time
    }
  }

  /// Retrieves chart data from cache. Returns null if not found or stale.
  static Future<List<Map<String, dynamic>>?> getChartData(String contractAddress) async {
    if (contractAddress.isEmpty || contractAddress == 'N/A') return null;

    final prefs = await SharedPreferences.getInstance();
    final String? cachedString = prefs.getString(_cacheKeyPrefix + contractAddress);

    if (cachedString == null) {
      return null; // Not found in cache
    }

    try {
      final Map<String, dynamic> decoded = json.decode(cachedString);
      final String? timestampString = decoded['timestamp'] as String?;
      final List<dynamic>? data = decoded['data'] as List<dynamic>?;
      final String? accessTimestampString = decoded['accessTimestamp'] as String?;

      if (timestampString == null || data == null || accessTimestampString == null) {
        // Incomplete cached data, consider it invalid
        await prefs.remove(_cacheKeyPrefix + contractAddress); // Clear invalid entry
        return null;
      }

      final cachedTime = DateTime.parse(timestampString);
      final now = DateTime.now();

      if (now.difference(cachedTime).inHours < _cacheDurationHours) {
        // Data is not stale, update access timestamp and return
        final updatedEntry = {
          'data': data,
          'timestamp': timestampString,
          'accessTimestamp': now.toIso8601String(), // Update access timestamp
        };
        await prefs.setString(_cacheKeyPrefix + contractAddress, json.encode(updatedEntry));
        print('Loaded chart data from cache for $contractAddress, updated access timestamp.');
        return List<Map<String, dynamic>>.from(data);
      } else {
        // Data is stale
        await prefs.remove(_cacheKeyPrefix + contractAddress); // Remove stale data
        print('Cached chart data for $contractAddress is stale, removed.');
        return null;
      }
    } catch (e) {
      errorLogger('Error retrieving/decoding chart data from cache for $contractAddress: $e', 'ChartCacheManager.getChartData');
      await prefs.remove(_cacheKeyPrefix + contractAddress); // Remove problematic entry
      return null;
    }
  }

  /// Clears cached chart data for tokens that are no longer in the active list.
  static Future<void> clearOldChartEntries(List<String> currentSmartContracts) async {
    final prefs = await SharedPreferences.getInstance();
    final Set<String> allCachedKeys = prefs.getKeys().where((key) => key.startsWith(_cacheKeyPrefix)).toSet();

    final Set<String> currentContractAddressesSet = currentSmartContracts.toSet();

    for (final key in allCachedKeys) {
      final contractAddress = key.substring(_cacheKeyPrefix.length);
      if (!currentContractAddressesSet.contains(contractAddress)) {
        await prefs.remove(key);
        print('Removed chart data for non-existent token: $contractAddress');
      }
    }
  }
}