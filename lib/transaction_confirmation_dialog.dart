// transaction_confirmation_dialog.dart
import 'package:flutter/material.dart';
import 'dart:html' as html;

/// A widget that displays a transaction confirmation pop-up.
class TransactionConfirmationDialog extends StatelessWidget {
  final String txHash;
  final String network; // 'ETH' or 'SOL'

  /// Creates a confirmation dialog for a blockchain transaction.
  const TransactionConfirmationDialog({
    super.key,
    required this.txHash,
    required this.network,
  });

  /// Function to construct the block explorer URL and open it in a new browser tab.
  void _launchBlockExplorer(String hash, String net) {
    String baseUrl;

    if (net == 'ETH') {
      baseUrl = 'https://etherscan.io/tx/';
    } else if (net == 'SOL') {
      baseUrl = 'https://solscan.io/tx/';
    } else {
      // Default or fallback URL
      baseUrl = 'https://etherscan.io/tx/';
    }

    final url = '$baseUrl$hash';

    // Use dart:html to open the URL in a new tab ('_blank') for web environments.
    html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    String explorerName = network == 'SOL' ? 'Solscan' : 'Etherscan';

    // Determine the Primary Color based on the current Brightness (Theme)
    final Color primaryColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFA8415B) // _lightModeColor
        : const Color(0xFF800020); // _darkModeColor

    // Use a Dialog with a custom child instead of AlertDialog for full style control
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
        maxWidth: 760, // Sets the maximum width to 740px
        ),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Container(
            // Background Color: Use Theme.of(context).cardColor
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Title Row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 30),
                    const SizedBox(width: 10),
                    Text(
                      'Transaction Confirmed!',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        // Text Color: Use Primary Color for emphasis
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.black // Black for light mode
                            : Colors.white, // White for dark mode
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Content Body - uses default theme text colors
                Text(
                  'Your transaction has been successfully processed on the $network network.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 15),
                Text(
                  'View on $explorerName:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                // Transaction Hash Link
                GestureDetector(
                  onTap: () => _launchBlockExplorer(txHash, network),
                  child: Text(
                    txHash,
                    style: const TextStyle(
                      //fontFamily: 'monospace',
                      color: Colors.blue,
                      //decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Action Button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      // 1. Set the background color to the dynamic primaryColor
                      backgroundColor: primaryColor,
                      elevation: 4, // Optional: Add a subtle shadow
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Text(
                        'OK',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}