// token_details.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // For network image loading
import 'package:provider/provider.dart'; // For AuthProvider
import 'package:flutter/services.dart'; // For Clipboard
import 'package:syncfusion_flutter_charts/charts.dart'; // For charts
import 'firestore_functions.dart'; // For fetchChartData
import 'auth_provider.dart'; // For accessing connected wallet info
import 'utils.dart';
import 'package:meme_hunter/swap_token.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // For Timestamp type
import 'token_data.dart'; // NEW: Import the TokenData class

// Chart Data Model for Syncfusion Chart
class ChartData {
  ChartData(this.time, this.value);
  final DateTime time;
  final double value;
}

class TokenDetails extends StatefulWidget {
  // MODIFIED: tokenData type changed to TokenData
  final TokenData tokenData;

  const TokenDetails({
    super.key,
    required this.tokenData,
  });

  @override
  State<TokenDetails> createState() => _TokenDetailsState();
}

class _TokenDetailsState extends State<TokenDetails> {

  final _wethAddress = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';

  // Default 6H selected, but will be overridden by cookie
  List<bool> _selectedTimeFilter = [false, true, false, false, false, false];

  List<Map<String, dynamic>> _rawChartData = []; // Stores the full fetched data
  List<ChartData> _filteredChartData = []; // Stores filtered data for chart
  bool _isLoadingChartData = true;

  final _darkModeColor = Color(0xFF800020);
  final _lightModeColor = const Color(0xFFA8415B);

  @override
  void initState() {
    super.initState();
    _loadChartTimePreference(); // Load preference when state initializes
    _fetchAndSetChartData();
  }

  // New: Load chart time preference from cookie
  void _loadChartTimePreference() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final int? savedIndex = authProvider.getChartTimeCookie(); // Access the private method
    if (savedIndex != null && savedIndex >= 0 && savedIndex < _selectedTimeFilter.length) {
      setState(() {
        _selectedTimeFilter = List.generate(_selectedTimeFilter.length, (i) => i == savedIndex);
      });
    }
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

