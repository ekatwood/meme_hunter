import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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
      child: const MemeHunterApp(),
    ),
  );
}

class MemeHunterApp extends StatelessWidget {
  const MemeHunterApp({super.key});

  final String _fontFamily = 'SourceCodePro';
  final double _fontSize = 16.0;

  @override
  Widget build(BuildContext context) {

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return MaterialApp(
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
          home: const TokenQuestPage(),
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
      const SnackBar(content: Text("Mint address copied to clipboard.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    // NEW: Access AuthProvider for theme toggle
    final authProvider = Provider.of<AuthProvider>(context);

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
                    child: Align(
                      alignment: Alignment.topRight,
                      child: TextField(
                        readOnly: true,
                        controller: TextEditingController(
                            text: 'tip the dev (DOGE): DByzcUdmZbfVGww2z4LcuWGjsV4aWubKVG'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10), // Space between text and switch
                  // Lightmode / Darkmode Toggle Switch
                  Tooltip( // Provides a hint on hover
                    message: authProvider.themeMode == ThemeMode.light ? 'Switch to Dark Mode' : 'Switch to Light Mode',
                    child: Switch(
                      value: authProvider.themeMode == ThemeMode.dark, // true if current theme is dark
                      onChanged: (bool value) {
                        authProvider.toggleThemeMode(); // Call the AuthProvider method
                      },
                      activeColor: Theme.of(context).primaryColor, // Use primary color for active state
                      inactiveTrackColor: Colors.grey, // Grey for inactive state
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
                      color: Theme.of(context).textTheme.bodyMedium?.color, // Inherit color from theme
                    ),
                    children: [
                      const TextSpan(
                        text: 'A GraphQL query to find trending blockchain tokens ',
                      ),
                      TextSpan(
                        text: '📈💸✅', // The emojis
                        style: const TextStyle(
                          fontFamily: 'NotoColorEmoji', // Apply the emoji font family
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.redAccent),
                    ),
                  );
                } else if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Text('Error: ${snapshot.error}'),
                  );
                } else if (snapshot.hasData) {
                  final trades = snapshot.data!;
                  // Assuming 'timestamp' key exists directly in the top-level map
                  final String timestamp = trades['timestamp']?.toString() ?? 'N/A';

                  // Filter out the timestamp entry to only process actual trade data rows
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
                              // NEW: Stubbed Mint Address for ETH and SOL
                              // In a real app, this would come from `trade['MintAddress']`
                              final String stubMintAddress = isSolana
                                  ? 'So11111111111111111111111111111111111111112' // Solana stub
                                  : '0x1234567890abcdef1234567890abcdef12345678'; // Ethereum stub

                              return DataRow(cells: [
                                DataCell(
                                  Container(
                                    width: 150, // Maintain original width
                                    child: SelectableText(
                                      trade['Name'] ?? 'N/A', // Use trade['Name']
                                      style: const TextStyle(fontSize: 16),
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
                                    onTap: () => _copyToClipboard(stubMintAddress),
                                    child: Container(
                                      width: 180, // Adjust width for address
                                      child: Text(
                                        '${stubMintAddress.substring(0, 6)}...${stubMintAddress.substring(stubMintAddress.length - 4)}', // Truncate
                                        style: const TextStyle(
                                          fontSize: 14,
                                          decoration: TextDecoration.underline,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis, // Handle long addresses
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