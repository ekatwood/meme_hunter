// token_data.dart
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
}