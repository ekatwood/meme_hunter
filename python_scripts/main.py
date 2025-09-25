import functions_framework
from solana.rpc.api import Client
from solders.pubkey import Pubkey
from spl.token.instructions import get_associated_token_address
from google.cloud import secretmanager

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
        return None

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
            return None

        RPC_URL = f"https://mainnet.helius-rpc.com/?api-key={api_key}"
        client = Client(RPC_URL)
        wallet_pubkey = Pubkey.from_string(wallet_address)

        if not contract_address:
            # Case 1: Fetch native SOL balance
            balance_in_lamports = client.get_balance(wallet_pubkey).value
            return balance_in_lamports / 10**9  # 1 SOL = 10^9 Lamports
        else:
            # Case 2: Fetch SPL token balance
            token_mint_pubkey = Pubkey.from_string(contract_address)
            token_account_address = get_associated_token_address(
                wallet_pubkey, token_mint_pubkey
            )
            token_accounts = client.get_token_account_balance(token_account_address)
            if token_accounts.value.ui_amount:
                return token_accounts.value.ui_amount
            else:
                print("No token account balance found for the provided mint address.")
                return 0
    except Exception as e:
        print(f"Error fetching balance: {e}")
        return None

# def get_0x_quote(Map<String, dynamic> params):
#
# def get_Jupiter_quote(Map<String, dynamic> params):
#
# def send_Solana_transaction():

# --- The main entry point for a single deployed function ---
@functions_framework.http
def api_router(request):
    request_args = request.args
    function_name = request_args.get("function", "")

    if function_name == "get_token_price_Moralis":
        contract = request_args.get("contract_address")
        chain = request_args.get("chain")
        if not contract:
            return "Missing contract parameter", 400
        if not chain:
            return "Missing chain parameter", 400
        result = get_token_price_Moralis(contract, chain)
        return {"token_price": result} if result is not None else "Error fetching token price", 500

    elif function_name == "get_balance_Solflare":
        wallet = request_args.get("wallet_address")
        contract = request_args.get("contract_address")
        if not wallet:
            return "Missing wallet_address parameter", 400
        result = get_balance_Solflare(wallet, contract)
        return {"balance": result} if result is not None else "Error fetching balance", 500

    else:
        return "Invalid function name specified", 400