  Future<void> _fetchAndSetChartData() async {
    setState(() {
      _isLoadingChartData = true;
    });

    // MODIFIED: Access SmartContract directly from tokenData object
    final String? contractAddress = widget.tokenData.smartContract;
    if (contractAddress != null && contractAddress.isNotEmpty && contractAddress != 'N/A') {
      // TODO: use contractAddress, for now hard coding to what is in the db
      _rawChartData = await fetchChartData('0x95af4af910c28e8ece4512bfe46f1f33687424ce');
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

  // Helper to parse dynamic timestamp into DateTime
  DateTime? _parseDynamicTimestamp(dynamic timestampData) {
    if (timestampData is Timestamp) { //
      return timestampData.toDate();
    } else if (timestampData is int) { //
      return DateTime.fromMillisecondsSinceEpoch(timestampData);
    } else if (timestampData is String) { //
      try {
        return DateTime.parse(timestampData);
      } catch (e) {
        print('Error parsing timestamp string: $e');
        return null; // Indicate parsing failure
      }
    }
    print('Unexpected timestamp type: ${timestampData.runtimeType}');
    return null; // Return null for unsupported types
  }

  void _applyTimeFilterAndChartData() {
    if (_rawChartData.isEmpty) {
      _filteredChartData = [];
      return;
    }

    // Step 1: Parse all raw timestamps and find the absolute latest timestamp in your data
    // This will be our dynamic "current" time reference
    DateTime? latestDataTimestamp;
    List<ChartData> tempChartData = []; // To store parsed data for finding max and then filtering

    for (var dataPoint in _rawChartData) {
      final DateTime? parsedTime = _parseDynamicTimestamp(dataPoint['timestamp']);
      final double? value = (dataPoint['open'] as num?)?.toDouble();

      if (parsedTime != null && value != null) {
        tempChartData.add(ChartData(parsedTime, value));
        if (latestDataTimestamp == null || parsedTime.isAfter(latestDataTimestamp)) {
          latestDataTimestamp = parsedTime;
        }
      }
    }

    // If no valid timestamps found, return empty
    if (latestDataTimestamp == null) {
      _filteredChartData = [];
      return;
    }

    // Step 2: Determine the start time for the filter based on the latestDataTimestamp
    DateTime startTime;
    int skipInterval = 1; // Default to no skipping

    if (_selectedTimeFilter[0]) { // 1H
      startTime = latestDataTimestamp.subtract(const Duration(hours: 1));
      skipInterval = 1;
    } else if (_selectedTimeFilter[1]) { // 6H
      startTime = latestDataTimestamp.subtract(const Duration(hours: 6));
      skipInterval = 3;
    } else if (_selectedTimeFilter[2]) { // 12H
      startTime = latestDataTimestamp.subtract(const Duration(hours: 12));
      skipInterval = 6;
    } else if (_selectedTimeFilter[3]) { // 1D
      startTime = latestDataTimestamp.subtract(const Duration(days: 1));
      skipInterval = 10;
    } else if (_selectedTimeFilter[4]) { // 1W
      startTime = latestDataTimestamp.subtract(const Duration(days: 7));
      skipInterval = 27;
    } else if (_selectedTimeFilter[5]) { // 2W
      startTime = latestDataTimestamp.subtract(const Duration(days: 14));
      skipInterval = 55;
    } else { // All time (show all data if no specific filter is active or for fallback)
      startTime = DateTime.fromMillisecondsSinceEpoch(0); // Effectively the beginning of time
    }

    // Step 3: Filter the data using the calculated startTime
    List<ChartData> filteredByTime = tempChartData
        .where((chartData) => chartData.time.isAfter(startTime) || chartData.time.isAtSameMomentAs(startTime))
        .toList();

    // Step 4: Sort by time to ensure correct chart display
    filteredByTime.sort((a, b) => a.time.compareTo(b.time));

    // Step 5: Apply the thinning logic
    _filteredChartData = [];
    if (skipInterval <= 1) {
      _filteredChartData = filteredByTime;
    } else {
      for (int i = 0; i < filteredByTime.length; i++) {
        if (i % skipInterval == 0) {
          _filteredChartData.add(filteredByTime[i]);
        }
      }
    }

    setState(() {}); // Ensure UI updates
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final walletProvider = authProvider.walletProvider;
    final userWalletAddress = authProvider.walletAddress;

    // MODIFIED: Access properties directly from widget.tokenData
    final tokenName = widget.tokenData.name;
    final tokenSymbol = widget.tokenData.symbol;
    final mintAddress = widget.tokenData.smartContract;
    final logoUrl = widget.tokenData.firebaseLogoUrl;
    final circulatingSupply = widget.tokenData.circulatingSupply;
    final marketCap = widget.tokenData.marketCap;
    final description = widget.tokenData.description;
    final websiteLink = widget.tokenData.websiteLink;
    final twitterLink = widget.tokenData.twitterLink;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, // Use card color for embedded view
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      // Wrap the content with SingleChildScrollView and SafeArea
      child: SafeArea( //
        child: SingleChildScrollView( //
          child: Column( //
            crossAxisAlignment: CrossAxisAlignment.center, //
            children: [
              // Add a close button at the top right of the modal
              Align( //
                alignment: Alignment.topRight, //
                child: IconButton( //
                  icon: const Icon(Icons.close), //
                  onPressed: () => Navigator.of(context).pop(), // Close the modal
                ),
              ),
              const SizedBox(height: 16), //

              // Logo Image
              ClipOval( //
                child: CachedNetworkImage( //
                  imageUrl: logoUrl ?? '', // Use logoUrl directly
                  width: 120, // Smaller logo for expanded view
                  height: 120, //
                  fit: BoxFit.cover, //
                  placeholder: (context, url) => const CircularProgressIndicator(), //
                  errorWidget: (context, url, error) => const Icon(Icons.error_outline, size: 100), //
                ),
              ),
              const SizedBox(height: 16), //

              // Token Name and Symbol
              Row( //
                mainAxisAlignment: MainAxisAlignment.center, //
                children: [ //
                  Text( //
                    tokenName, // Use tokenName directly
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), //
                  ),
                  const SizedBox(width: 8), //
                  Text( //
                    '(${tokenSymbol})', // Use tokenSymbol directly
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), //
                  ),
                ],
              ),
              const SizedBox(height: 8), //

              // Contract Address
              GestureDetector( //
                onTap: () => copyToClipboard(mintAddress, context), // Use mintAddress directly
                child: RichText( //
                  text: TextSpan( //
                    style: Theme.of(context).textTheme.bodyMedium, // Base style
                    children: [ //
                      const TextSpan(text: 'Contract Address: '), //
                      TextSpan( //
                        text: _abbreviateAddress(mintAddress), // Use mintAddress directly
                        style: const TextStyle( //
                          color: Colors.blue, //
                          //decoration: TextDecoration.underline, //
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16), //

              // Total Supply
              Align( //
                alignment: Alignment.centerLeft, //
                child: Text( //
                  'Total Supply: ${circulatingSupply}', // Use the formatted circulating supply
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold), //
                ),
              ),
              const SizedBox(height: 4), //

              // Market Cap
              Align( //
                alignment: Alignment.centerLeft, //
                child: Text( //
                  'Market Capitalization: \$''${marketCap}', // Use formatted market cap
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold), //
                ),
              ),
              const SizedBox(height: 16), //

              // Description (if available)
              if (description != null && description.isNotEmpty) ...[ //
                Align( //
                  alignment: Alignment.centerLeft, //
                  child: Text( //
                    'Description:', //
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), //
                  ),
                ),
                const SizedBox(height: 8), //
                Text( //
                  description, // Use description directly
                  style: Theme.of(context).textTheme.bodyMedium, //
                  textAlign: TextAlign.left, //
                ),
                const SizedBox(height: 16), //
              ],

              // Website and Twitter Icons in a Row
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  if (websiteLink != null && websiteLink.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Tooltip(
                        message: 'Visit Website',
                        child: IconButton(
                          icon: const Icon(Icons.web_asset, size: 30),
                          color: Colors.blue,
                          onPressed: () => launchURL(websiteLink),
                        ),
                      ),
                    ),
                  if (twitterLink != null && twitterLink.isNotEmpty)
                    Tooltip(
                      message: 'Visit Twitter',
                      child: IconButton(
                        icon: Image.asset(
                          'assets/twitter_logo.png', // Assuming you have a twitter_logo.png in your assets
                          width: 30,
                          height: 30,
                        ),
                        onPressed: () => launchURL(twitterLink),
                      ),
                    ),
                ],
              ),
              if ((websiteLink != null && websiteLink.isNotEmpty) || (twitterLink != null && twitterLink.isNotEmpty))
                const SizedBox(height: 16),

              // Time Filter ToggleButtons
              ToggleButtons( //
                isSelected: _selectedTimeFilter, //
                onPressed: (int index) { //
                  setState(() { //
                    for (int i = 0; i < _selectedTimeFilter.length; i++) { //
                      _selectedTimeFilter[i] = i == index; //
                    }
                    final authProvider = Provider.of<AuthProvider>(context, listen: false);
                    authProvider.setChartTimeCookie(index); // Save the selected index to cookie
                    _applyTimeFilterAndChartData(); // Re-apply filter
                  });
                },
                borderRadius: BorderRadius.circular(8.0),
                selectedColor: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.white, // Adjusted for dark mode
                fillColor: Theme.of(context).brightness == Brightness.light ? _lightModeColor : _darkModeColor, // Adjusted for dark mode
                color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white, // Adjusted for dark mode
                borderColor: Theme.of(context).brightness == Brightness.light ? _lightModeColor : _darkModeColor, // Adjusted for dark mode
                selectedBorderColor: Theme.of(context).brightness == Brightness.light ? _lightModeColor : _darkModeColor, // Adjusted for dark mode
                children: const <Widget>[ //
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('1H')), //
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('6H')), //
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('12H')), //
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('1D')), //
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('1W')), //
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('2W')), //
                ],
              ),
              const SizedBox(height: 16), //

              _isLoadingChartData
                  ? const CircularProgressIndicator()
                  : _filteredChartData.isEmpty
                  ? const SizedBox(
                height: 250,
                child: Center(child: Text('No chart data available for this period.')),
              )
                  : Container( // Wrap with Container
                height: 310,
                width: 450,
                decoration: BoxDecoration(
                  color: Colors.grey[850], // Match this to the chart background
                  borderRadius: BorderRadius.circular(4.0), // Apply rounded corners
                  border: Border.all(
                    color: Colors.white, // If you want a white border around the rounded container
                    width: 1,
                  ),
                ),
                child: ClipRRect( // Clip the chart content to the rounded corners
                  borderRadius: BorderRadius.circular(4.0), // Match the border radius
                  child: SfCartesianChart(
                    plotAreaBorderWidth: 2,
                    plotAreaBorderColor: Colors.white,
                    backgroundColor: Colors.transparent, // Make chart background transparent
                    primaryXAxis: DateTimeAxis(
                      isVisible: true, // Keep X-axis visible
                      majorGridLines: const MajorGridLines(width: 0), // Remove X-axis grid lines
                      axisLine: const AxisLine( // Change X-axis line color
                        width: 2, // Set a width for the line
                        color: Colors.white, // Set the color to white
                      ),
                      labelStyle: const TextStyle( // Direct TextStyle for more control
                        color: Colors.white, // White color for labels
                        fontWeight: FontWeight.bold, // Bold font weight
                      ),
                    ),
                    primaryYAxis: NumericAxis(
                      isVisible: false, // Hide Y-axis labels and line
                    ),
                    series: <CartesianSeries<ChartData, DateTime>>[
                      SplineSeries<ChartData, DateTime>(
                        dataSource: _filteredChartData,
                        xValueMapper: (ChartData data, _) => data.time,
                        yValueMapper: (ChartData data, _) => data.value,
                        name: 'Price History',
                        enableTooltip: false,
                        animationDuration: 0,
                        color: Colors.greenAccent, // Light green color for the line
                        width: 2, // Line thickness
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24), //

              // Swap Token Widget (Stubbed)
              Text( //
                'Purchase ${tokenName}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold), //
              ),
              const SizedBox(height: 16), //
              SwapToken( //
                tokenBlockchainNetwork: (authProvider.isSolana ? 'SOL' : 'ETH'),
                tokenMintAddress: mintAddress, // Use mintAddress directly
                tokenSymbol: tokenSymbol, // Use tokenSymbol directly
                walletProvider: walletProvider,
                userWalletAddress: userWalletAddress,
              ),
              const SizedBox(height: 48), //
            ],
          ),
        ),
      ),
    );
  }
}