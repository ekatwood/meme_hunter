import 'utils.dart'; // Assuming utils.dart contains formatBigNumber

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
  final String? timestamp; // Changed to String? to match your Firestore data type

  final String blockchainNetwork = "ETH"; // Default, but consider making this dynamic if needed

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
    this.timestamp,
  });

  // Factory constructor to create a TokenData object from a Firestore document map
  factory TokenData.fromFirestore(Map<String, dynamic> doc) {
    return TokenData(
      name: doc['Name'] as String? ?? 'N/A', // Provide a default if null
      smartContract: doc['SmartContract'] as String? ?? 'N/A',
      symbol: doc['Symbol'] as String? ?? 'N/A',
      circulatingSupply: formatBigNumber(doc['circulating_supply']) as String?,
      marketCap: formatBigNumber(doc['market_cap']) as String?,
      description: doc['description'] as String?,
      websiteLink: doc['website_link'] as String?,
      twitterLink: doc['twitter_link'] as String?,
      firebaseLogoUrl: doc['firebase_logo_url'] as String?,
      timestamp: doc['timestamp'] as String?, // Ensure this matches Firestore type
    );
  }

  // New: Method to convert a TokenData object to a JSON-compatible map
  Map<String, dynamic> toJson() {
    return {
      'Name': name,
      'SmartContract': smartContract,
      'Symbol': symbol,
      'circulating_supply': circulatingSupply,
      'market_cap': marketCap,
      'description': description,
      'website_link': websiteLink,
      'twitter_link': twitterLink,
      'firebase_logo_url': firebaseLogoUrl,
      'timestamp': timestamp,
      // Note: blockchainNetwork is not stored as it's a constant or derived
    };
  }

  // New: Factory constructor to create a TokenData object from a JSON map (for shared_preferences)
  factory TokenData.fromJson(Map<String, dynamic> json) {
    return TokenData(
      name: json['Name'] as String? ?? 'N/A',
      smartContract: json['SmartContract'] as String? ?? 'N/A',
      symbol: json['Symbol'] as String? ?? 'N/A',
      circulatingSupply: json['circulating_supply'] as String?,
      marketCap: json['market_cap'] as String?,
      description: json['description'] as String?,
      websiteLink: json['website_link'] as String?,
      twitterLink: json['twitter_link'] as String?,
      firebaseLogoUrl: json['firebase_logo_url'] as String?,
      timestamp: json['timestamp'] as String?,
    );
  }
}