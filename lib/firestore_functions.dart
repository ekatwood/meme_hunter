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

void phantomWalletConnected(String walletAddress) {
  try {
    // Check if wallet already exists in database
    FirebaseFirestore.instance
        .collection('phantom_wallets')
        .where('wallet_address', isEqualTo: walletAddress)
        .get()
        .then((snapshot) {
      // If wallet doesn't exist, add it
      if (snapshot.docs.isEmpty) {
        FirebaseFirestore.instance.collection('phantom_wallets').add({
          'wallet_address': walletAddress,
          'connected_at': FieldValue.serverTimestamp(),
        });
      } else {
        // Update last connection time
        FirebaseFirestore.instance
            .collection('phantom_wallets')
            .doc(snapshot.docs.first.id)
            .update({
          'last_connected': FieldValue.serverTimestamp(),
        });
      }
    });
  } catch (e) {
    errorLogger(e.toString(), 'phantomWalletConnected()');
  }
}