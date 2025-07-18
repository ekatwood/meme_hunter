import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firestore_functions.dart';
import 'package:meme_hunter/token_details.dart';
import 'auth_provider.dart';
import 'appbar.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'token_data.dart'; // NEW: Import the TokenData class

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
  void _launchURL() async {
    final url = Uri.parse("https://bitquery.io/");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  // MODIFIED: Return type changed to List<TokenData>
  Future<List<TokenData>> fetchTokensData() async {
    return await fetchDocuments();
  }

  // MODIFIED: Return type changed to List<TokenData>
  Future<List<TokenData>> fetchSOLTokensData() async {
    return await fetchSOLDocuments();
  }

  // Function to copy text to clipboard and show SnackBar
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Address copied to clipboard.")),
    );
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
                      child: RichText(
                        text: TextSpan(
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: _fontFamily,
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                            children: [
                              const TextSpan(
                                text: 'Tip the dev (SOL): ',
                              ),
                              TextSpan(
                                text: '${_tipAddress.substring(0, 6)}...${_tipAddress.substring(_tipAddress.length - 4)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  decoration: TextDecoration.underline,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.normal,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    _copyToClipboard(_tipAddress);
                                  },
                              ),
                            ]
                        ),
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
              padding: const EdgeInsets.only(top: 25.0, right: 10, left: 10),
              child: Center(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: _fontFamily,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                    children: [
                      TextSpan(
                        text: 'A GraphQL query to find trending blockchain tokens ',
                      ),
                      TextSpan(
                        text: '📈💸✅',
                        style: const TextStyle(
                          fontFamily: 'NotoColorEmoji',
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
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
                },
              ),
            ),
            // MODIFIED: FutureBuilder now expects List<TokenData>
            FutureBuilder<List<TokenData>>(
              // Use authProvider.isSolana for the future selection
              future: authProvider.isSolana ? fetchSOLTokensData() : fetchTokensData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF800020)),
                    ),
                  );
                } else if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Text('Error: ${snapshot.error}'),
                  );
                } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  final tokens = snapshot.data!;
                  // The timestamp is now part of the first token, or derived.
                  // If you specifically need the latest timestamp from the query,
                  // you might need to adjust fetchDocuments to return it separately
                  // or assume it's consistent across all returned tokens.
                  // For now, let's take it from the first token for display.
                  final String? displayTimestamp = tokens.isNotEmpty ? tokens.first.timestamp : 'N/A';


                  return Column(
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
                                    style: TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Symbol',
                                    style: TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Mint Address',
                                    style: TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                            ],
                            // MODIFIED: Use the List<TokenData> directly
                            rows: tokens.map((token) {
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
                                            child: Image.network(
                                              token.firebaseLogoUrl!, // Access directly
                                              width: 25,
                                              height: 25,
                                              fit: BoxFit.cover,
                                              loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                                                if (loadingProgress == null) {
                                                  return child;
                                                }
                                                return Center(
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    value: loadingProgress.expectedTotalBytes != null
                                                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                        : null,
                                                  ),
                                                );
                                              },
                                              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
                                                print('Image.network Error: $error' + 'url: ${token.firebaseLogoUrl}'); // Access directly
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
                                                      tokenData: {
                                                        'Name': token.name,
                                                        'SmartContract': token.smartContract,
                                                        'Symbol': token.symbol,
                                                        'circulating_supply': token.circulatingSupply,
                                                        'market_cap': token.marketCap,
                                                        'description': token.description,
                                                        'website_link': token.websiteLink,
                                                        'twitter_link': token.twitterLink,
                                                        'firebase_logo_url': token.firebaseLogoUrl,
                                                        'tradesCountWithUniqueTraders': token.tradesCountWithUniqueTraders,
                                                        'timestamp': token.timestamp,
                                                      }, // Pass as Map for now, refactor TokenDetails next
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
                                  GestureDetector(
                                    onTap: () => _copyToClipboard(token.smartContract), // Access directly
                                    child: Container(
                                      width: 150,
                                      child: Text(
                                            () {
                                          final smartContract = token.smartContract; // Access directly
                                          if (smartContract.isEmpty || smartContract == 'N/A') {
                                            return 'N/A';
                                          }
                                          if (smartContract == '0x') {
                                            return '0x';
                                          }
                                          final int minLengthForTruncation = 10;
                                          if (smartContract.length <= minLengthForTruncation) {
                                            return smartContract;
                                          } else {
                                            return '${smartContract.substring(0, 6)}...${smartContract.substring(smartContract.length - 4)}';
                                          }
                                        }(),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          decoration: TextDecoration.underline,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0, right: 15),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Text(
                            displayTimestamp ?? 'N/A', // Display timestamp from the first token
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 15.0, bottom: 80),
                        child: RichText(
                          text: TextSpan(
                            style: Theme.of(context).textTheme.bodyMedium,
                            children: [
                              const TextSpan(
                                  text: 'Powered by ',
                                  style: const TextStyle(fontWeight: FontWeight.normal,)
                              ),
                              TextSpan(
                                text: 'Bitquery',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.normal,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = _launchURL,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  return const Center(
                    child: Text('No data available'),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}