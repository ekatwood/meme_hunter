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
  final String? walletProvider; // From AuthProvider, can be null if not connected
  final String? userWalletAddress; // Added to get the user's wallet address

  const SwapToken({
    super.key,
    required this.tokenBlockchainNetwork,
    required this.tokenMintAddress,
    required this.tokenSymbol,
    this.walletProvider,
    this.userWalletAddress, // Added to constructor
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
  // Note: For SOL, we often use the wSOL (wrapped SOL) address for smart contract interactions,
  // as native SOL isn't an ERC-20 token. The price APIs might handle this internally or
  // refer to the wSOL price as effectively the SOL price.
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
    // Re-fetch balances and prices if the network or wallet address changes
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

  // Calls the MetaMask JavaScript function to get ERC-20 token balance
  Future<double?> _getBalanceMetaMask(String walletAddress, String contractAddress) async {
    try {
      final dynamic result = await js_util.promiseToFuture(
        js_util.callMethod(html.window, 'getBalanceMetaMask', [walletAddress, contractAddress]),
      );
      if (result is double) {
        return result;
      } else if (result is int) { // Handle cases where JS might return an integer
        return result.toDouble();
      }
      return null;
    } catch (e) {
      print("Error calling getBalanceMetaMask: $e");
      return null;
    }
  }

  // Stub for getting Solflare balance (from gcloud_functions.dart)
  Future<double?> _getBalanceSolflare(String contractAddress) async {
    // This calls the stubbed function from gcloud_functions.dart
    // In a real app, this would be an async call to a cloud function
    // that interacts with the Solana blockchain.
    return getBalanceSolflare(contractAddress); // Assuming this is now async or returns Future<double?>
  }

  // Fetches balances and prices based on the connected network
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
      purchaseTokenAddress = _solContractAddress; // Using wSOL address for consistency
      purchaseTokenSymbol = 'SOL';
    }

    if (purchaseTokenAddress != null && widget.userWalletAddress != null && widget.userWalletAddress!.isNotEmpty) {
      // Fetch balance
      if (widget.walletProvider == 'MetaMask' && widget.tokenBlockchainNetwork == 'ETH') {
        final balance = await _getBalanceMetaMask(widget.userWalletAddress!, purchaseTokenAddress);
        setState(() {
          _availablePurchaseTokenBalance = balance;
          _isLoadingBalance = false;
        });
      } else if (widget.walletProvider == 'Solflare' && widget.tokenBlockchainNetwork == 'SOL') {
        final balance = await _getBalanceSolflare(purchaseTokenAddress);
        setState(() {
          _availablePurchaseTokenBalance = balance;
          _isLoadingBalance = false;
        });
      } else {
        // Mismatch or unsupported network
        setState(() {
          _isLoadingBalance = false;
        });
      }

      // Fetch price
      if (widget.tokenBlockchainNetwork == 'ETH') {
        final price = getTokenPriceMoralis(purchaseTokenAddress); // This is currently sync/stubbed
        setState(() {
          _purchaseTokenPriceUSD = price;
          _isLoadingPrice = false;
        });
      } else if (widget.tokenBlockchainNetwork == 'SOL') {
        final price = getTokenPriceMoralisSOL(purchaseTokenAddress); // This is currently sync/stubbed
        setState(() {
          _purchaseTokenPriceUSD = price;
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
    _updateConversionAndValidate(); // Recalculate based on new balance/price
  }

  // Updates the estimated USD conversion and validates the input amount
  void _updateConversionAndValidate() {
    final String text = _amountController.text;
    double? amount = double.tryParse(text);

    if (_purchaseTokenPriceUSD != null && amount != null && amount >= 0) {
      _estimatedUSDAmount = '~ \$${(amount * _purchaseTokenPriceUSD!).toStringAsFixed(2)}';
    } else {
      _estimatedUSDAmount = '~ \$0.00';
    }

    // Validate amount against available balance
    if (amount != null && _availablePurchaseTokenBalance != null && amount > _availablePurchaseTokenBalance!) {
      _showBalanceWarning = true;
    } else {
      _showBalanceWarning = false;
    }

    setState(() {}); // Update the UI
  }

  /// Stubs out the swap button's functionality.
  /// This method will be implemented later to call the appropriate swap API.
  void _performSwap() {
    // TODO: Implement actual swap logic here.
    // This will involve calling Jupiter API for Solana or 1inch API for Arbitrum.
    // Use tokenBlockchainNetwork and userBlockchainNetwork to determine the path.
    print('Swap button pressed!');
    print('Token to swap: ${widget.tokenSymbol} (${widget.tokenMintAddress}) on ${widget.tokenBlockchainNetwork}');
    print('User connected to: ${widget.walletProvider ?? 'N/A'}');
    print('Amount to swap: ${_amountController.text}');
    print('Estimated USD: $_estimatedUSDAmount');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Swap for ${widget.tokenSymbol} stubbed out!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    String swapButtonText;
    bool canEnableButton = false;
    bool textFieldEnabled = false;
    String purchaseTokenDisplaySymbol = ''; // To display WETH or SOL

    // Determine purchase token display symbol
    if (widget.tokenBlockchainNetwork == 'ETH') {
      purchaseTokenDisplaySymbol = 'WETH';
    } else if (widget.tokenBlockchainNetwork == 'SOL') {
      purchaseTokenDisplaySymbol = 'SOL';
    }

    // Determine button text and enablement based on wallet connection and network
    if (widget.walletProvider == widget.tokenBlockchainNetwork) {
      if (widget.walletProvider == 'Solflare' || widget.walletProvider == 'MetaMask') {
        swapButtonText = 'Purchase ${widget.tokenSymbol}';
        textFieldEnabled = true;

        // Check if amount is valid for enabling the button
        double? amount = double.tryParse(_amountController.text);
        if (amount != null && amount > 0 && _availablePurchaseTokenBalance != null && amount <= _availablePurchaseTokenBalance!) {
          canEnableButton = true;
        }
      } else {
        // This case should ideally not be hit if userBlockchainNetwork is strictly Solflare or MetaMask
        swapButtonText = 'Connected Wallet';
        textFieldEnabled = false;
      }
    } else if (widget.walletProvider != null && widget.walletProvider!.isNotEmpty) {
      // User is connected, but to a different network
      swapButtonText = 'Connect to ${widget.tokenBlockchainNetwork} to swap';
      textFieldEnabled = false;
    } else {
      // User is not connected
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
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              balanceDisplay,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountController,
              focusNode: _focusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              enabled: textFieldEnabled,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')), // Allow only numbers and a single decimal point
              ],
              decoration: InputDecoration(
                labelText: 'Amount of $purchaseTokenDisplaySymbol to swap',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.currency_bitcoin),
                errorText: _showBalanceWarning ? 'Amount exceeds available balance' : null,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('You will receive approximately:', style: TextStyle(fontWeight: FontWeight.w500)),
                  _isLoadingPrice
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Text(_estimatedUSDAmount, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: canEnableButton ? _performSwap : null, // Disable if cannot swap
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
