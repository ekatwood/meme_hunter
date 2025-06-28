import 'package:cloud_firestore/cloud_firestore.dart';

Future<Map<int, dynamic>> fetchSOLDocuments() async {
  // Reference to the collection
  final collectionRef = FirebaseFirestore.instance.collection('tokens_by_timestamp_SOL');

  // Step 1: Find the latest timestamp by querying the first document in descending order of 'timestamp'
  final latestTimestampSnapshot = await collectionRef
      .orderBy('timestamp', descending: true)
      .limit(1)
      .get();

  // Retrieve the latest timestamp value
  final latestTimestamp = latestTimestampSnapshot.docs.first.get('timestamp');

  // Step 2: Query documents with the latest timestamp, ordered by 'tradesCountWithUniqueTraders'
  final latestDocsQuery = await collectionRef
      .where('timestamp', isEqualTo: latestTimestamp)
      .orderBy('Counter')
      .get();

  Map<int, dynamic> trades = {};
  var counter = 1;

  for(var doc in latestDocsQuery.docs){
    trades[counter] = {
      'Name': doc['Name'],
      'SmartContract': doc['SmartContract'],
      'Symbol': doc['Symbol'],
      'timestamp': doc['timestamp']
    };
    counter += 1;
  }
  return trades;
}
