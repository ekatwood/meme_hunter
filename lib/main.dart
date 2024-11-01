import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'find_unique_trades.dart';


void main() async {
  //WidgetsFlutterBinding.ensureInitialized();
  //await Firebase.initializeApp();

  runApp(const meme_hunter());
}

class meme_hunter extends StatelessWidget {
  const meme_hunter({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meme Hunter',
      theme: ThemeData(

          //colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          //useMaterial3: true,
          ),
      home: const MemeHunterPage(),
    );
  }
}

class MemeHunterPage extends StatelessWidget {
  const MemeHunterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 20.0, right: 20.0),
            child: Align(
              alignment: Alignment.topRight,
              child: SelectableText(
                'tip the dev: ETH 0xAe68f894965866b8Bc95f7603Ba7029884E1B6Be',
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
            padding: EdgeInsets.only(top: 25.0,right: 10, left: 10),
            child:
              Text(
                'Top 350 DEX coins across ETH, BSC and more chains, sorted by unique trades:',
                style: TextStyle(fontSize: 18),
              ),
          ),
          ElevatedButton(
            onPressed: () {
              fetchUniqueTrades();
            },
            child: Text('testing'),
          ),
        ],
      ),
    );
  }
}
