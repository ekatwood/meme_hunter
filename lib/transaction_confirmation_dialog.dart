import 'package:flutter/material.dart';
import 'dart:html' as html; // Required for web navigation

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

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 30),
          SizedBox(width: 10),
          Text(
            'Transaction Confirmed!',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            Text(
              'Your transaction has been successfully processed on the $network network.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 15),
            Text(
              'View on $explorerName:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            // The transaction hash is now wrapped in a GestureDetector to make it clickable.
            GestureDetector(
              onTap: () => _launchBlockExplorer(txHash, network),
              child: Text(
                txHash,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.blue, // Indicates a link
                  decoration: TextDecoration.underline, // Underline to indicate link
                ),
              ),
            ),
            const SizedBox(height: 5),
          ],
        ),
      ),
      actions: <Widget>[
        // The "OK" button to close the dialog
        TextButton(
          onPressed: () {
            // Dismisses the modal
            Navigator.of(context).pop();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.0),
            child: Text(
              'OK',
              style: TextStyle(
                fontSize: 16,
                color: Colors.deepPurple,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
