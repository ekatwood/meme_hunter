import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // For network image loading
import 'package:provider/provider.dart'; // For AuthProvider
import 'package:url_launcher/url_launcher.dart'; // For launching URLs
import 'package:flutter/services.dart'; // For Clipboard
import 'package:syncfusion_flutter_charts/charts.dart'; // For charts
import 'firestore_functions.dart'; // For fetchChartData
import 'auth_provider.dart'; // For accessing connected wallet info
import 'package:meme_hunter/swap_token.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // For Timestamp type

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          'Swap Token Widget Placeholder for ${tokenSymbol}',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// Chart Data Model for Syncfusion Chart
class ChartData {
  ChartData(this.time, this.value);
  final DateTime time;
  final double value;
}

class TokenDetails extends StatefulWidget {
  final Map<String, dynamic> tokenData; // Changed to accept the full token map

  const TokenDetails({
    super.key,
    required this.tokenData,
  });

  @override
  State<TokenDetails> createState() => _TokenDetailsState();
}

class _TokenDetailsState extends State<TokenDetails> {
  List<bool> _selectedTimeFilter = [false, true, false, false, false, false]; // Default 6H selected
  List<bool> _selectedChartType = [true, false]; // Default Line chart selected (Line, Spline)

  List<Map<String, dynamic>> _rawChartData = []; // Stores the full fetched data
  List<ChartData> _filteredChartData = []; // Stores filtered data for chart
  bool _isLoadingChartData = true;

  @override
  void initState() {
    super.initState();
    _fetchAndSetChartData();
  }

  // Helper function to abbreviate address
  String _abbreviateAddress(String? address) {
    if (address == null || address.isEmpty) {
      return 'N/A';
    }
    if (address == '0x') {
      return '0x';
    }
    final int minLengthForTruncation = 10;
    if (address.length <= minLengthForTruncation) {
      return address;
    } else {
      return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
    }
  }

