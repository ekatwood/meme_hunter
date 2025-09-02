import 'dart:convert';
import 'utils.dart';
import 'package:http/http.dart' as http;

// TODO: move these queries into google cloud functions. stubbing out for now
double getTokenPriceMoralis(String contractAddress){
    print('getTokenPriceMoralis(String contractAddress)');
    return 4408;
}

double getTokenPriceMoralisSOL(String contractAddress){
    print('getTokenPriceMoralisSOL(String contractAddress)');
    return 183;
}

// TODO: set up in gcloud, because this uses an RPC node with an api key
double getBalanceSolflare(String contractAddress){
    print('getBalanceSolflare(String contractAddress)');
    return 7.2;
}

/**
 * Mock function to simulate a call to a GCloud function that gets a 0x quote.
 * This function returns a hardcoded transaction object.
 * In a real application, you would replace this with an actual network call.
 * @param {Map<String, dynamic>} params - The parameters for the 0x API call (sellToken, buyToken, etc.).
 * @returns {Future<Map<String, dynamic>>} A future that resolves with a mock 0x quote object.
 */
Future<Map<String, dynamic>> get0xQuote(Map<String, dynamic> params) async {
    print("Mocking 0x API call with parameters: $params");

    // This is a hardcoded mock transaction object.
    // In a real scenario, this would be the JSON response from your GCloud function.
    final Map<String, dynamic> mockQuote = {
        // The "to" address is the 0x Exchange Proxy contract.
        "to": "0xDef1C0ded9FD7C55C148bC7A8b724f605f6396f4",
        // "data" contains the encoded function call to perform the swap.
        "data": "0x4114f484000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000000000000000000000100000000000000000000000067342938f32ac9105ed1a403061ce88647ac235c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
        // "value" is the amount of ETH (or WETH in this case, which is a different flow) to send with the transaction.
        // For WETH swaps, this would typically be '0'.
        "value": "0x0",
        // "gasPrice" and "gas" are included for a complete transaction object.
        "gasPrice": "0x4a817c800",
        "gas": "0x989680"
    };

    // Simulate a network delay
    await Future.delayed(Duration(seconds: 1));

    return mockQuote;
}