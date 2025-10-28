// token_details.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'firestore_functions.dart';
import 'auth_provider.dart';
import 'utils.dart';
import 'package:meme_hunter/swap_token.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'token_data.dart';

// Chart Data Model for Syncfusion Chart
class ChartData {
  ChartData(this.time, this.value);
  final DateTime time;
  final double value;
}

class TokenDetails extends StatefulWidget {
  final TokenData tokenData;

  const TokenDetails({
    super.key,
    required this.tokenData,
  });

  @override
  State<TokenDetails> createState() => _TokenDetailsState();
}

class _TokenDetailsState extends State<TokenDetails> {

  // NEW: Mapping from _selectedTimeFilter index to the Firestore field key
  final List<String> _timeframeKeys = const [
    'data_1h', // 1H (Index 0)
    'data_6h', // 6H (Index 1)
    'data_12h', // 12H (Index 2)
    'data_1d', // 1D (Index 3)
    'data_1w', // 1W (Index 4)
    'data_2w', // 2W (Index 5)
  ];

  final _wethAddress = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';

  // Default 6H selected, but will be overridden by cookie
  List<bool> _selectedTimeFilter = [false, true, false, false, false, false];

  // MODIFIED: _rawChartData is removed as data is fetched pre-thinned
  List<ChartData> _filteredChartData = []; // Stores filtered data for chart
  bool _isLoadingChartData = true;

  // NEW: Reference to AuthProvider for cookie management
  late final AuthProvider _authProvider;

  final _darkModeColor = Color(0xFF800020);
  final _lightModeColor = const Color(0xFFA8415B);

  @override
  void initState() {
    super.initState();
    _loadChartTimePreference(); // Load preference when state initializes
    // NOTE: _fetchAndSetChartData is called after didChangeDependencies is run
    // which is the earliest place we can safely access Provider.
  }

  // NEW: Initialize AuthProvider reference here
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize AuthProvider reference once here
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    // Fetch data now that AuthProvider is initialized
    if (_filteredChartData.isEmpty && _isLoadingChartData) {
      _fetchAndSetChartData();
    }
  }

  // NEW: Clean up the cookies when the widget is disposed
  @override
  void dispose() {
    // Delete all possible chart data cookies for this token when the modal closes.
    final String? contractAddress = widget.tokenData.smartContract;
    if (contractAddress != null) {
      for (final key in _timeframeKeys) {
        final cookieKey = 'chartData_${contractAddress}_$key';
        _authProvider.deleteChartDataCookie(cookieKey);
        print('Deleted chart data cookie: $cookieKey');
      }
    }
    super.dispose();
  }

  // New: Load chart time preference from cookie
  void _loadChartTimePreference() {
    // The AuthProvider won't be available via Provider.of here, so we wait for didChangeDependencies.
    // However, to keep the flow clean, we use the original approach and rely on Flutter's deferred
    // access to Provider.
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final int? savedIndex = authProvider.getChartTimeCookie(); // Access the cookie
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

  // MODIFIED: Function updated to use pre-thinned data and cookie cache
  Future<void> _fetchAndSetChartData() async {
    setState(() {
      _isLoadingChartData = true;
    });

    final String? contractAddress = widget.tokenData.smartContract;

    // Get the currently selected key (e.g., 'data_6h')
    final int selectedIndex = _selectedTimeFilter.indexOf(true);
    final String timeframeKey = selectedIndex != -1 ? _timeframeKeys[selectedIndex] : _timeframeKeys[1]; // Default to 6H

    if (contractAddress != null && contractAddress.isNotEmpty && contractAddress != 'N/A') {
      // MODIFIED: Pass the timeframeKey AND the cookie management functions
      final List<Map<String, dynamic>> rawChartData = await fetchChartData(
        contractAddress,
        timeframeKey,
        _authProvider.getChartDataCookie, // Pass getCookie function
        _authProvider.setChartDataCookie, // Pass setCookie function
      );

      // Directly map the fetched, pre-thinned data
      _filteredChartData = rawChartData.map((dataPoint) {
        final DateTime? parsedTime = _parseDynamicTimestamp(dataPoint['timestamp']);
        final double? value = (dataPoint['open'] as num?)?.toDouble();

        if (parsedTime != null && value != null) {
          return ChartData(parsedTime, value);
        }
        return null;
      }).whereType<ChartData>().toList(); // Filter out any null entries

      // Sort by time to ensure correct chart display
      _filteredChartData.sort((a, b) => a.time.compareTo(b.time));

    } else {
      _filteredChartData = [];
      print('Contract address is null or empty for chart data fetch.');
    }

    setState(() {
      _isLoadingChartData = false;
    });
  }

  // Helper to parse dynamic timestamp into DateTime (kept as is)
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

  // DELETED: _applyTimeFilterAndChartData logic is removed as data is pre-thinned

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
                    // Save the selected index to cookie
                    authProvider.setChartTimeCookie(index);
                  });
                  // NEW: Fetch the new data from Firestore/Cache for the selected time range
                  _fetchAndSetChartData();
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