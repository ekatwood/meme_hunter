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

  final trades = await fetchDocuments();
  // Get the first entry
  var firstEntry = trades.entries.first;
  // Access the value which is a Map and then get the 'timestamp'
  String timestamp = firstEntry.value['timestamp'];

  runApp(meme_hunter(trades: trades, timestamp: timestamp));
}

class meme_hunter extends StatelessWidget {
  const meme_hunter({super.key, required this.trades, required this.timestamp});

  final Map<int, dynamic> trades;
  final String timestamp;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meme Hunter',
      theme: ThemeData(

          //colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          //useMaterial3: true,
          ),
      home: MemeHunterPage(trades: trades, timestamp: timestamp),
    );
  }
}

class MemeHunterPage extends StatelessWidget {
  const MemeHunterPage(
      {super.key, required this.trades, required this.timestamp});

  final Map<int, dynamic> trades;
  final String timestamp;

  void _launchURL() async {
    final url = Uri.parse("https://bitquery.io/");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 20.0, right: 20.0),
              child: Align(
                alignment: Alignment.topRight,
                child: SelectableText(
                  'tip the dev: DOGE DByzcUdmZbfVGww2z4LcuWGjsV4aWubKVG',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 30.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14.0),
                // Adjust the radius as needed
                child: Image.asset(
                  'assets/meme-hunter_logo1.png', // Path to your asset image
                  height: 80, // Adjust height as needed
                  fit: BoxFit
                      .cover, // Ensures the image fits within the rounded rectangle
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 25.0, right: 10, left: 10),
              child: Text(
                'Top 350 DEX coins across ETH, BSC and more chains, sorted by unique trades:',
                style: TextStyle(fontSize: 18),
              ),
            ),
            Padding(
              padding:
                  EdgeInsets.only(top: 20.0, right: 10, left: 10, bottom: 15),
              child: DataTable(
                columns: const <DataColumn>[
                  DataColumn(
                    label: Expanded(
                      child: Text(
                        'Name',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Expanded(
                      child: Text(
                        'Symbol',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Expanded(
                      child: Text(
                        'Unique Trades',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
                  ),
                ],
                rows: trades.entries.map((entry) {
                  return DataRow(cells: [
                    DataCell(Text(entry.value['Name'] ?? '')),
                    DataCell(Text(entry.value['Symbol'] ?? '')),
                    DataCell(Text(
                        entry.value['tradesCountWithUniqueTraders'].toString()))
                  ]);
                }).toList(),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: 10.0, right: 15),
              child: Align(
                alignment: Alignment.topRight,
                child: Text(
                  timestamp,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: 15.0, bottom: 25),
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
                      recognizer: TapGestureRecognizer()..onTap = _launchURL,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
