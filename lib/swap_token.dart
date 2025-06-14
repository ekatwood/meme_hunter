// lib/swap_token.dart

import 'package:flutter/material.dart';

/// A widget that displays an interface for the user to swap a token.
/// The swap button's text adapts based on the user's connected blockchain network.
class SwapToken extends StatelessWidget {
  final String tokenBlockchainNetwork;
  final String tokenMintAddress;
  final String tokenSymbol;
  final String? userBlockchainNetwork; // From AuthProvider, can be null if not connected

  const SwapToken({
    super.key,
    required this.tokenBlockchainNetwork,
    required this.tokenMintAddress,
    required this.tokenSymbol,
    this.userBlockchainNetwork,
  });

  /// Stubs out the swap button's functionality.
  /// This method will be implemented later to call the appropriate swap API.
  void _performSwap() {
    // TODO: Implement actual swap logic here.
    // This will involve calling Jupiter API for Solana or 1inch API for Arbitrum.
    // Use tokenBlockchainNetwork and userBlockchainNetwork to determine the path.
    print('Swap button pressed!');
    print('Token to swap: $tokenSymbol ($tokenMintAddress) on $tokenBlockchainNetwork');
    print('User connected to: ${userBlockchainNetwork ?? 'N/A'}');

    // Example: Show a snackbar message
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(content: Text('Swap for $tokenSymbol stubbed out!')),
    // );
  }

  @override
  Widget build(BuildContext context) {
    String swapButtonText;
    bool canSwap = true;

    // Determine swap button text based on user's connected wallet network
    if (userBlockchainNetwork == 'Solflare' && tokenBlockchainNetwork == 'Solana') {
      swapButtonText = 'Swap for SOL';
    } else if (userBlockchainNetwork == 'MetaMask' && tokenBlockchainNetwork == 'Arbitrum') {
      swapButtonText = 'Swap for ETH';
    } else if (userBlockchainNetwork != null) {
      // User is connected, but to a different network
      swapButtonText = 'Connect to ${tokenBlockchainNetwork} to swap';
      canSwap = false;
    } else {
      // User is not connected
      swapButtonText = 'Connect Wallet to Swap';
      canSwap = false;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(
              'Swap Interface',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Currently displaying: $tokenSymbol on $tokenBlockchainNetwork',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount of ${tokenSymbol} to swap',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.currency_bitcoin),
              ),
            ),
            const SizedBox(height: 16),
            // Placeholder for "You will receive"
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('You will receive approximately:', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text('~0.00 SOL/ETH', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: canSwap ? _performSwap : null, // Disable if cannot swap
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                swapButtonText,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}