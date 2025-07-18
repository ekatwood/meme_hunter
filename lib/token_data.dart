// token_data.dart
import 'package:intl/intl.dart';

class TokenData {
  final String name;
  final String smartContract;
  final String symbol;
  final String? circulatingSupply; // Nullable if not always present
  final String? marketCap;
  final String? description;
  final String? websiteLink;
  final String? twitterLink;
  final String? firebaseLogoUrl;
  final int? tradesCountWithUniqueTraders;
  final String? timestamp; // Changed to String? to match your Firestore data type

  TokenData({
    required this.name,
    required this.smartContract,
    required this.symbol,
    this.circulatingSupply,
    this.marketCap,
    this.description,
    this.websiteLink,
    this.twitterLink,
    this.firebaseLogoUrl,
    this.tradesCountWithUniqueTraders,
    this.timestamp,
  });

  // Factory constructor to create a TokenData object from a Firestore document map
  factory TokenData.fromFirestore(Map<String, dynamic> doc) {
    return TokenData(
      name: doc['Name'] as String? ?? 'N/A', // Provide a default if null
      smartContract: doc['SmartContract'] as String? ?? 'N/A',
      symbol: doc['Symbol'] as String? ?? 'N/A',
      circulatingSupply: doc['circulating_supply'] as String?,
      marketCap: doc['market_cap'] as String?,
      description: doc['description'] as String?,
      websiteLink: doc['website_link'] as String?,
      twitterLink: doc['twitter_link'] as String?,
      firebaseLogoUrl: doc['firebase_logo_url'] as String?,
      tradesCountWithUniqueTraders: doc['tradesCountWithUniqueTraders'] as int?,
      timestamp: doc['timestamp'] as String?, // Ensure this matches Firestore type
    );
  }

  String get formattedCirculatingSupply {
    if (circulatingSupply == null || circulatingSupply!.isEmpty) {
      return 'N/A';
    }

    try {
      final int value = int.parse(circulatingSupply!);
      final formatter = NumberFormat.currency(
        locale: 'en_US', // Use en_US locale for comma formatting
        symbol: '',      // No currency symbol
        decimalDigits: 0, // No decimal digits for whole numbers
      );

      if (value < 1000000) {
        // Less than 1 million, use commas
        return formatter.format(value);
      } else if (value < 1000000000) {
        // Between 1 million and 1 billion, use M notation
        final double millions = value / 1000000.0;
        return '${millions.toStringAsFixed(2)}M';
      } else {
        // 1 billion or more, use B notation
        final double billions = value / 1000000000.0;
        return '${billions.toStringAsFixed(2)}B';
      }
    } catch (e) {
      // Handle parsing errors (e.g., if circulatingSupply is not a valid integer string)
      print('Error parsing circulatingSupply: $circulatingSupply, Error: $e');
      return 'Invalid Data'; // Or return circulatingSupply! if you want to show the raw invalid string
    }
  }

  String get formattedmarketCap {
    if (marketCap == null || marketCap!.isEmpty) {
      return 'N/A';
    }

    try {
      final int value = int.parse(marketCap!);
      final formatter = NumberFormat.currency(
        locale: 'en_US', // Use en_US locale for comma formatting
        symbol: '',      // No currency symbol
        decimalDigits: 0, // No decimal digits for whole numbers
      );

      if (value < 1000000) {
        // Less than 1 million, use commas
        return r'$'+formatter.format(value);
      } else if (value < 1000000000) {
        // Between 1 million and 1 billion, use M notation
        final double millions = value / 1000000.0;
        return r'$''${millions.toStringAsFixed(2)}M';
      } else {
        // 1 billion or more, use B notation
        final double billions = value / 1000000000.0;
        return r'$''${billions.toStringAsFixed(2)}B';
      }
    } catch (e) {
      // Handle parsing errors (e.g., if circulatingSupply is not a valid integer string)
      print('Error parsing circulatingSupply: $marketCap, Error: $e');
      return 'Invalid Data'; // Or return circulatingSupply! if you want to show the raw invalid string
    }
  }

}

