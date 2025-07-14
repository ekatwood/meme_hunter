// lib/token_details.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // For network image loading
import 'package:provider/provider.dart'; // For AuthProvider
import 'swap_token.dart'; // Import the new SwapToken widget
import 'auth_provider.dart'; // For accessing connected wallet info

final List<Map<String, dynamic>> priceHistory; // List of {'x': timestamp, 'y': price}

class TokenDetails extends StatefulWidget {
  final String blockchainNetwork;
  final String mintAddress;

  const TokenDetails({
    super.key,
    required this.blockchainNetwork,
    required this.mintAddress,
  });

  @override
  State<TokenDetails> createState() => _TokenDetailsState();
}

class _TokenDetailsState extends State<TokenDetails> {

  List<bool> _selectedTimeFilter = [false, true, false, false, false, false];

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // Consumer to get the connected wallet's blockchain network from AuthProvider
    final authProvider = Provider.of<AuthProvider>(context);
    final userBlockchainNetwork = authProvider.blockchainNetwork;

    return Scaffold(
      // CustomAppBar will be handled by the parent Scaffold in main.dart
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo Image
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: _tokenData.logoUri,
                  width: 180,
                  height: 180,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const CircularProgressIndicator(),
                  errorWidget: (context, url, error) => const Icon(Icons.error_outline, size: 250),
                ),
              ),
              const SizedBox(height: 24),

              // Token Name and Symbol
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _tokenData.name,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '(${_tokenData.symbol})',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.grey[700]),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Mint Address
              Text(
                'Mint Address: ${_tokenData.mintAddress}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),

              // Price History Chart Placeholder
              Text(
                'Price History on ${_tokenData.blockchainNetwork}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ToggleButtons(
                isSelected: _selectedTimeFilter,
                onPressed: (int index) {
                  setState(() {
                    for (int i = 0; i < _selectedTimeFilter.length; i++) {
                      _selectedTimeFilter[i] = i == index;
                    }
                    // TODO: Filter price history data based on selected index
                    print('Time filter changed to index $index');
                  });
                },
                borderRadius: BorderRadius.circular(8.0),
                selectedColor: Colors.white,
                fillColor: Theme.of(context).primaryColor,
                color: Theme.of(context).primaryColor,
                borderColor: Theme.of(context).primaryColor,
                selectedBorderColor: Theme.of(context).primaryColor,
                children: const <Widget>[
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('1H')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('6H')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('12H')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('24H')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('3D')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('5D')),
                ],
              ),
              const SizedBox(height: 16),
              // Chart placeholder
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Price Chart Placeholder',
                  style: TextStyle(color: Colors.grey, fontSize: 18),
                ),
              ),
              const SizedBox(height: 24),

              // Metadata Table
              Text(
                'Metadata',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _tokenData.metadata.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${entry.key}:',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Flexible(
                                child: Text(
                                  entry.value,
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Swap Token Widget
              Text(
                'Swap ${_tokenData.symbol}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // Pass the token details and user's connected blockchain network to SwapToken
              SwapToken(
                tokenBlockchainNetwork: _tokenData.blockchainNetwork,
                tokenMintAddress: _tokenData.mintAddress,
                tokenSymbol: _tokenData.symbol,
                userBlockchainNetwork: userBlockchainNetwork,
              ),
              const SizedBox(height: 48), // Extra space at bottom
            ],
          ),
        ),
      ),
    );
  }
}