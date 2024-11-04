import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'find_unique_trades.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MemeHunterApp());
}

class MemeHunterApp extends StatelessWidget {
  const MemeHunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meme Hunter',
      theme: ThemeData(
          // Define theme settings here if needed
          ),
      home: const MemeHunterPage(),
    );
  }
}

class MemeHunterPage extends StatelessWidget {
  const MemeHunterPage({super.key});

  void _launchURL() async {
    final url = Uri.parse("https://bitquery.io/");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  Future<Map<int, dynamic>> fetchTradesData() async {
    final trades = await fetchDocuments();
    return trades;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(top: 10.0, right: 10.0, left: 10),
              child: Align(
                alignment: Alignment.topRight,
                child: TextField(
                  readOnly: true,
                  controller: TextEditingController(
                      text:
                          'tip the dev (DOGE): DByzcUdmZbfVGww2z4LcuWGjsV4aWubKVG'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true, // Reduces padding to make it more compact
                    contentPadding: EdgeInsets.zero, // Adjust padding as needed
                  ),
                ),
              ),
            ),
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
                  'Top 350 DEX coins across ETH, BSC and more chains, sorted by unique trades:',
                  style: TextStyle(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            FutureBuilder<Map<int, dynamic>>(
              future: fetchTradesData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                      padding: EdgeInsets.only(top: 20.0),
                      child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.redAccent)));
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
                        padding: const EdgeInsets.only(
                            top: 20.0, right: 15, left: 15, bottom: 15),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          // Enable horizontal scrolling
                          child: DataTable(
                            columns: const <DataColumn>[
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Name',
                                    style:
                                        TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Flexible(
                                  child: Text(
                                    'Symbol',
                                    style:
                                        TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              ),
                            ],
                            rows: trades.entries.map((entry) {
                              return DataRow(cells: [
                                DataCell(
                                  Container(
                                    width: 180,
                                    // Set the maximum width for the first column
                                    child: TextField(
                                      readOnly: true,
                                      controller: TextEditingController(
                                          text: entry.value['Name']),
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isDense: true,
                                        // Reduces padding to make it more compact
                                        contentPadding: EdgeInsets
                                            .zero, // Adjust padding as needed
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  TextField(
                                    readOnly: true,
                                    controller: TextEditingController(
                                        text: entry.value['Symbol']),
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      // Reduces padding to make it more compact
                                      contentPadding: EdgeInsets
                                          .zero, // Adjust padding as needed
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
                            style: const TextStyle(
                                fontSize: 16, color: Colors.black),
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
