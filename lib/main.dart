// main.dart
import 'dart:convert'; // Import for JSON encoding/decoding
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firestore_functions.dart';
import 'package:meme_hunter/token_details.dart';
import 'auth_provider.dart';
import 'utils.dart';
import 'appbar.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'token_data.dart'; // Import the TokenData class
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const TokenQuestPage(),
    ),
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    // Provide the AuthProvider to the entire application.
    ChangeNotifierProvider(
      create: (context) => AuthProvider(),
      child: const TokenQuestApp(),
    ),
  );
}

class TokenQuestApp extends StatelessWidget {
  const TokenQuestApp({super.key});

  final String _fontFamily = 'SourceCodePro';
  final double _fontSize = 16.0;

  @override
  Widget build(BuildContext context) {

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return MaterialApp.router(
          title: 'Token Quest',
          themeMode: authProvider.themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            //primarySwatch: Colors.teal, // Example light primary color
            fontFamily: _fontFamily, // Default font family.
            textTheme: TextTheme(
              bodyMedium: TextStyle(
                fontSize: _fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            //primarySwatch: Colors.indigo, // Example dark primary color
            fontFamily: _fontFamily, // Default font family.
            textTheme: TextTheme(
              bodyMedium: TextStyle(
                fontSize: _fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          routerConfig: _router,
        );
      },
    );
  }
}

class TokenQuestPage extends StatefulWidget {
  const TokenQuestPage({super.key});

  @override
  _TokenQuestPageState createState() => _TokenQuestPageState();
}

class _TokenQuestPageState extends State<TokenQuestPage> {
  // State variables to hold the token data and loading status for each blockchain
  List<TokenData>? _ethereumTokens;
  List<TokenData>? _solanaTokens;
  bool _isLoadingEthereum = false;
  bool _isLoadingSolana = false;

  // Timestamps to track when the data was last fetched/cached for each blockchain
  String? _ethereumFetchTimestamp;
  String? _solanaFetchTimestamp;
  String? _timestamp; // This variable is not needed anymore

  // Cache duration in hours
  static const int _cacheDurationHours = 12;

  @override
  void initState() {
    super.initState();
    // Fetch initial data based on the current preference
    // Using addPostFrameCallback to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isSolana) {
        _fetchSolanaTokensData(forceRefresh: false);
      } else {
        _fetchEthereumTokensData(forceRefresh: false);
      }
    });
  }

  // Helper function to check if cached data is stale
  bool _isDataStale(String? timestampString) {

    if (timestampString == null) return true;
    try {
      final cachedTime = DateTime.parse(timestampString);
      final now = DateTime.now();
      return now.difference(cachedTime).inHours >= _cacheDurationHours;
    } catch (e) {
      print('Error parsing timestamp: $e');
      return true; // If parsing fails, treat as stale
    }
  }

  // Fetches Ethereum token data from cache or Firestore
  Future<void> _fetchEthereumTokensData({bool forceRefresh = false}) async {
    if (_isLoadingEthereum && !forceRefresh) return; // Prevent multiple simultaneous fetches
    setState(() {
      _isLoadingEthereum = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final cachedDataString = prefs.getString('ethereum_tokens_cache');
    final cachedTimestampString = prefs.getString('ethereum_timestamp_cache');

    if (!forceRefresh && cachedDataString != null && !_isDataStale(cachedTimestampString)) {
      try {
        final List<dynamic> decodedData = json.decode(cachedDataString);
        _ethereumTokens = decodedData.map((e) => TokenData.fromJson(e as Map<String, dynamic>)).toList();
        _timestamp = _ethereumTokens?.first.timestamp;
        _ethereumFetchTimestamp = cachedTimestampString;
        print('Loaded Ethereum data from cache. Timestamp: $_ethereumFetchTimestamp');
      } catch (e) {
        print('Error decoding cached Ethereum data: $e');
        // If decoding fails, force a fetch from Firestore
        await _fetchEthereumTokensData(forceRefresh: true);
      }
    } else {
      print('Fetching Ethereum data from Firestore...');
      try {
        final fetchedTokens = await fetchDocuments();
        _ethereumTokens = fetchedTokens;
        _timestamp = _ethereumTokens?.first.timestamp;
        _ethereumFetchTimestamp = DateTime.now().toIso8601String(); // Store current time as fetch timestamp

        // Cache the fetched data
        final String encodedData = json.encode(fetchedTokens.map((e) => e.toJson()).toList());
        await prefs.setString('ethereum_tokens_cache', encodedData);
        await prefs.setString('ethereum_timestamp_cache', _ethereumFetchTimestamp!);
        print('Fetched and cached Ethereum data. Timestamp: $_ethereumFetchTimestamp');
      } catch (e) {
        print('Error fetching Ethereum data: $e');
        // Optionally, show an error message to the user
      }
    }

    setState(() {
      _isLoadingEthereum = false;
    });
  }

  // Fetches Solana token data from cache or Firestore
  Future<void> _fetchSolanaTokensData({bool forceRefresh = false}) async {
    if (_isLoadingSolana && !forceRefresh) return; // Prevent multiple simultaneous fetches
    setState(() {
      _isLoadingSolana = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final cachedDataString = prefs.getString('solana_tokens_cache');
    final cachedTimestampString = prefs.getString('solana_timestamp_cache');

    if (!forceRefresh && cachedDataString != null && !_isDataStale(cachedTimestampString)) {
      try {
        final List<dynamic> decodedData = json.decode(cachedDataString);
        _solanaTokens = decodedData.map((e) => TokenData.fromJson(e as Map<String, dynamic>)).toList();
        _timestamp = _solanaTokens?.first.timestamp;
        _solanaFetchTimestamp = cachedTimestampString;
        print('Loaded Solana data from cache. Timestamp: $_solanaFetchTimestamp');
      } catch (e) {
        print('Error decoding cached Solana data: $e');
        // If decoding fails, force a fetch from Firestore
        await _fetchSolanaTokensData(forceRefresh: true);
      }
    } else {
      print('Fetching Solana data from Firestore...');
      try {
        final fetchedTokens = await fetchSOLDocuments();
        _solanaTokens = fetchedTokens;
        _timestamp = _solanaTokens?.first.timestamp;
        _solanaFetchTimestamp = DateTime.now().toIso8601String(); // Store current time as fetch timestamp

        // Cache the fetched data
        final String encodedData = json.encode(fetchedTokens.map((e) => e.toJson()).toList());
        await prefs.setString('solana_tokens_cache', encodedData);
        await prefs.setString('solana_timestamp_cache', _solanaFetchTimestamp!);
        print('Fetched and cached Solana data. Timestamp: $_solanaFetchTimestamp');
      } catch (e) {
        print('Error fetching Solana data: $e');
        // Optionally, show an error message to the user
      }
    }

    setState(() {
      _isLoadingSolana = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final String _tipAddress = '3m4NqSsisHtCtCpA7jSAj6jNxNEgGL1uGbkpb36yBNq4';
    final String _fontFamily = 'SourceCodePro';

    final Color selectedFillColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFA8415B)
        : const Color(0xFF800020);

    final Color unselectedTextColor = Theme.of(context).brightness == Brightness.light
        ? Colors.black87
        : Colors.white70;

    final Color selectedTextColor = Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : Colors.white;

    final Color unselectedBorderColor = Theme.of(context).brightness == Brightness.light
        ? Colors.grey
        : Colors.grey[700]!;

    final Color selectedBorderColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFA8415B)
        : const Color(0xFF800020);

    // Determine which list and loading state to use based on AuthProvider
    List<TokenData>? currentTokens;
    bool isLoadingCurrent;

    if (authProvider.isSolana) {
      currentTokens = _solanaTokens;
      isLoadingCurrent = _isLoadingSolana;
    } else {
      currentTokens = _ethereumTokens;
      isLoadingCurrent = _isLoadingEthereum;
    }

    return Scaffold(
      appBar: CustomAppBar(),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 10.0, right: 10.0, left: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child:
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                          _timestamp != null ? '${convertTimestampToFormattedString(_timestamp!)}' : 'Loading...',
                        style: Theme.of(context).textTheme.bodyMedium
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: authProvider.themeMode == ThemeMode.light ? 'Switch to Dark Mode' : 'Switch to Light Mode',
                    child: IconButton(
                      icon: Icon(
                        authProvider.themeMode == ThemeMode.light
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        size: 28,
                        color: Theme.of(context).brightness == Brightness.light ? Colors.grey[800] : Colors.amber,
                      ),
                      onPressed: authProvider.toggleThemeMode,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: ToggleButtons(
                color: unselectedTextColor,
                selectedColor: selectedTextColor,
                fillColor: selectedFillColor,
                borderColor: unselectedBorderColor,
                selectedBorderColor: selectedBorderColor,
                splashColor: Colors.grey.withOpacity(0.2),
                hoverColor: Colors.grey.withOpacity(0.1),
                children: const <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Ethereum'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Solana'),
                  ),
                ],
                isSelected: [!authProvider.isSolana, authProvider.isSolana],
                onPressed: (int index) {
                  authProvider.setBlockchainPreference(index == 1);
                  // Fetch data only if not already loaded or if it's stale
                  if (index == 0) { // Ethereum selected
                    if (_ethereumTokens == null || _isDataStale(_ethereumFetchTimestamp)) {
                      _fetchEthereumTokensData();
                    }
                  } else { // Solana selected
                    if (_solanaTokens == null || _isDataStale(_solanaFetchTimestamp)) {
                      _fetchSolanaTokensData();
                    }
                  }
                },
              ),
            ),
            // Conditional rendering based on loading state and data availability
            if (isLoadingCurrent)
              const Padding(
                padding: EdgeInsets.only(top: 20.0),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF800020)),
                ),
              )
            else if (currentTokens == null || currentTokens.isEmpty)
              const Center(
                child: Text('No data available'),
              )
            else
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        top: 20.0, right: 15, left: 15, bottom: 15),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const <DataColumn>[
                          DataColumn(
                            label: Flexible(
                              child: Text(
                                'Name',
                                style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Flexible(
                              child: Text(
                                'Symbol',
                                style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Flexible(
                              child: Text(
                                'Market Cap.',
                                style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                        rows: currentTokens!.map((token) {
                          return DataRow(cells: [
                            DataCell(
                              Container(
                                width: (MediaQuery.of(context).size.width - 20) * 0.4,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Conditional logic for displaying the logo
                                    if (token.firebaseLogoUrl != null && token.firebaseLogoUrl!.isNotEmpty)
                                      ClipOval(
                                        child: CachedNetworkImage( // Changed to CachedNetworkImage
                                          imageUrl: token.firebaseLogoUrl!, // Access directly
                                          width: 25,
                                          height: 25,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 2,),
                                          errorWidget: (context, url, error) {
                                            print('CachedNetworkImage Error: $error, URL: $url');
                                            return const Icon(Icons.error, size: 25);
                                          },
                                        ),
                                      )
                                    else
                                      ClipOval(
                                        child: SizedBox(
                                          width: 25,
                                          height: 25,
                                          child: authProvider.isSolana
                                              ? Image.asset(
                                            'assets/solana-sol-logo.png',
                                            fit: BoxFit.cover,
                                          )
                                              : Image.asset(
                                            'assets/ethereum-logo.png',
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            useRootNavigator: true,
                                            builder: (BuildContext context) {
                                              return FractionallySizedBox(
                                                heightFactor: 0.98,
                                                child: TokenDetails(
                                                  tokenData: token,
                                                ),
                                              );
                                            },
                                          );
                                        },
                                        child: Text(
                                          token.name, // Access directly
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                width: 110,
                                child: TextField(
                                  readOnly: true,
                                  controller: TextEditingController(text: token.symbol), // Access directly
                                  style: const TextStyle(fontSize: 16,fontWeight: FontWeight.bold,),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                width: 150,
                                child: TextField(
                                  readOnly: true,
                                  controller: TextEditingController(text: '\$${token.marketCap}'), // Access directly
                                  style: const TextStyle(fontSize: 16,fontWeight: FontWeight.bold,),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              // GestureDetector(
                              //   onTap: () => _copyToClipboard(token.marketCap), // Access directly
                              //   child: Container(
                              //     width: 150,
                              //     child: Text(
                              //           () {
                              //         final smartContract = token.marketCap; // Access directly
                              //         if (smartContract.isEmpty || smartContract == 'N/A') {
                              //           return 'N/A';
                              //         }
                              //         if (smartContract == '0x') {
                              //           return '0x';
                              //         }
                              //         final int minLengthForTruncation = 10;
                              //         if (smartContract.length <= minLengthForTruncation) {
                              //           return smartContract;
                              //         } else {
                              //           return '${smartContract.substring(0, 6)}...${smartContract.substring(smartContract.length - 4)}';
                              //         }
                              //       }(),
                              //       style: const TextStyle(
                              //         fontSize: 14,
                              //         decoration: TextDecoration.underline,
                              //         color: Colors.blue,
                              //         fontWeight: FontWeight.normal,
                              //       ),
                              //     ),
                              //   ),
                              // ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 15.0, bottom: 15),
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: [
                          const TextSpan(
                              text: 'Powered by ',
                              style: const TextStyle(fontWeight: FontWeight.bold,)
                          ),
                          TextSpan(
                            text: 'Bitquery',
                            style: const TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.bold,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () async { // Changed to an async anonymous function
                                final url = Uri.parse("https://bitquery.io/");
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                } else {
                                  // Optionally, show an error message to the user
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Could not launch ${url.toString()}')),
                                  );
                                }
                              },
                          ),
                        ],
                      ),
                    ),
                  ),
                  // New RichText for tipping the dev
                  Padding(
                    padding: const EdgeInsets.only(bottom: 80), // Added padding
                    child: RichText(
                      text: TextSpan(
                          style: Theme.of(context).textTheme.bodyMedium,
                          children: [
                            const TextSpan(
                              text: 'Tip the dev (SOL): ',
                            ),
                            TextSpan(
                              text: '${_tipAddress.substring(0, 6)}...${_tipAddress.substring(_tipAddress.length - 4)}',
                              style: const TextStyle(
                                decoration: TextDecoration.underline,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  copyToClipboard(_tipAddress, context);
                                },
                            ),
                          ]
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}