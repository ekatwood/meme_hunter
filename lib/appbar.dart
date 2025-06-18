import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:meme_hunter/firestore_functions.dart';
import 'auth_provider.dart';
import 'dart:js_util' as js_util;
import 'dart:html' as html;
import 'package:flutter_svg/flutter_svg.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isLoggedIn = authProvider.isLoggedIn;

    return AppBar(
      backgroundColor: const Color(0xFF800020),
      leadingWidth: 200,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GestureDetector(
          onTap: () {
            context.go('/');
          },
          child: const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Token Quest',
              style: TextStyle(
                fontFamily: 'SourceCodePro',
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (isLoggedIn)
          _buildLoggedInActions(context, authProvider)
        else
          _buildLoggedOutAction(context, authProvider),
      ],
    );
  }

  Widget _buildLoggedInActions(BuildContext context, AuthProvider authProvider) {
    return PopupMenuButton<String>(
      itemBuilder: (BuildContext context) {
        return [
          PopupMenuItem<String>(
            value: 'log_out',
            child: Text('Log Out'),
          ),
        ];
      },
      onSelected: (String value) async {
        switch (value) {
          case 'log_out':
            authProvider.logout();
            break;
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            const Icon(Icons.arrow_drop_down,color: Colors.grey,),
            const SizedBox(width: 8),
            Text(
              _truncateWalletAddress(authProvider.walletAddress),
              style: const TextStyle(fontSize: 12,color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedOutAction(BuildContext context, AuthProvider authProvider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GestureDetector(
          onTap: () {
            // Show the wallet selection dropdown
            _showWalletOptions(context, authProvider);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.0),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 40.0,
              color: Colors.white,
            ),
          )
      ),
    );
  }

  void _showWalletOptions(BuildContext context, AuthProvider authProvider) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(
        1000.0, //  Adjust as needed
        kToolbarHeight, //  Position it below the AppBar
        0.0,
        0.0,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'Solflare',
          child: Row(
            children: [
              Image.asset(
                'assets/Solflare_INSIGNIA_Obsidian_Noir.png', //  Solflare logo
                width: 24,
                height: 24,
              ),
              const SizedBox(width: 8),
              const Text('Solflare',style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'MetaMask',
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/metamask-fox.svg', //  MetaMask logo (SVG)
                width: 24,
                height: 24,
              ),
              const SizedBox(width: 8),
              const Text('MetaMask',style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    ).then((value) {
      // Handle the selected wallet
      if (value != null) {
        _connectToWallet(context, authProvider, value);
      }
    });
  }

  Future<void> _connectToWallet(
      BuildContext context, AuthProvider authProvider, String blockchain) async {
    try {
      String? result;
      if (blockchain == 'Solflare') {
        result = await js_util.promiseToFuture<String>(
          js_util.callMethod(html.window, 'connectSolflare', []),
        );
      } else if (blockchain == 'MetaMask') {
        result = await js_util.promiseToFuture<String>(
          js_util.callMethod(html.window, 'connectMetaMask', []), //  Call Metamask
        );
      }

      //print("Result from $wallet: $result"); // Debugging

      if (result == 'Solflare unavailable' || result == 'MetaMask unavailable'
          || result == 'User rejected') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$blockchain wallet unavailable. Please make sure to install the browser extension.'),
            duration: const Duration(seconds: 5),
          ),
        );
      } else if (result != null) {
        //  Assume it's the public key
        authProvider.login(result, blockchain);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to wallet.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      //print("Error connecting to $wallet: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect to $blockchain: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
      errorLogger('Failed to connect to $blockchain: $e', 'Future<void> _connectToWallet(BuildContext context, AuthProvider authProvider, String wallet) async');
    }
  }

  String _truncateWalletAddress(String address) {
    if (address.length > 10) {
      return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
    }
    return address;
  }
}



//  For sending Transaction
// Future<dynamic> sendSolanaTransaction(Transaction transaction) async {
//   try {
//     // Convert the Transaction object to a JavaScript object.
//     final jsTransaction = js_util.jsify(transaction.toJson());
//
//     // Call the JavaScript function and await the result.
//     final result = await js_util.promiseToFuture(
//       js_util.callMethod(html.window, 'signAndSendTransactionSolflare', [jsTransaction]),
//     );
//
//     if (result is Map && result.containsKey('error')) {
//       print("Error sending transaction: ${result['error']}");
//       throw Exception(result['error']); // Throw an exception to be caught in Dart
//     }
//     //  Access signature
//     final signature = result['signature'];
//     return signature;
//   } catch (e) {
//     print("Error in sendSolanaTransaction: $e");
//     throw e;
//   }
// }

// For signing transaction
// Future<Transaction?> signSolanaTransaction(Transaction transaction) async {
//   try {
//     // Convert the Transaction object to a JavaScript object.
//     final jsTransaction = js_util.jsify(transaction.toJson());
//
//     // Call the JavaScript function and await the result.
//     final result = await js_util.promiseToFuture<dynamic>(
//       js_util.callMethod(html.window, 'signTransactionSolflare', [jsTransaction]),
//     );
//
//     if (result is Map && result.containsKey('error')) {
//       print("Error signing transaction: ${result['error']}");
//       throw Exception(result['error']); // Throw for Dart
//     }
//
//     // Convert the result back to a Transaction object.  Adapt this based on the actual structure.
//     final signedTransaction = result['signedTransaction'];
//     if (signedTransaction == null) {
//       return null;
//     }
//     //  This part depends on the structure of the signedTransaction object
//     //  You'll need to adapt it based on the actual properties returned from JavaScript.
//     final signature = signedTransaction['signature'];
//
//     final transactionSignature =
//     TransactionSignature(signature: signature);
//
//     // Create a new Transaction object.  This is a placeholder.
//     final signedSolanaTransaction = Transaction(
//       signatures: [transactionSignature],
//       instructions: transaction.instructions,
//       feePayer: transaction.feePayer,
//     );
//
//     return signedSolanaTransaction;
//   } catch (e) {
//     print("Error signing transaction: $e");
//     throw e;
//   }
// }

//  For signing Message
// Future<Uint8List?> signSolanaMessage(Uint8List message) async {
//   try {
//     // Call the JavaScript function and await the result.
//     final result = await js_util.promiseToFuture(
//       js_util.callMethod(html.window, 'signMessageSolflare', [message]),
//     );
//
//     if (result is Map && result.containsKey('error')) {
//       print("Error signing message: ${result['error']}");
//       throw Exception(result['error']); // Throw for Dart
//     }
//     final signedMessageArray = result['signedMessage'];
//     if (signedMessageArray == null) {
//       return null;
//     }
//
//     // Convert the JavaScript array back to Uint8List.
//     final signedMessage = Uint8List.fromList(signedMessageArray.cast<int>());
//     return signedMessage;
//   } catch (e) {
//     print("Error signing message: $e");
//     throw e;
//   }
// }
//