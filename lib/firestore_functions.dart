import 'package:cloud_firestore/cloud_firestore.dart';
import 'token_data.dart';

Future<List<TokenData>> fetchDocuments() async {
  // Reference to the collection
  final collectionRef = FirebaseFirestore.instance.collection('tokens_by_timestamp');

  // Step 1: Find the latest timestamp by querying the first document in descending order of 'timestamp'
  final latestTimestampSnapshot = await collectionRef
      .orderBy('timestamp', descending: true)
      .limit(1)
      .get();

  if (latestTimestampSnapshot.docs.isEmpty) {
    return []; // No documents found, return an empty list
  }

  // Retrieve the latest timestamp value
  // Assuming 'timestamp' in Firestore is a String, adjust if it's an int or Timestamp
  final latestTimestamp = latestTimestampSnapshot.docs.first.get('timestamp');

  // Step 2: Query documents with the latest timestamp, ordered by 'tradesCountWithUniqueTraders'
  final latestDocsQuery = await collectionRef
      .where('timestamp', isEqualTo: latestTimestamp)
      .orderBy('tradesCountWithUniqueTraders', descending: true)
      .get();

  List<TokenData> tokens = [];

  for (var doc in latestDocsQuery.docs) {
    // Strip out empty entries or entries with null/empty Name/Symbol
    final name = doc['Name'];
    final symbol = doc['Symbol'];

    if (name == null ||
        symbol == null ||
        name.toString().trim().isEmpty ||
        symbol.toString().trim().isEmpty) {
      continue;
    }

    // Create a TokenData object from the Firestore document data
    tokens.add(TokenData.fromFirestore(doc.data()));
  }

  return tokens;
}

Future<List<TokenData>> fetchSOLDocuments() async {
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

  List<TokenData> tokens = [];

  for (var doc in latestDocsQuery.docs) {
    // Strip out empty entries or entries with null/empty Name/Symbol
    final name = doc['Name'];
    final symbol = doc['Symbol'];

    if (name == null ||
        symbol == null ||
        name.toString().trim().isEmpty ||
        symbol.toString().trim().isEmpty) {
      continue;
    }

    // Create a TokenData object from the Firestore document data
    tokens.add(TokenData.fromFirestore(doc.data()));
  }

  return tokens;
}


Future<List<Map<String, dynamic>>> fetchChartData(String contractAddress) async {
  try {
    final docRef = FirebaseFirestore.instance.collection('charts').doc(contractAddress);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      if (data != null && data.containsKey('minute_data') && data['minute_data'] is List) {
        // Cast the list to the expected type
        return List<Map<String, dynamic>>.from(data['minute_data']);
      } else {
        errorLogger('Document for contractAddress $contractAddress exists but does not contain a valid minute_data array.', 'fetchChartData');
        return [];
      }
    } else {
      errorLogger('No document found for contractAddress: $contractAddress in charts collection.', 'fetchChartData');
      return [];
    }
  } catch (e) {
    errorLogger('Error fetching chart data for $contractAddress: $e', 'fetchChartData');
    return [];
  }
}

void errorLogger(String errorMessage, String location) {
  try {
    FirebaseFirestore.instance.collection('error_logs').add({
      'error': errorMessage,
      'location': location,
      'timestamp': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // Silently fail if error logging itself fails
    print('Error logging failed: $e');
  }
}