import 'package:cloud_firestore/cloud_firestore.dart';

Future<Map<int, dynamic>> fetchDocuments() async {
  // Reference to the collection
  final collectionRef = FirebaseFirestore.instance.collection('tokens_by_timestamp');

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
      .orderBy('tradesCountWithUniqueTraders', descending: true)
      .get();

  Map<int, dynamic> trades = {};
  var counter = 1;

  for(var doc in latestDocsQuery.docs){
    //strip out empty entries
    if (doc['Name'] == null ||
        doc['Symbol'] == null ||
        doc['Name'].toString().trim().isEmpty ||
        doc['Symbol'].toString().trim().isEmpty) continue;

    trades[counter] = {
      'Name': doc['Name'],
      'SmartContract': doc['SmartContract'],
      'Symbol': doc['Symbol'],
      'tradesCountWithUniqueTraders': doc['tradesCountWithUniqueTraders'],
      'timestamp': doc['timestamp']
    };
    counter += 1;
  }
  return trades;
}