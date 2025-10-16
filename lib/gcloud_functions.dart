import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

const String _baseUrl = 'https://us-central1-meme-hunter-4f1c1.cloudfunctions.net/api_router';

Future<double> getTokenPriceMoralis(String contractAddress, String blockchain) async {
    String fullUrl = _baseUrl + '?function=get_token_price_Moralis';
    final urlString = fullUrl + '&contract_address=$contractAddress&chain=$blockchain';

    try {
        final uri = Uri.parse(urlString);
        final response = await http.get(uri);

        if (response.statusCode == 200) {
            print('response 200 from gcloud function');
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
    String fullUrl = _baseUrl + '?function=get_balance_Solflare';
    final urlString = fullUrl + '&wallet_address=$walletAddress';

    try {
        final uri = Uri.parse(urlString);
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
    print('get0xQuote(String tokenContractAddress, double WETHAmountToSpend, String takerAddress)');
    String fullUrl = _baseUrl + "?function=get_0x_swap_quote";
    final uri = Uri.parse('$fullUrl&token_contract_address=$tokenContractAddress&weth_amount_to_spend=$WETHAmountToSpend&taker_address=$takerAddress');

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
    // Perform the calculation (1 SOL = 10^9 Lamports)
    const int solDecimals = 9;
    // We use .round() to ensure correct integer conversion after multiplication
    final int lamportAmountToSell = (SOLAmountToSell * math.pow(10, solDecimals)).round();

    String fullUrl = _baseUrl + "?function=generate_jupiter_swap_tx";
    // Change parameter name in the URI to reflect Lamports
    final uri = Uri.parse('$fullUrl&output_token_mint=$outputTokenMint&lamport_amount_to_sell=$lamportAmountToSell&user_wallet_address=$userWalletAddress');

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
    print('sendTransactionSolana(String signedTransactionBase64)');
    String fullUrl = _baseUrl + "?function=send_transaction_Solana";
    final uri = Uri.parse('$fullUrl&signed_transaction_base64=$signedTransactionBase64');

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