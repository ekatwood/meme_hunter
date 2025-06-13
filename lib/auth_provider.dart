// lib/auth_provider.dart

import 'package:flutter/material.dart';
// import 'package:firestore_functions.dart'; // Keep if you use this elsewhere
import 'smart_wallet_service.dart'; // Import your SmartWalletService
import 'package:solana/solana.dart'; // For Pubkey

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  String? _walletAddress; // Made nullable to reflect disconnected state
  String? _blockchainNetwork; // Made nullable

  // Add SmartWalletService instance
  late SmartWalletService _smartWalletService;

  // Getters
  bool get isLoggedIn => _isLoggedIn;
  String? get walletAddress => _walletAddress;
  String? get blockchainNetwork => _blockchainNetwork;
  SmartWalletService get smartWalletService => _smartWalletService; // Expose the service

  // Constructor for AuthProvider
  AuthProvider() {
    // Initialize SmartWalletService here.
    // IMPORTANT: Replace with your actual deployed program ID and GCF URL

    final programId = Pubkey.fromBase58('YOUR_DEPLOYED_PROGRAM_ID_HERE'); // <<< REPLACE THIS
    final gcfTriggerUrl = 'https://<YOUR_REGION>-<YOUR_PROJECT_ID>.cloudfunctions.net/trigger_smart_wallet_processing'; // <<< REPLACE THIS

    _smartWalletService = SmartWalletService(
      rpcUrl: 'https://api.devnet.solana.com', // Assuming Devnet RPC
      programId: programId,
      gcfTriggerUrl: gcfTriggerUrl,
    );

    // Listen to changes in SmartWalletService and notify AuthProvider's listeners
    _smartWalletService.addListener(_onSmartWalletServiceChange);
  }

  // Internal listener to propagate changes from SmartWalletService
  void _onSmartWalletServiceChange() {
    // We only care about connection status here; other details will be handled by SmartEscrowWallet itself.
    // Update AuthProvider's _isLoggedIn based on SmartWalletService's connection status.
    if (_isLoggedIn != _smartWalletService.isConnected) {
      _isLoggedIn = _smartWalletService.isConnected;
      if (_smartWalletService.isConnected) {
        _walletAddress = _smartWalletService.userWalletAddress;
        // _blockchainNetwork = 'Solana Devnet'; // Or fetch dynamically
      } else {
        _walletAddress = null;
        _blockchainNetwork = null;
      }
      notifyListeners();
    } else if (_walletAddress != _smartWalletService.userWalletAddress) {
      // Also update wallet address if it changes within the smartWalletService
      _walletAddress = _smartWalletService.userWalletAddress;
      notifyListeners();
    }
  }


  // Call this method when the user logs in / connects wallet.
  // This will now internally call smartWalletService.connectWallet()
  Future<void> login(String blockchainNetwork) async {
    try {
      // Use the smartWalletService's connectWallet method
      await _smartWalletService.connectWallet();
      _isLoggedIn = _smartWalletService.isConnected;
      _walletAddress = _smartWalletService.userWalletAddress;
      _blockchainNetwork = blockchainNetwork;
      notifyListeners(); // Notify listeners that AuthProvider state has changed
    } catch (e) {
      _isLoggedIn = false;
      _walletAddress = null;
      _blockchainNetwork = null;
      notifyListeners();
      rethrow; // Re-throw for UI to handle
    }
  }

  // Call this method when the user logs out / disconnects wallet.
  // This will now internally call smartWalletService.disconnectWallet()
  Future<void> logout() async {
    try {
      await _smartWalletService.disconnectWallet();
      _isLoggedIn = _smartWalletService.isConnected; // Should be false now
      _walletAddress = null;
      _blockchainNetwork = null;
      notifyListeners(); // Notify listeners
    } catch (e) {
      print('Error during logout: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    // Remove listener to prevent memory leaks
    _smartWalletService.removeListener(_onSmartWalletServiceChange);
    // Also dispose the SmartWalletService itself if it's no longer needed (though typically it persists with AuthProvider)
    _smartWalletService.dispose();
    super.dispose();
  }
}