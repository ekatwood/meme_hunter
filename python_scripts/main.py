import functions_framework
from get_balance_solflare import get_balance_solflare
from flask import jsonify

@functions_framework.http
def get_balance(request):
    """
    HTTP Cloud Function to get a Solana wallet's balance.
    """
    # Set CORS headers
    headers = {
        'Access-Control-Allow-Origin': '*'
    }
    if request.method == 'OPTIONS':
        return ('', 204, headers)

    request_json = request.get_json(silent=True)
    if not request_json or 'wallet_address' not in request_json:
        return jsonify({'error': 'Missing wallet_address'}), 400, headers

    wallet_address = request_json['wallet_address']
    contract_address = request_json.get('contract_address')

    balance = get_balance_solflare(wallet_address, contract_address)

    if balance is not None:
        return jsonify({'balance': balance}), 200, headers
    else:
        return jsonify({'error': 'Failed to fetch balance'}), 500, headers
