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

# --- Your original get_balance_solflare function ---
def get_balance_solflare(wallet_address: str, contract_address: str = None):
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

# --- The main entry point for a single deployed function ---
@functions_framework.http
def api_router(request):
    request_args = request.args
    function_name = request_args.get("function", "")

    if function_name == "get_balance":
        wallet = request_args.get("wallet_address")
        contract = request_args.get("contract_address")
        if not wallet:
            return "Missing wallet_address parameter", 400
        result = get_balance_solflare(wallet, contract)
        return {"balance": result} if result is not None else "Error fetching balance", 500

    elif function_name == "other function":
        wallet = request_args.get("wallet_address")
        if not wallet:
            return "Missing wallet_address parameter", 400
        result = get_recent_transactions(wallet)
        return result

    else:
        return "Invalid function name specified", 400
