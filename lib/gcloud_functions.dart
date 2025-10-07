import 'dart:convert';
import 'package:http/http.dart' as http;

// TODO: add real url
const String _baseUrl = 'https://YOUR_REGION-YOUR_PROJECT_ID.cloudfunctions.net/';

Future<double> getTokenPriceMoralis(String contractAddress, String blockchain) async {
    print('getTokenPriceMoralis(String contractAddress)');
    String fullUrl = _baseUrl + "get_token_price_Moralis";
    final uri = Uri.parse('$fullUrl?contract_address=$contractAddress&chain=$blockchain');

    try {
        final response = await http.get(uri);

        if (response.statusCode == 200) {
            final jsonResponse = jsonDecode(response.body);
            // The function returns a JSON object with the balance.
            return jsonResponse['token_price'] as double;
        } else {
            // Handle the error here
            print('Request failed with status: ${response.statusCode}.');
            print('Response body: ${response.body}');
            throw Exception('Failed to fetch token price.');
        }
    } catch (e) {
        print('Error: $e');
        throw Exception('Error calling gcloud function get_token_price_Moralis: $e');
    }
}

Future<double> getBalanceSolflare(String walletAddress) async {
    print('getBalanceSolflare(String contractAddress)');

    String fullUrl = _baseUrl + "get_balance_Solflare";
    final uri = Uri.parse('$fullUrl?wallet_address=$walletAddress');

    try {
        final response = await http.get(uri);

        if (response.statusCode == 200) {
            final jsonResponse = jsonDecode(response.body);
            // The function returns a JSON object with the balance.
            return jsonResponse['balance'] as double;
        } else {
            // Handle the error here
            print('Request failed with status: ${response.statusCode}.');
            print('Response body: ${response.body}');
            throw Exception('Failed to load Solana balance');
        }
    } catch (e) {
        print('Error: $e');
        throw Exception('Error calling gcloud function get_token_price_Moralis: $e');
    }
}

Future<Map<String, dynamic>> get0xQuote(String tokenContractAddress, double WETHAmountToSpend, String takerAddress) async {
    String fullUrl = _baseUrl + "get_0x_swap_quote";
    final uri = Uri.parse('$fullUrl?token_contract_address=$tokenContractAddress&weth_amount_to_spend=$WETHAmountToSpend&taker_address=$takerAddress');

    try {
        final response = await http.get(uri);

        if (response.statusCode == 200) {
            final jsonResponse = jsonDecode(response.body);
            // The function returns a JSON object with the balance.
            return jsonResponse['quote'] as Map<String, dynamic>;
        } else {
            // Handle the error here
            print('Request failed with status: ${response.statusCode}.');
            print('Response body: ${response.body}');
            throw Exception('Failed to fetch 0x API quote.');
        }
    } catch (e) {
        print('Error: $e');
        throw Exception('Error calling gcloud function get_0x_swap_quote: $e');
    }
}

Future<Map<String, dynamic>> getJupiterQuote(String outputTokenMint, double SOLAmountToSell, String userWalletAddress) async {
    String fullUrl = _baseUrl + "generate_jupiter_swap_tx";
    final uri = Uri.parse('$fullUrl?output_token_mint=$outputTokenMint&sol_amount_to_sell=$SOLAmountToSell&user_wallet_address=$userWalletAddress');

    try {
        final response = await http.get(uri);

        if (response.statusCode == 200) {
            final jsonResponse = jsonDecode(response.body);
            // The function returns a JSON object with the balance.
            return jsonResponse['swap_tx'] as Map<String, dynamic>;
        } else {
            // Handle the error here
            print('Request failed with status: ${response.statusCode}.');
            print('Response body: ${response.body}');
            throw Exception('Failed to generate Jupiter API transaction.');
        }
    } catch (e) {
        print('Error: $e');
        throw Exception('Error calling gcloud function generate_jupiter_swap_tx: $e');
    }
}

Future <String> sendTransactionSolana(String signedTransactionBase64) async {
    String fullUrl = _baseUrl + "send_transaction_Solana";
    final uri = Uri.parse('$fullUrl?signed_transaction_base64=$signedTransactionBase64');

    try {
        final response = await http.get(uri);

        if (response.statusCode == 200) {
            final jsonResponse = jsonDecode(response.body);
            // The function returns a JSON object with the balance.
            return jsonResponse['signature'] as String;
        } else {
            // Handle the error here
            print('Request failed with status: ${response.statusCode}.');
            print('Response body: ${response.body}');
            throw Exception('Failed to complete Solana transaction.');
        }
    } catch (e) {
        print('Error: $e');
        throw Exception('Error calling gcloud function send_transaction_Solana: $e');
    }
}