  // Helper function to copy text to clipboard
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Address copied to clipboard.")),
    );
  }

  // Helper function to launch URLs
  void _launchURL(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // TODO: Add error logging/snackbar if URL cannot be launched
      print('Could not launch ${url}');
    }
  }

  Future<void> _fetchAndSetChartData() async {
    setState(() {
      _isLoadingChartData = true;
    });

    final String? contractAddress = widget.tokenData['SmartContract'];
    if (contractAddress != null && contractAddress.isNotEmpty) {
      _rawChartData = await fetchChartData(contractAddress);
      _applyTimeFilterAndChartData(); // Apply filter after fetching
    } else {
      _rawChartData = [];
      // TODO: Log an error or show a message if contract address is missing
      print('Contract address is null or empty for chart data fetch.');
    }

    setState(() {
      _isLoadingChartData = false;
    });
  }

  void _applyTimeFilterAndChartData() {
    if (_rawChartData.isEmpty) {
      _filteredChartData = [];
      return;
    }

    DateTime now = DateTime.now();
    DateTime startTime;

    if (_selectedTimeFilter[0]) { // 1H
      startTime = now.subtract(const Duration(hours: 1));
    } else if (_selectedTimeFilter[1]) { // 6H
      startTime = now.subtract(const Duration(hours: 6));
    } else if (_selectedTimeFilter[2]) { // 12H
      startTime = now.subtract(const Duration(hours: 12));
    } else if (_selectedTimeFilter[3]) { // 1D
      startTime = now.subtract(const Duration(days: 1));
    } else if (_selectedTimeFilter[4]) { // 1W
      startTime = now.subtract(const Duration(days: 7));
    } else if (_selectedTimeFilter[5]) { // 3M
      startTime = now.subtract(const Duration(days: 90)); // Approx 3 months
    } else { // All time (default to showing all if no filter selected)
      startTime = DateTime.fromMillisecondsSinceEpoch(0); // Effectively all time
    }

    _filteredChartData = _rawChartData
        .where((dataPoint) {
      final timestamp = dataPoint['timestamp'];
      if (timestamp is Timestamp) {
        return timestamp.toDate().isAfter(startTime);
      } else if (timestamp is int) { // Assuming milliseconds since epoch
        return DateTime.fromMillisecondsSinceEpoch(timestamp).isAfter(startTime);
      }
      return false;
    })
        .map((dataPoint) {
      DateTime time;
      if (dataPoint['timestamp'] is Timestamp) {
        time = dataPoint['timestamp'].toDate();
      } else if (dataPoint['timestamp'] is int) {
        time = DateTime.fromMillisecondsSinceEpoch(dataPoint['timestamp']);
      } else {
        // TODO: Handle unexpected timestamp type more robustly
        time = DateTime.now();
      }
      final value = (dataPoint['open'] as num?)?.toDouble() ?? 0.0;
      return ChartData(time, value);
    })
        .toList();

    // Sort by time to ensure correct chart display
    _filteredChartData.sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final userBlockchainNetwork = authProvider.blockchainNetwork;

    final tokenName = widget.tokenData['Name'] ?? 'N/A';
    final tokenSymbol = widget.tokenData['Symbol'] ?? 'N/A';
    final mintAddress = widget.tokenData['SmartContract'] ?? 'N/A';
    final logoUrl = widget.tokenData['firebase_logo_url'];
    final totalSupply = widget.tokenData['circulating_supply'] ?? 'N/A'; // Check mapping for total vs circulating
    final marketCap = widget.tokenData['market_cap'] ?? 'N/A';
    final description = widget.tokenData['description'];
    final websiteLink = widget.tokenData['website_link'];
    final twitterLink = widget.tokenData['twitter_link'];

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, // Use card color for embedded view
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo Image
          ClipOval(
            child: CachedNetworkImage(
              imageUrl: logoUrl ?? '',
              width: 100, // Smaller logo for expanded view
              height: 100,
              fit: BoxFit.cover,
              placeholder: (context, url) => const CircularProgressIndicator(),
              errorWidget: (context, url, error) => const Icon(Icons.error_outline, size: 100),
            ),
          ),
          const SizedBox(height: 16),

          // Token Name and Symbol
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tokenName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                '(${tokenSymbol})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Contract Address
          GestureDetector(
            onTap: () => _copyToClipboard(mintAddress),
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium, // Base style
                children: [
                  const TextSpan(text: 'Contract Address: '),
                  TextSpan(
                    text: _abbreviateAddress(mintAddress),
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Total Supply
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Total Supply: ${totalSupply}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: 4),

          // Market Cap
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Market Cap: ${marketCap}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: 16),

          // Description (if available)
          if (description != null && description.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Description:',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 16),
          ],

          // Website Link (if available)
          if (websiteLink != null && websiteLink.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _launchURL(websiteLink),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Website: ${websiteLink}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],

          // Twitter Link (if available)
          if (twitterLink != null && twitterLink.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _launchURL(twitterLink),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Twitter: ${twitterLink}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Price History Chart
          Text(
            'Price History',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Time Filter ToggleButtons
          ToggleButtons(
            isSelected: _selectedTimeFilter,
            onPressed: (int index) {
              setState(() {
                for (int i = 0; i < _selectedTimeFilter.length; i++) {
                  _selectedTimeFilter[i] = i == index;
                }
                _applyTimeFilterAndChartData(); // Re-apply filter
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
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('1D')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('1W')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('3M')),
            ],
          ),
          const SizedBox(height: 16),
          // Chart Type ToggleButtons
          ToggleButtons(
            isSelected: _selectedChartType,
            onPressed: (int index) {
              setState(() {
                for (int i = 0; i < _selectedChartType.length; i++) {
                  _selectedChartType[i] = i == index;
                }
              });
            },
            borderRadius: BorderRadius.circular(8.0),
            selectedColor: Colors.white,
            fillColor: Theme.of(context).primaryColor,
            color: Theme.of(context).primaryColor,
            borderColor: Theme.of(context).primaryColor,
            selectedBorderColor: Theme.of(context).primaryColor,
            children: const <Widget>[
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Line')),
              Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Spline')),
            ],
          ),
          const SizedBox(height: 16),
          _isLoadingChartData
              ? const CircularProgressIndicator()
              : _filteredChartData.isEmpty
              ? const SizedBox(
            height: 200,
            child: Center(child: Text('No chart data available for this period.')),
          )
              : SizedBox(
            height: 300,
            child: SfCartesianChart(
              primaryXAxis: DateTimeAxis(),
              series: <ChartSeries>[
                _selectedChartType[0] // If Line chart is selected
                    ? LineSeries<ChartData, DateTime>(
                  dataSource: _filteredChartData,
                  xValueMapper: (ChartData data, _) => data.time,
                  yValueMapper: (ChartData data, _) => data.value,
                  name: 'Price',
                  enableTooltip: true,
                )
                    : SplineSeries<ChartData, DateTime>( // If Spline chart is selected
                  dataSource: _filteredChartData,
                  xValueMapper: (ChartData data, _) => data.time,
                  yValueMapper: (ChartData data, _) => data.value,
                  name: 'Price',
                  enableTooltip: true,
                ),
              ],
              tooltipBehavior: TooltipBehavior(enable: true),
            ),
          ),
          const SizedBox(height: 24),

          // Swap Token Widget (Stubbed)
          Text(
            'Swap ${tokenSymbol}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SwapToken(
            tokenBlockchainNetwork: widget.tokenData['blockchainNetwork'] ?? 'N/A', // TODO: Verify actual key for blockchainNetwork
            tokenMintAddress: mintAddress,
            tokenSymbol: tokenSymbol,
            userBlockchainNetwork: userBlockchainNetwork,
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}