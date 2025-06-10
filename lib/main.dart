import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth_provider.dart';
import 'appbar.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'find_unique_trades_SOL.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firestore_functions.dart';
import 'package:flutter/services.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const TokenQuestPage(),
    ),
    // GoRoute(
    //   path: '/mint_token',
    //   builder: (context, state) => const TokenFactory(), // Create this page
    // ),
    // GoRoute(
    //   path: '/settings',
    //   builder: (context, state) => SettingsPage(), // and this page
    // ),
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(// Provide the AuthProvider to the entire application.
    ChangeNotifierProvider(
      create: (context) => AuthProvider(),
      child: const MemeHunterApp(),
    ),);
}

class MemeHunterApp extends StatelessWidget {
  const MemeHunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Token Quest',
      theme: ThemeData(),
      home: const TokenQuestPage(),
      routes: {
        '/chart': (context) => const ChartPage(),
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
  String? _walletAddress; // Add wallet address state

  void _launchURL() async {
    final url = Uri.parse("https://bitquery.io/");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  Future<Map<int, dynamic>> fetchSOLTradesData() async {
    return await fetchSOLDocuments();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mint address copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 30.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14.0),
                child: Image.asset(
                  'assets/meme-hunter_logo1.png',
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 25.0, right: 10, left: 10),
              child: Center(
                child: Text(
                  'Hottest 🔥📈 Solana Tokens',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            FutureBuilder<Map<int, dynamic>>(
              future: fetchSOLTradesData(),
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
                  final timestamp = trades.entries.first.value['timestamp'];

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0, right: 15),
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            timestamp,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
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
                                    'CA',
                                    style: TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    '📈',
                                    style: TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                            ],
                            rows: trades.entries.map((entry) {
                              return DataRow(cells: [
                                DataCell(
                                  Container(
                                    width: 180,
                                    child: SelectableText(
                                      entry.value['Name'],
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  TextField(
                                    readOnly: true,
                                    controller: TextEditingController(
                                        text: entry.value['Symbol']),
                                    style: const TextStyle(fontSize: 16),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  GestureDetector(
                                    onTap: () {
                                      _copyToClipboard(entry.value['CA'] ?? 'No CA available');
                                    },
                                    child: const Text(
                                      'copy',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  GestureDetector(
                                    onTap: () {
                                      _navigateToChart(
                                        entry.value['Name'],
                                        entry.value['CA'] ?? '',
                                      );
                                    },
                                    child: const Icon(
                                      Icons.bar_chart,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 15.0, bottom: 80),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 16, color: Colors.black),
                            children: [
                              const TextSpan(text: 'Powered by '),
                              TextSpan(
                                text: 'Bitquery',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
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

// New ChartPage class
class ChartPageArguments {
  final String tokenName;
  final String tokenCA;

  ChartPageArguments(this.tokenName, this.tokenCA);
}

class ChartPage extends StatelessWidget {
  const ChartPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as ChartPageArguments;

    return Scaffold(
      appBar: CustomAppBar(),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 25.0, right: 10, left: 10),
              child: Center(
                child: Text(
                  'Chart For "${args.tokenName}"',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: Text(
                  'Contract Address: ${args.tokenCA}',
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // Placeholder for chart content
            Container(
              height: 400,
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('Chart data loading...'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
