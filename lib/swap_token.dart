// lib/swap_token.dart
import 'package:flutter/material.dart';
import 'dart:js_util' as js_util;
import 'dart:html' as html;
import 'gcloud_functions.dart'; // Import for getTokenPriceMoralis and getTokenPriceMoralisSOL
import 'package:flutter/services.dart'; // For TextInputFormatter

/// A widget that displays an interface for the user to swap a token.
/// The swap button's text adapts based on the user's connected blockchain network.
class SwapToken extends StatefulWidget {
  final String tokenBlockchainNetwork;
  final String tokenMintAddress;
  final String tokenSymbol;
  final String walletProvider; // From AuthProvider, can be empty string if not connected
  final String userWalletAddress; // Added to get the user's wallet address

  const SwapToken({
    super.key,
    required this.tokenBlockchainNetwork,
    required this.tokenMintAddress,
    required this.tokenSymbol,
    required this.walletProvider,
    required this.userWalletAddress,
  });

  @override
  State<SwapToken> createState() => _SwapTokenState();
}

class _SwapTokenState extends State<SwapToken> {
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  double? _availablePurchaseTokenBalance;
  double? _purchaseTokenPriceUSD;
  String _estimatedUSDAmount = '~ \$0.00';
  bool _isLoadingBalance = false;
  bool _isLoadingPrice = false;
  bool _showBalanceWarning = false;

