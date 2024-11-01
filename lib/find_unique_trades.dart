import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

void fetchUniqueTrades() async {
  print('hi');
  var db = FirebaseFirestore.instance;

  //print(db.databaseId);
  //query: Path is tokens_by_timestamp
  //order by timestamp descending
  //limit 350
  //stop reading query programmatically if an older timestamp appears


  // //reading from db
  // await db.collection('tokens_by_timestamp').get().then((event) {
  //   for (var doc in event.docs) {
  //     print("${doc.id} => ${doc.data()}");
  //   }
  // });


}