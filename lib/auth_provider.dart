// lib/auth_provider.dart

import 'package:flutter/material.dart';
import 'firestore_functions.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String _walletAddress = '';
  String _blockchainNetwork = '';
  // NEW: Add theme mode state, defaulting to light
  ThemeMode _themeMode = ThemeMode.light;

  bool get isLoggedIn => _isLoggedIn;
  String get walletAddress => _walletAddress;
  String get blockchainNetwork => _blockchainNetwork;
  // NEW: Getter for theme mode
  ThemeMode get themeMode => _themeMode;

  // Call this method when the user logs in.
  Future<void> login(String walletAddress, String blockchainNetwork) async {
    _isLoggedIn = true;
    _walletAddress = walletAddress;
    _blockchainNetwork = blockchainNetwork;

    //solflareWalletConnected(walletAddress);

    notifyListeners(); // Notify listeners that the state has changed.
  }

  // Call this method when the user logs out.
  void logout() {
    _isLoggedIn = false;
    _walletAddress = '';
    _blockchainNetwork = '';
    notifyListeners();
  }

  // NEW: Method to toggle theme mode
  void toggleThemeMode() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}