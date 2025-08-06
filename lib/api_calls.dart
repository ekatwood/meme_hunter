import 'dart:convert';
import 'utils.dart';
import 'package:http/http.dart' as http;

Future<double?> getTokenPriceMoralis({
  required String contractAddress,
  required String remoteConfigParameter,
  String chain = "eth",
}) async {
  final url = "https://deep-index.moralis.io/api/v2.2/erc20/$contractAddress/price";
  String apiKey = getRemoteConfigValue(remoteConfigParameter) as String;

  final headers = {
    "Accept": "application/json",
    "X-API-Key": apiKey,
  };
  final params = {
    "chain": chain,
  };

  try {
    final uri = Uri.parse(url).replace(queryParameters: params);
    final response = await http.get(uri, headers: headers);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body);
      final usdPrice = data['usdPrice'];
      return usdPrice != null ? usdPrice.toDouble() : null;
    } else {
      print("Error fetching token price: ${response.statusCode} - ${response.reasonPhrase}");
      return null;
    }
  } catch (e) {
    print("Error: $e");
    return null;
  }
}

Future<double?> getTokenPriceMoralisSOL({
  required String contractAddress,
  required String remoteConfigParameter,
  String chain = "solana",
}) async {
  final url = "https://solana-gateway.moralis.io/token/$chain/$contractAddress/price";
  String apiKey = getRemoteConfigValue(remoteConfigParameter) as String;

  final headers = {
    "Accept": "application/json",
    "X-API-Key": apiKey,
  };

  try {
    final uri = Uri.parse(url);
    final response = await http.get(uri, headers: headers);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body);
      final usdPrice = data['usdPrice'];
      return usdPrice != null ? usdPrice.toDouble() : null;
    } else {
      print("Error fetching token price: ${response.statusCode} - ${response.reasonPhrase}");
      return null;
    }
  } catch (e) {
    print("Error: $e");
    return null;
  }
}