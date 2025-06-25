// auth_provider.dart:
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html show document;
import 'firestore_functions.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String _walletAddress = '';
  String _blockchainNetwork = '';
  ThemeMode _themeMode = ThemeMode.system;
  bool _isSolana = false; // New state variable for blockchain preference

  bool get isLoggedIn => _isLoggedIn;
  String get walletAddress => _walletAddress;
  String get blockchainNetwork => _blockchainNetwork;
  ThemeMode get themeMode => _themeMode;
  bool get isSolana => _isSolana; // Getter for blockchain preference

  AuthProvider() {
    _loadThemePreference();
    _loadBlockchainPreference(); // Load blockchain preference when AuthProvider is created
  }

  // --- Cookie Management Functions (Web Only) ---
  void _setThemeCookie(bool isDarkMode) {
    if (kIsWeb) {
      final String themeValue = isDarkMode ? 'dark' : 'light';
      final DateTime expirationDate = DateTime.now().add(const Duration(days: 36500));
      html.document.cookie = 'themePreference=$themeValue; expires=${expirationDate.toUtc().toIso8601String()}; path=/';
    }
  }

  bool? _getThemeCookie() {
    if (kIsWeb) {
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
    return null;
  }

  // New: Set blockchain preference cookie
  void _setBlockchainCookie(bool isSolana) {
    if (kIsWeb) {
      final String blockchainValue = isSolana ? 'solana' : 'ethereum';
      final DateTime expirationDate = DateTime.now().add(const Duration(days: 36500));
      html.document.cookie = 'blockchainPreference=$blockchainValue; expires=${expirationDate.toUtc().toIso8601String()}; path=/';
    }
  }

  // New: Get blockchain preference cookie
  bool? _getBlockchainCookie() {
    if (kIsWeb) {
      final String? cookies = html.document.cookie;
      if (cookies != null && cookies.isNotEmpty) {
        final List<String> cookieList = cookies.split(';');
        for (String cookie in cookieList) {
          final List<String> parts = cookie.trim().split('=');
          if (parts.length == 2 && parts[0] == 'blockchainPreference') {
            return parts[1] == 'solana';
          }
        }
      }
    }
    return null;
  }
  // --- End Cookie Management Functions ---

  void _loadThemePreference() {
    final bool? isDarkMode = _getThemeCookie();
    if (isDarkMode != null) {
      _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  // New: Load blockchain preference from cookie on initialization
  void _loadBlockchainPreference() {
    final bool? isSolanaPreference = _getBlockchainCookie();
    if (isSolanaPreference != null) {
      _isSolana = isSolanaPreference;
    } else {
      _isSolana = false; // Default to Ethereum if no cookie is found
    }
    notifyListeners();
  }

  Future<void> login(String walletAddress, String blockchainNetwork) async {
    _isLoggedIn = true;
    _walletAddress = walletAddress;
    _blockchainNetwork = blockchainNetwork;
    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    _walletAddress = '';
    _blockchainNetwork = '';
    notifyListeners();
  }

  void toggleThemeMode() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    _setThemeCookie(_themeMode == ThemeMode.dark);
    notifyListeners();
  }

  // New: Method to set blockchain preference and save to cookie
  void setBlockchainPreference(bool isSolana) {
    _isSolana = isSolana;
    _setBlockchainCookie(isSolana); // Save the new preference to cookie
    notifyListeners(); // Notify listeners of the change
  }
}