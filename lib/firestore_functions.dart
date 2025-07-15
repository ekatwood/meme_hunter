import 'package:cloud_firestore/cloud_firestore.dart';

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

  Map<int, dynamic> tokens = {};
  var counter = 1;

  for(var doc in latestDocsQuery.docs){
    //strip out empty entries
    if (doc['Name'] == null ||
        doc['Symbol'] == null ||
        doc['Name'].toString().trim().isEmpty ||
        doc['Symbol'].toString().trim().isEmpty) continue;

    tokens[counter] = {
      'Name': doc['Name'],
      'SmartContract': doc['SmartContract'],
      'Symbol': doc['Symbol'],
      'circulating_supply': doc['circulating_supply'],
      'market_cap': doc['market_cap'],
      'description': doc['description'],
      'website_link': doc['website_link'],
      'twitter_link': doc['twitter_link'],
      'firebase_logo_url': doc['firebase_logo_url'],
      'tradesCountWithUniqueTraders': doc['tradesCountWithUniqueTraders'],
      'timestamp': doc['timestamp']
    };
    counter += 1;
  }
  return tokens;
}

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

  Map<int, dynamic> tokens = {};
  var counter = 1;

  for(var doc in latestDocsQuery.docs){
    tokens[counter] = {
      'Name': doc['Name'],
      'SmartContract': doc['MintAddress'],
      'Symbol': doc['Symbol'],
      'circulating_supply': doc['totalSupplyFormatted'],
      'market_cap': doc['fullyDilutedValue'],
      'description': doc['description'],
      'website_link': doc['website_link'],
      'twitter_link': doc['twitter_link'],
      'firebase_logo_url': doc['firebase_logo_url'],
      'timestamp': doc['timestamp']
    };
    counter += 1;
  }
  return tokens;
}

/// Fetches the minute_data array for a given contract address from the 'charts' collection.
///
/// Returns a List of Maps, where each Map represents a minute data point
/// with 'timestamp' and 'open' price. Returns an empty list if the document
/// or the 'minute_data' field does not exist, or if an error occurs.
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