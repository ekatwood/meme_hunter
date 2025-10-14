import functions_framework
import requests
import json
from typing import Optional, Dict, Any
import decimal
from solana.rpc.api import Client
from solders.pubkey import Pubkey
from solders.transaction import Transaction
from solders.transaction_status import VersionedTransaction
#from spl.token.instructions import get_associated_token_address
import base64
from google.cloud import secretmanager

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*', # Allows all origins for development
    'Access-Control-Allow-Methods': 'GET, OPTIONS', # Allow the methods you use
    'Access-Control-Allow-Headers': 'Content-Type', # Allow Content-Type header
    'Access-Control-Max-Age': '3600' # Cache preflight response for 1 hour
}

# --- Helper function to get secrets from Google Cloud Secret Manager ---
def get_secret(project_id: str, secret_id: str):

    # Add project id's to this as needed
    if(project_id == "meme_hunter"):
        project_id = "194957573763"
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        print(f"Error accessing secret: {e}")
        return None

def get_token_price_Moralis(contract_address: str, chain: str):

    if(chain == "eth"):
        url = f"https://deep-index.moralis.io/api/v2.2/erc20/{contract_address}/price"
        params = {
            "chain": chain
        }
    elif(chain == "sol"):
        url = f"https://solana-gateway.moralis.io/token/mainnet/" + f"{contract_address}/price"
        params = {}

    # Get the API key from Secret Manager
    api_key = get_secret("meme_hunter", "MORALIS_API_KEY")

    if not api_key:
        print("Failed to retrieve API key from Secret Manager. Exiting.")
        return {"error": "Failed to retrieve API key from Secret Manager. Exiting."}

    headers = {
        "Accept": "application/json",
        "X-API-Key": api_key
    }

    try:
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status() # Raise HTTPError for bad responses (4xx or 5xx)
        data = response.json()
        usd_price = data.get('usdPrice')
        return float(usd_price) if usd_price is not None else None
    except requests.exceptions.RequestException as e:
        print(f"Error fetching token price: {e}")
        return None
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON response: {e}")
        return None

def get_balance_Solflare(wallet_address: str, contract_address: str = None):
    try:
        # Get the API key from Secret Manager
        api_key = get_secret("meme_hunter", "HELIUS_API_KEY")

        if not api_key:
            print("Failed to retrieve API key from Secret Manager. Exiting.")
            return {"error": "Failed to retrieve API key from Secret Manager. Exiting."}

        RPC_URL = f"https://mainnet.helius-rpc.com/?api-key={api_key}"
        client = Client(RPC_URL)
        wallet_pubkey = Pubkey.from_string(wallet_address)
        print('got here')
        if not contract_address:
            # Case 1: Fetch native SOL balance
            balance_in_lamports = client.get_balance(wallet_pubkey).value
            return balance_in_lamports / 10**9  # 1 SOL = 10^9 Lamports
        #else:
            # Commenting out spl, it is not used yet for this app, it only checks SOL
            # Case 2: Fetch SPL token balance
#             token_mint_pubkey = Pubkey.from_string(contract_address)
#             token_account_address = get_associated_token_address(
#                 wallet_pubkey, token_mint_pubkey
#             )
#             token_accounts = client.get_token_account_balance(token_account_address)
#             if token_accounts.value.ui_amount:
#                 return token_accounts.value.ui_amount
#             else:
#                 print("No token account balance found for the provided mint address.")
#                 return 0
    except Exception as e:
        print(f"Error fetching balance: {e}")
        return None

