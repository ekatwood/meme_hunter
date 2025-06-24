import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:meme_hunter/token_page.dart';
import 'auth_provider.dart';
import 'appbar.dart';
import 'find_unique_trades_SOL.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'find_unique_trades.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const TokenQuestPage(),
    ),
    GoRoute(
      path: '/token/:blockchainNetwork/:mintAddress',
      builder: (context, state) => TokenPage(blockchainNetwork: state.pathParameters['blockchainNetwork']!, mintAddress: state.pathParameters['mintAddress']!),
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
  bool isSolana = false;

  void _launchURL() async {
    final url = Uri.parse("https://bitquery.io/");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  // Existing `fetchTradesData` (untouched)
  Future<Map<int, dynamic>> fetchTradesData() async {
    return await fetchDocuments();
  }

  // Existing `fetchSOLTradesData` (untouched)
  Future<Map<int, dynamic>> fetchSOLTradesData() async {
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
    // NEW: Access AuthProvider for theme toggle
    final authProvider = Provider.of<AuthProvider>(context);
    final String _tipAddress = 'MFxBxp8ysZVXezAADWBt6tgDf2iqfq6LbY';
    final String _fontFamily = 'SourceCodePro';

    // Define colors for the ToggleButtons based on the current theme's brightness
    // You can customize these colors directly.
    final Color selectedFillColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFA8415B) // Light burgundy for light mode selected
        : const Color(0xFF800020); // Darker burgundy for dark mode selected

    final Color unselectedTextColor = Theme.of(context).brightness == Brightness.light
        ? Colors.black87 // Dark text for unselected in light mode
        : Colors.white70; // Light text for unselected in dark mode

    final Color selectedTextColor = Theme.of(context).brightness == Brightness.light
        ? Colors.white // White text for selected in light mode
        : Colors.white; // White text for selected in dark mode (or a contrasting dark color if needed)

    final Color unselectedBorderColor = Theme.of(context).brightness == Brightness.light
        ? Colors.grey // Grey border for unselected in light mode
        : Colors.grey[700]!; // Dark grey border for unselected in dark mode

    final Color selectedBorderColor = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFFA8415B) // Light burgundy border for selected in light mode
        : const Color(0xFF800020); // Darker burgundy border for selected in dark mode

    return Scaffold(
      appBar: CustomAppBar(),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 10.0, right: 10.0, left: 10),
              // NEW: Use a Row to place items on the same line, aligned to the end
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded( // Allows TextField to take remaining space
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
                          text: 'Tip the dev (LTC): ', // Static text
                        ),
                        TextSpan(
                          text: '${_tipAddress.substring(0, 6)}...${_tipAddress.substring(_tipAddress.length - 4)}', // Truncate
                          style: const TextStyle(
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                            color: Colors.blue, // Clickable part color
                            fontWeight: FontWeight.normal, // Ensure address is not bold if parent is
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              _copyToClipboard(_tipAddress); // Pass the full address to copy
                            },
                        ),
                        ]
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Lightmode / Darkmode Toggle
                  Tooltip( // Provides a hint on hover
                    message: authProvider.themeMode == ThemeMode.light ? 'Switch to Dark Mode' : 'Switch to Light Mode',
                    child: IconButton(
                      icon: Icon(
                        authProvider.themeMode == ThemeMode.light
                            ? Icons.dark_mode_outlined // Icon for light mode to switch to dark
                            : Icons.light_mode_outlined, // Icon for dark mode to switch to light
                        size: 28,
                        color: Theme.of(context).brightness == Brightness.light ? Colors.grey[800] : Colors.amber, // Icon color based on theme
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
                      color: Theme.of(context).textTheme.bodyMedium?.color, // Inherit color from theme
                    ),
                    children: [
                      TextSpan(
                        text: 'A GraphQL query to find trending blockchain tokens ',
                      ),
                      TextSpan(
                        text: '📈💸✅', // The emojis
                        style: const TextStyle(
                          fontFamily: 'NotoColorEmoji', // Apply the emoji font family
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
                // Directly apply your custom colors here
                color: unselectedTextColor, // Color of text/icons in unselected buttons
                selectedColor: selectedTextColor, // Color of text/icons in selected buttons
                fillColor: selectedFillColor, // Background color of selected button
                borderColor: unselectedBorderColor, // Border color of unselected buttons
                selectedBorderColor: selectedBorderColor, // Border color of selected button
                // These typically come from the theme, so keeping them simple for direct control
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
                isSelected: [!isSolana, isSolana],
                onPressed: (int index) {
                  setState(() {
                    isSolana = index == 1;
                  });
                },
              ),
            ),
            FutureBuilder<Map<int, dynamic>>(
              future: isSolana ? fetchSOLTradesData() : fetchTradesData(),
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
                } else if (snapshot.hasData) {
                  final trades = snapshot.data!;
                  final timestamp = trades.entries.first.value['timestamp'];

                  // Filter out the timestamp entry to only process actual trade data rowsMore actions
                  final List<Map<String, dynamic>> tradeEntries = trades.entries
                      .where((entry) => entry.key is int) // Filter out non-integer keys like 'timestamp'
                      .map((entry) => entry.value as Map<String, dynamic>)
                      .toList();

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
                              // Mint Address DataColumn
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Mint Address',
                                    style: TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                            ],
                            rows: tradeEntries.map((trade) {

                              return DataRow(cells: [
                                DataCell(
                                  Container(
                                    width: (MediaQuery.of(context).size.width - 20) * 0.4, // Approx 40% of screen width (adjust 20 for padding), // Maintain original width
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min, // Use minimum space
                                      children: [
                                        // Conditional logic for displaying the logo
                                        if (trade['Logo'] != null && trade['Logo'].isNotEmpty)
                                          ClipOval(
                                            child: CachedNetworkImage(
                                              imageUrl: trade['Logo'],
                                              width: 25,
                                              height: 25,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 2),
                                              errorWidget: (context, url, error) => const Icon(Icons.error, size: 25),
                                            ),
                                          )
                                        else
                                          ClipOval(
                                            child: SizedBox(
                                              width: 25,
                                              height: 25,
                                              child: isSolana
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
                                              // Navigate to TokenPage with blockchain and mintAddress
                                              _router.go('/token/${isSolana ? 'Solana' : 'Ethereum'}/${trade['mintAddress']}');
                                            },
                                            child: Text(
                                              trade['Name'] ?? 'N/A',
                                              style: const TextStyle(fontSize: 16),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Container( // Use Container to apply width directly
                                    width: 80, // Adjust width as needed for symbol
                                    child: TextField(
                                      readOnly: true,
                                      controller: TextEditingController(text: trade['Symbol'] ?? 'N/A'),
                                      style: const TextStyle(fontSize: 16,fontWeight: FontWeight.bold,),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                ),
                                // NEW: Mint Address DataCell
                                DataCell(
                                  GestureDetector( // Make the cell clickable
                                    onTap: () => _copyToClipboard(trade['mintAddress']),
                                    child: Container(
                                      width: 150, // Adjust width for address
                                      child: Text(
                                        '${trade['mintAddress'].substring(0, 6)}...${trade['mintAddress'].substring(trade['mintAddress'].length - 4)}', // Truncate
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
                            timestamp,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 15.0, bottom: 80),
                        child: RichText(
                          text: TextSpan(
                            // NEW: Ensure RichText style adapts to theme
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