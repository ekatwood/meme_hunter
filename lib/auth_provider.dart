// lib/auth_provider.dart

import 'package:flutter/material.dart';
// Conditional import for dart:html
// This ensures that dart:html is only imported when building for the web.
// For other platforms (like mobile), it will use a "stub" (effectively nothing).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html show document; // Import only what's needed from dart:html
import 'firestore_functions.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String _walletAddress = '';
  String _blockchainNetwork = '';
  ThemeMode _themeMode = ThemeMode.system; // Default to system to respect OS preference if no cookie

  bool get isLoggedIn => _isLoggedIn;
  String get walletAddress => _walletAddress;
  String get blockchainNetwork => _blockchainNetwork;
  ThemeMode get themeMode => _themeMode;

  AuthProvider() {
    _loadThemePreference(); // Load theme preference when AuthProvider is created
  }

  // --- Cookie Management Functions (Web Only) ---
  void _setThemeCookie(bool isDarkMode) {
    if (kIsWeb) { // Only execute on web platform
      final String themeValue = isDarkMode ? 'dark' : 'light';
      final DateTime expirationDate = DateTime.now().add(const Duration(days: 36500)); // Cookie expires in 100 years
      // Set the cookie
      html.document.cookie = 'themePreference=$themeValue; expires=${expirationDate.toUtc().toIso8601String()}; path=/';
    }
  }

  bool? _getThemeCookie() {
    if (kIsWeb) { // Only execute on web platform
      final String? cookies = html.document.cookie;
      if (cookies != null && cookies.isNotEmpty) {
        final List<String> cookieList = cookies.split(';');
        for (String cookie in cookieList) {
          final List<String> parts = cookie.trim().split('=');
          if (parts.length == 2 && parts[0] == 'themePreference') {
            return parts[1] == 'dark';
          }
        }
      }
    }
    return null; // No preference found or not on web
  }
  // --- End Cookie Management Functions ---

  // Load theme preference from cookie on initialization
  void _loadThemePreference() {
    final bool? isDarkMode = _getThemeCookie();
    if (isDarkMode != null) {
      _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    } else {
      // If no cookie, default to system theme.
      // This is a good default as it respects the user's OS preference.
      _themeMode = ThemeMode.system;
    }
    notifyListeners(); // Notify listeners after loading the preference
  }

  // Call this method when the user logs in.
  Future<void> login(String walletAddress, String blockchainNetwork) async {
    _isLoggedIn = true;
    _walletAddress = walletAddress;
    _blockchainNetwork = blockchainNetwork;

    //solflareWalletConnected(walletAddress); // Keep if this is used

    notifyListeners(); // Notify listeners that the state has changed.
  }

  // Call this method when the user logs out.
  void logout() {
    _isLoggedIn = false;
    _walletAddress = '';
    _blockchainNetwork = '';
    notifyListeners();
  }

  // Method to toggle theme mode and save to cookie
  void toggleThemeMode() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    _setThemeCookie(_themeMode == ThemeMode.dark); // Save the new preference to cookie
    notifyListeners(); // Notify listeners of the change
  }
}