def get_0x_swap_quote(token_contract_address, weth_amount_to_spend, taker_address):

    decimal.getcontext().prec = 50

    API_BASE_URL = "https://api.0x.org"
    WETH_CONTRACT_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    # The affiliate fee in basis points (BPS). 1 BPS = 0.01%.
    # 0.25% = 25 BPS.
    AFFILIATE_FEE_BPS = 25

    # Define the API endpoint for getting a quote.
    endpoint = f"{API_BASE_URL}/swap/allowance-holder/quote"

    try:
        # Get the API key from Secret Manager
        api_key = get_secret("meme_hunter", "0X_API_KEY")

        if not api_key:
            print("Failed to retrieve API key from Secret Manager. Exiting.")
            return {"error": "Failed to retrieve API key from Secret Manager. Exiting."}

        # Get the API key from Secret Manager
        fee_recipient_address = get_secret("meme_hunter", "0x_FEE_RECIPIENT_ADDRESS")

        if not fee_recipient_address:
            print("Failed to retrieve fee receipient address from Secret Manager. Exiting.")
            return {"error": "Failed to retrieve fee receipient address from Secret Manager. Exiting."}

        # Convert the human-readable WETH amount to the smallest unit (wei)
        # as required by the 0x API. 1 ETH = 10^18 wei.
        wei_amount_to_spend = int(decimal.Decimal(str(weth_amount_to_spend)) * decimal.Decimal('1e18'))

        # Define the query parameters for the API request.
        # sellToken and buyToken are contract addresses.
        # sellAmount is the amount of the sellToken in its smallest denomination (wei).
        # affiliateAddress and affiliateFeeBps are for collecting fees.
        params = {
            "chainId": 1,
            "sellToken": WETH_CONTRACT_ADDRESS,
            "buyToken": token_contract_address,
            "sellAmount": str(wei_amount_to_spend),
            "swapFeeRecipient": fee_recipient_address,
            "swapFeeBps": AFFILIATE_FEE_BPS,
            "swapFeeToken": WETH_CONTRACT_ADDRESS,
            "taker": taker_address,
        }

        # Set up the headers, including the API key for authentication.
        headers = {
            "0x-api-key": api_key,
            "0x-version": "v2",
            "Accept": "application/json"
        }

        # Make the GET request to the API.
        response = requests.get(endpoint, params=params, headers=headers)

        # Raise an exception for bad status codes (4xx or 5xx).
        response.raise_for_status()

        # Parse the JSON response.
        quote_data = response.json()
        return quote_data

    except requests.exceptions.RequestException as e:
        print(f"An error occurred during the API request: {e}")
        return {"error": str(e)}
    except (ValueError, TypeError) as e:
        print(f"Invalid input: {e}")
        return {"error": f"Invalid input: {e}"}

def generate_jupiter_swap_tx(
    output_token_mint: str,
    sol_amount_to_sell: float,
    user_wallet_address: str,
) -> Optional[Dict[str, Any]]:

    JUPITER_API_BASE_URL = "https://lite-api.jup.ag/swap/v1"
    SOL_MINT_ADDRESS = "So11111111111111111111111111111111111111112"
    # 0.25% in Basis Points (1 bp = 0.01%)
    FEE_BPS = 25
    # Standard SOL decimals
    SOL_DECIMALS = 9
    # 1. Convert SOL amount to Lamports (1 SOL = 10^9 Lamports)
    amount_in_lamports = int(sol_amount_to_sell * (10 ** SOL_DECIMALS))

    quote_url = f"{JUPITER_API_BASE_URL}/quote"
    quote_params = {
        "inputMint": SOL_MINT_ADDRESS,
        "outputMint": output_token_mint,
        "amount": amount_in_lamports,
        "platformFeeBps": FEE_BPS,
    }

    try:
        response = requests.get(quote_url, params=quote_params)
        response.raise_for_status() # Raise an HTTPError for bad responses (4xx or 5xx)
        quote_response = response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error fetching quote: {e}")
        return {"error": f"Error fetching quote: {e}"}

    if not quote_response.get("outAmount"):
        print("Quote response did not return a valid route or outAmount.")
        # print(json.dumps(quote_response, indent=2))
        return {"error": f"Quote response did not return a valid route or outAmount. {e}"}

    swap_url = f"{JUPITER_API_BASE_URL}/swap"
    # Get fee account address from Secret Manager
    fee_recipient_address = get_secret("meme_hunter", "JUPITER_FEE_RECIPIENT_ADDRESS")

    if not fee_recipient_address:
        print("Failed to retrieve fee receipient address from Secret Manager. Exiting.")
        return {"error": "Failed to retrieve fee receipient address from Secret Manager. Exiting."}

    swap_body = {
        "quoteResponse": quote_response,
        "userPublicKey": user_wallet_address,
        "feeAccount": fee_recipient_address,
    }

    try:
        response = requests.post(
            swap_url,
            headers={"Content-Type": "application/json"},
            data=json.dumps(swap_body)
        )
        response.raise_for_status()
        swap_transaction = response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error generating swap transaction: {e}")
        return {"error": f"Error generating swap transaction: {e}"}

    return swap_transaction

