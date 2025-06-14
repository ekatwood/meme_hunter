import 'package:flutter/material.dart';
import 'firestore_functions.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String _walletAddress = '';
  String _blockchainNetwork = '';

  bool get isLoggedIn => _isLoggedIn;
  String get walletAddress => _walletAddress;
  String get blockchainNetwork => _blockchainNetwork;

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
}