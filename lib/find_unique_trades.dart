import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

Future<List<QueryDocumentSnapshot>> fetchDocumentsTESTING() async {
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
      .get();

  for (var doc in latestDocsQuery.docs) {
    print(doc['Name']);
    print(doc['Symbol']);
    print(doc['tradesCountWithUniqueTraders']);
    print(doc['timestamp']);
    print('===');
  }

  return latestDocsQuery.docs;
}


class TokensDataTable extends StatefulWidget {
  @override
  _TokensDataTableState createState() => _TokensDataTableState();
}

class _TokensDataTableState extends State<TokensDataTable> {
  Future<List<QueryDocumentSnapshot>> fetchDocuments() async {
    // Reference to the collection
    final collectionRef = FirebaseFirestore.instance.collection('tokens_by_timestamp');

    // Step 1: Find the latest timestamp by querying the first document in descending order of 'timestamp'
    final latestTimestampSnapshot = await collectionRef
        .orderBy('timestamp', descending: true)
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

    print(latestDocsQuery);

    return latestDocsQuery.docs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<QueryDocumentSnapshot>>(
        future: fetchDocuments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No data available'));
          }

          // Data is available; build the DataTable
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Symbol')),
                DataColumn(label: Text('Unique Trades')),
              ],
              rows: snapshot.data!.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return DataRow(cells: [
                  DataCell(Text(data['Name'].toString())), // Replace 'tokenId' with your actual field
                  DataCell(Text(data['Symbol'].toString())), // Adjust for the timestamp field
                  DataCell(Text(data['tradesCountWithUniqueTraders'].toString())), // Adjust as needed
                  // Add more cells as needed
                ]);
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