def send_transaction_Solana(signed_transaction_base64: str):
    try:
        tx_bytes = base64.b64decode(signed_transaction_base64)
        try:
            signed_transaction = VersionedTransaction.from_bytes(tx_bytes)
        except Exception:
            signed_transaction = Transaction.from_bytes(tx_bytes)

        # Get the API key from Secret Manager
        api_key = get_secret("meme_hunter", "HELIUS_API_KEY")

        if not api_key:
            print("Failed to retrieve API key from Secret Manager. Exiting.")
            return {"error": "Failed to retrieve API key from Secret Manager. Exiting."}

        RPC_URL = f"https://mainnet.helius-rpc.com/?api-key={api_key}"
        client = Client(RPC_URL)

        response = client.send_transaction(signed_transaction)

        signature = str(response.value)

        confirmation_response = client.confirm_transaction(signature)

        if confirmation_response.value.is_err():
            print(f"Transaction confirmation failed or timed out: {confirmation_response.value.err}")
            return {"error": f"Transaction confirmation failed or timed out: {confirmation_response.value.err}"}

        return signature
    except Exception as e:
        print(f"Error sending Solana transaction: {e}")
        return {"error": f"Error sending Solana transaction: {e}"}

# --- The main entry point for a single deployed function ---
@functions_framework.http
def api_router(request):

    # --- 1. HANDLE CORS PRE-FLIGHT REQUEST ---
    if request.method == 'OPTIONS':
        # Send a 204 No Content response with CORS headers
        return ('', 204, CORS_HEADERS)
    # --- 2. HANDLE MAIN REQUEST ---

    # Check if we have arguments (from GET request URL)
    if request.args:
        request_args = request.args
    else:
        # Check if we have a JSON body (for POST request, though not used here)
        try:
            request_json = request.get_json(silent=True)
            request_args = request_json
        except:
            return ("Invalid request format", 400, CORS_HEADERS)

    function_name = request_args.get("function", "")

    if not function_name:
        return ("Missing function parameter", 400, CORS_HEADERS)

    if function_name == "get_token_price_Moralis":
        contract = request_args.get("contract_address")
        chain = request_args.get("chain")
        if not contract:
            return ("Missing contract parameter", 400, CORS_HEADERS)
        if not chain:
            return ("Missing chain parameter", 400, CORS_HEADERS)
        result = get_token_price_Moralis(contract, chain)
        return ({"token_price": result}, 200, CORS_HEADERS) if result is not None else ("Error fetching token price", 500, CORS_HEADERS)

    elif function_name == "get_balance_Solflare":
        print('in api_router, function = get_balance_Solflare')
        wallet = request_args.get("wallet_address")
        contract = request_args.get("contract_address")
        if not wallet:
            return ("Missing wallet_address parameter", 400, CORS_HEADERS)
        print('wallet = ' + wallet)
        result = get_balance_Solflare(wallet, contract)
        return ({"balance": result}, 200, CORS_HEADERS) if result is not None else ("Error fetching balance", 500, CORS_HEADERS)

    elif function_name == "get_0x_swap_quote":
        token = request_args.get("token_contract_address")
        weth_amount = request_args.get("weth_amount_to_spend")
        taker = request_args.get("taker_address")
        if not token:
            return ("Missing token parameter", 400, CORS_HEADERS)
        if not weth_amount:
            return ("Missing weth_amount parameter", 400, CORS_HEADERS)
        if not taker:
            return ("Missing taker parameter", 400, CORS_HEADERS)
        result = get_0x_swap_quote(token, weth_amount, taker)
        return ({"quote": result}, 200, CORS_HEADERS) if result is not None else ("Error fetching 0x quote", 500, CORS_HEADERS)

    elif function_name == "generate_jupiter_swap_tx":
        token = request_args.get("output_token_mint")
        sol_amount = request_args.get("sol_amount_to_sell")
        user_wallet = request_args.get("user_wallet_address")
        if not token:
            return ("Missing token parameter", 400, CORS_HEADERS)
        if not sol_amount:
            return ("Missing sol_amount parameter", 400, CORS_HEADERS)
        if not user_wallet:
            return ("Missing user_wallet parameter", 400, CORS_HEADERS)
        result = generate_jupiter_swap_tx(token, sol_amount, user_wallet)
        return ({"swap_tx": result}, 200, CORS_HEADERS) if result is not None else ("Error fetching Jupiter swap transaction", 500, CORS_HEADERS)

    elif function_name == "send_transaction_Solana":
        tx = request_args.get("signed_transaction_base64")
        if not tx:
            return ("Missing signed_transaction_base64 parameter", 400, CORS_HEADERS)
        result = send_transaction_Solana(tx)
        return ({"signature": result}, 200, CORS_HEADERS) if result is not None else ("Error sending Solana transaction", 500, CORS_HEADERS)
    else:
        return ("Invalid function name specified", 400, CORS_HEADERS)