  // WETH and SOL addresses for fetching prices and balances
  final String _wethContractAddress = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
  final String _solContractAddress = 'So11111111111111111111111111111111111111112';

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_updateConversionAndValidate);
    _fetchBalancesAndPrices();
  }

  @override
  void didUpdateWidget(covariant SwapToken oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tokenBlockchainNetwork != oldWidget.tokenBlockchainNetwork ||
        widget.walletProvider != oldWidget.walletProvider ||
        widget.userWalletAddress != oldWidget.userWalletAddress) {
      _fetchBalancesAndPrices();
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_updateConversionAndValidate);
    _amountController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<double?> _getBalanceMetaMask(String walletAddress, String contractAddress) async {
    print('_getBalanceMetaMask(String walletAddress, String contractAddress)');
    try {
      final dynamic result = await js_util.promiseToFuture(
        js_util.callMethod(html.window, 'getBalanceMetaMask', [walletAddress, contractAddress]),
      );
      if (result is double) {
        return result;
      } else if (result is int) {
        return result.toDouble();
      }
      return double.tryParse(result);
    } catch (e) {
      print("Error calling getBalanceMetaMask: $e");
      return null;
    }
  }

  Future<double?> _getBalanceSolflare(String contractAddress) async {
    try {
      double balance = await getBalanceSolflare(contractAddress);
      return balance;
    } catch (e) {
      print('Error getting balance in _getBalanceSolflare: $e');
      return null;
      // OR re-throw e;
    }
  }

  Future<void> _fetchBalancesAndPrices() async {
    setState(() {
      _isLoadingBalance = true;
      _isLoadingPrice = true;
      _availablePurchaseTokenBalance = null;
      _purchaseTokenPriceUSD = null;
      _estimatedUSDAmount = '~ \$0.00';
      _showBalanceWarning = false;
    });

    String? purchaseTokenAddress;
    String? purchaseTokenSymbol;

    if (widget.tokenBlockchainNetwork == 'ETH') {
      purchaseTokenAddress = _wethContractAddress;
      purchaseTokenSymbol = 'WETH';
    } else if (widget.tokenBlockchainNetwork == 'SOL') {
      purchaseTokenAddress = _solContractAddress;
      purchaseTokenSymbol = 'SOL';
    }

    if (purchaseTokenAddress != null && widget.userWalletAddress.isNotEmpty) {
      // Fetch balance
      if (widget.walletProvider == 'MetaMask' && widget.tokenBlockchainNetwork == 'ETH') {
        final balance = await _getBalanceMetaMask(widget.userWalletAddress, purchaseTokenAddress);
        setState(() {
          _availablePurchaseTokenBalance = balance;
          _isLoadingBalance = false;
        });
      } else if (widget.walletProvider == 'Solflare' && widget.tokenBlockchainNetwork == 'SOL') {
        final balance = await _getBalanceSolflare(widget.userWalletAddress);
        setState(() {
          _availablePurchaseTokenBalance = balance;
          _isLoadingBalance = false;
        });
      } else {
        setState(() {
          _isLoadingBalance = false;
        });
      }

      // Fetch price
      if (widget.tokenBlockchainNetwork == 'ETH' && widget.walletProvider == 'MetaMask') {
        final price = await getTokenPriceMoralis(purchaseTokenAddress,'eth');
        setState(() {
          _purchaseTokenPriceUSD = price as double?;
          _isLoadingPrice = false;
        });
      } else if (widget.tokenBlockchainNetwork == 'SOL' && widget.walletProvider == 'Solflare') {
        final price = await getTokenPriceMoralis(purchaseTokenAddress,'sol');
        setState(() {
          _purchaseTokenPriceUSD = price as double?;
          _isLoadingPrice = false;
        });
      } else {
        setState(() {
          _isLoadingPrice = false;
        });
      }
    } else {
      setState(() {
        _isLoadingBalance = false;
        _isLoadingPrice = false;
      });
    }
    _updateConversionAndValidate();
  }

  void _updateConversionAndValidate() {
    final String text = _amountController.text;
    double? amount = double.tryParse(text);

    if (_purchaseTokenPriceUSD != null && amount != null && amount >= 0) {
      _estimatedUSDAmount = '~ \$${(amount * _purchaseTokenPriceUSD!).toStringAsFixed(2)}';
    } else {
      _estimatedUSDAmount = '~ \$0.00';
    }

    if (amount != null && _availablePurchaseTokenBalance != null && amount > _availablePurchaseTokenBalance!) {
      _showBalanceWarning = true;
    } else {
      _showBalanceWarning = false;
    }

    setState(() {});
  }

  Future<void> _performSwap() async {
    print('Token to swap: ${widget.tokenSymbol} (${widget.tokenMintAddress}) on ${widget.tokenBlockchainNetwork}');
    print('Amount to swap: ${_amountController.text}');

    if(widget.tokenBlockchainNetwork == 'ETH' || widget.tokenBlockchainNetwork == 'SOL'){
      try {
        if (widget.tokenBlockchainNetwork == 'ETH') {
          // Step 1: Call the GCloud function (now in Dart) to get the 0x quote
          final quote = await get0xQuote(widget.tokenMintAddress, _amountController.text as double, widget.userWalletAddress);

          if (quote != null) {
            print('Received 0x quote: $quote');
            // Step 2: Use the quote to prompt the user to sign the transaction with MetaMask
            final dynamic txHash = await js_util.promiseToFuture(
              js_util.callMethod(
                  html.window, 'sendTransaction', [js_util.jsify(quote)]),
            );

            if (txHash != null) {
              print('Transaction successful! Hash: $txHash');
              // You can now display a success message to the user
            } else {
              print('Transaction failed or was rejected.');
              // Display an error message to the user
            }
          } else {
            print('Failed to get quote from 0x API.');
          }
        }

        if(widget.tokenBlockchainNetwork == 'SOL'){

          final Map<String, dynamic> solanaQuote = await getJupiterQuote(widget.tokenMintAddress, _amountController.text as double, widget.userWalletAddress);

          if (solanaQuote.containsKey('transaction')) {
            final String encodedTransaction = solanaQuote['transaction'];
            print("Received Solana transaction from GCloud function. Sending to Solflare...");

            // 2. Call the JavaScript function `signAndSendTransactionSolana` to interact with the wallet
            final jsTransactionSignature = await js_util.callMethod(
              html.window,
              'signAndSendTransactionSolana',
              [encodedTransaction],
            );

            if (jsTransactionSignature != null) {
              print("Swap successful! Transaction signature: $jsTransactionSignature");
            } else {
              print("Swap failed: Transaction was not signed or sent.");
            }
          } else {
            throw Exception('Invalid quote response: missing transaction data.');
          }
        }
      } catch (e) {
        print("Error during swap process: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String swapButtonText;
    bool canEnableButton = false;
    bool textFieldEnabled = false;
    String purchaseTokenDisplaySymbol = '';

    final Color primaryColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFA8415B)
        : const Color(0xFF800020);

    if (widget.tokenBlockchainNetwork == 'ETH') {
      purchaseTokenDisplaySymbol = 'WETH';
    } else if (widget.tokenBlockchainNetwork == 'SOL') {
      purchaseTokenDisplaySymbol = 'SOL';
    }

    if ((widget.walletProvider == 'Solflare' && widget.tokenBlockchainNetwork == 'SOL') ||
        (widget.walletProvider == 'MetaMask' && widget.tokenBlockchainNetwork == 'ETH')) {
      swapButtonText = 'Purchase ${widget.tokenSymbol}';
      textFieldEnabled = true;

      double? amount = double.tryParse(_amountController.text);
      if (amount != null && amount > 0 && _availablePurchaseTokenBalance != null && amount <= _availablePurchaseTokenBalance!) {
        canEnableButton = true;
      }
    } else {
      swapButtonText = 'Connect Wallet';
      textFieldEnabled = false;
    }

    String balanceDisplay = '';
    if (_isLoadingBalance) {
      balanceDisplay = 'Loading balance...';
    } else if (_availablePurchaseTokenBalance != null) {
      balanceDisplay = 'Available: ${_availablePurchaseTokenBalance!.toStringAsFixed(4)} $purchaseTokenDisplaySymbol';
    } else {
      balanceDisplay = 'Balance: N/A';
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
              'Currently displaying: ${widget.tokenSymbol} on ${widget.tokenBlockchainNetwork}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              balanceDisplay,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountController,
              focusNode: _focusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              enabled: textFieldEnabled,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
              ],
              style: const TextStyle(fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Amount of $purchaseTokenDisplaySymbol to swap',
                labelStyle: TextStyle(fontWeight: FontWeight.bold),
                floatingLabelStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: primaryColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: primaryColor, width: 2.0),
                ),
                prefixIcon: const Icon(Icons.swap_horiz),
                errorText: _showBalanceWarning ? 'Amount exceeds available balance' : null,
                errorStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.light ? Colors.grey[100] : Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('You will receive approximately:', style: TextStyle(fontWeight: FontWeight.bold)),
                  _isLoadingPrice
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Text(_estimatedUSDAmount, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: canEnableButton ? _performSwap : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                swapButtonText,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}