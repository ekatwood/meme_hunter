import 'dart:convert';
import 'utils.dart';
import 'package:http/http.dart' as http;

// TODO: move these queries into google cloud functions. stubbing out for now
double getTokenPriceMoralis(String contractAddress){
    print('getTokenPriceMoralis(String contractAddress)');
    return 4197;
}

double getTokenPriceMoralisSOL(String contractAddress){
    print('getTokenPriceMoralisSOL(String contractAddress)');
    return 145.23;
}

// TODO: set up in gcloud, because this uses an RPC node with an api key
double getBalanceSolflare(String contractAddress){
    print('getBalanceSolflare(String contractAddress)');
    return 10.5;
}
// Moralis API key remote config parameter: moralis_api_key
// WETH address: 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
// Future<double?> getTokenPriceMoralis({
//   required String contractAddress,
//   required String remoteConfigParameter,
//   String chain = "eth",
// }) async {
//   final url = "https://deep-index.moralis.io/api/v2.2/erc20/$contractAddress/price";
//   String apiKey = getRemoteConfigValue(remoteConfigParameter) as String;
//
//   final headers = {
//     "Accept": "application/json",
//     "X-API-Key": apiKey,
//   };
//   final params = {
//     "chain": chain,
//   };
//
//   try {
//     final uri = Uri.parse(url).replace(queryParameters: params);
//     final response = await http.get(uri, headers: headers);
//
//     if (response.statusCode >= 200 && response.statusCode < 300) {
//       final data = json.decode(response.body);
//       final usdPrice = data['usdPrice'];
//       return usdPrice != null ? usdPrice.toDouble() : null;
//     } else {
//       print("Error fetching token price: ${response.statusCode} - ${response.reasonPhrase}");
//       return null;
//     }
//   } catch (e) {
//     print("Error: $e");
//     return null;
//   }
// }
//
// // wSOL address: So11111111111111111111111111111111111111112
// Future<double?> getTokenPriceMoralisSOL({
//   required String contractAddress,
//   required String remoteConfigParameter,
//   String chain = "solana",
// }) async {
//   final url = "https://solana-gateway.moralis.io/token/$chain/$contractAddress/price";
//   String apiKey = getRemoteConfigValue(remoteConfigParameter) as String;
//
//   final headers = {
//     "Accept": "application/json",
//     "X-API-Key": apiKey,
//   };
//
//   try {
//     final uri = Uri.parse(url);
//     final response = await http.get(uri, headers: headers);
//
//     if (response.statusCode >= 200 && response.statusCode < 300) {
//       final data = json.decode(response.body);
//       final usdPrice = data['usdPrice'];
//       return usdPrice != null ? usdPrice.toDouble() : null;
//     } else {
//       print("Error fetching token price: ${response.statusCode} - ${response.reasonPhrase}");
//       return null;
//     }
//   } catch (e) {
//     print("Error: $e");
//     return null;
//   }
// }