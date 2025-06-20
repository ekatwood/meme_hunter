// lib/token_page.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // For network image loading
import 'package:provider/provider.dart'; // For AuthProvider
import 'swap_token.dart'; // Import the new SwapToken widget
import 'auth_provider.dart'; // For accessing connected wallet info

/// Represents the data structure for a Token to be displayed.
/// In a real app, this would come from your backend/database.
class TokenData {
  final String name;
  final String symbol;
  final String mintAddress;
  final String blockchainNetwork;
  final String logoUri;
  final Map<String, String> metadata;
  final List<Map<String, dynamic>> priceHistory; // List of {'x': timestamp, 'y': price}

  TokenData({
    required this.name,
    required this.symbol,
    required this.mintAddress,
    required this.blockchainNetwork,
    required this.logoUri,
    this.metadata = const {},
    this.priceHistory = const [],
  });

  // Factory constructor for stub data
  static TokenData getStubTokenData() {
    return TokenData(
      name: 'MemeCoin',
      symbol: 'MEME',
      mintAddress: 'Gk7v1c8cQpA7sF8fW6eB2x9YdZ3eH0fG1aB4c5D6e7F8', // Solana-like address
      blockchainNetwork: 'Solana',
      logoUri: 'https://placehold.co/250x250/FF8C00/FFFFFF?text=MEME', // Placeholder image
      metadata: {
        'Market Cap': '\$1,234,567,890',
        '24h Volume': '\$50,000,000',
        'Total Supply': '1,000,000,000 MEME',
        'Circulating Supply': '750,000,000 MEME',
        'Contract Type': 'SPL Token',
        'Website': 'https://memecoin.xyz',
        'Twitter': '@MemeCoinOfficial',
      },
      priceHistory: [
        {'x': DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch.toDouble(), 'y': 0.0001},
        {'x': DateTime.now().subtract(const Duration(days: 6)).millisecondsSinceEpoch.toDouble(), 'y': 0.00015},
        {'x': DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch.toDouble(), 'y': 0.00012},
        {'x': DateTime.now().subtract(const Duration(days: 4)).millisecondsSinceEpoch.toDouble(), 'y': 0.00018},
        {'x': DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch.toDouble(), 'y': 0.00016},
        {'x': DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch.toDouble(), 'y': 0.0002},
        {'x': DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch.toDouble(), 'y': 0.00019},
        {'x': DateTime.now().millisecondsSinceEpoch.toDouble(), 'y': 0.00021},
      ],
    );
  }

  static TokenData getArbitrumStubTokenData() {
    return TokenData(
      name: 'Arbitrum ETH Token',
      symbol: 'AET',
      mintAddress: '0x1234567890abcdef1234567890abcdef12345678', // Arbitrum-like address
      blockchainNetwork: 'Arbitrum',
      logoUri: 'https://placehold.co/250x250/0000FF/FFFFFF?text=AET', // Placeholder image
      metadata: {
        'Market Cap': '\$987,654,321',
        '24h Volume': '\$30,000,000',
        'Total Supply': '500,000,000 AET',
        'Circulating Supply': '400,000,000 AET',
        'Contract Type': 'ERC-20',
        'Website': 'https://aetoken.xyz',
        'Twitter': '@AETokenOfficial',
      },
      priceHistory: [
        {'x': DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch.toDouble(), 'y': 100.50},
        {'x': DateTime.now().subtract(const Duration(days: 6)).millisecondsSinceEpoch.toDouble(), 'y': 101.20},
        {'x': DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch.toDouble(), 'y': 99.80},
        {'x': DateTime.now().subtract(const Duration(days: 4)).millisecondsSinceEpoch.toDouble(), 'y': 102.50},
        {'x': DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch.toDouble(), 'y': 101.90},
        {'x': DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch.toDouble(), 'y': 103.10},
        {'x': DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch.toDouble(), 'y': 102.80},
        {'x': DateTime.now().millisecondsSinceEpoch.toDouble(), 'y': 104.00},
      ],
    );
  }
}

class TokenPage extends StatefulWidget {
  final String blockchainNetwork;
  final String mintAddress;

  const TokenPage({
    super.key,
    required this.blockchainNetwork,
    required this.mintAddress,
  });

  @override
  State<TokenPage> createState() => _TokenPageState();
}

class _TokenPageState extends State<TokenPage> {
  late TokenData _tokenData;
  List<bool> _selectedTimeFilter = [true, false, false, false, false, false]; // 1 hour, 12 hours, 1 day, 1 week, 3 months, All time

  @override
  void initState() {
    super.initState();
    // Stub out token information based on network.
    // In a real app, you would fetch this from your database or an API.
    if (widget.blockchainNetwork == 'Arbitrum') {
      _tokenData = TokenData.getArbitrumStubTokenData();
    } else { // Default to Solana stub
      _tokenData = TokenData.getStubTokenData();
    }
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
                  width: 250,
                  height: 250,
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
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('12H')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('1D')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('1W')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('1M')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('3M')),
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