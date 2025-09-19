# cd '' && '/usr/local/bin/python3'  'get_balance_solflare.py'

from solana.rpc.api import Client
from solders.pubkey import Pubkey
from spl.token.instructions import get_associated_token_address
from utils import utils

def get_balance_solflare(wallet_address: str, contract_address: str = None):
    """
    Fetches the native SOL or SPL token balance for a given wallet address.

    Args:
        wallet_address (str): The public key of the wallet.
        contract_address (str): The mint address of the SPL token. If None,
                                the native SOL balance is returned.

    Returns:
        float: The balance of the specified asset, or None if an error occurs.
    """
    try:
        # --- Get the API key from Secret Manager ---
        api_key = utils.get_secret("meme_hunter", "HELIUS_API_KEY")

        if not api_key:
            print("Failed to retrieve API key from Secret Manager. Exiting.")
            return None

        RPC_URL = "https://mainnet.helius-rpc.com/?api-key=" # + API KEY FROM SECRET MANAGER
        client = Client(RPC_URL)
        wallet_pubkey = Pubkey.from_string(wallet_address)

        if not contract_address:
            # Case 1: Fetch native SOL balance
            balance_in_lamports = client.get_balance(wallet_pubkey).value
            return balance_in_lamports / 10**9  # 1 SOL = 10^9 Lamports
        else:
            # Case 2: Fetch SPL token balance
            token_mint_pubkey = Pubkey.from_string(contract_address)

            # Get the address of the associated token account
            token_account_address = get_associated_token_address(
                wallet_pubkey, token_mint_pubkey
            )

            # Fetch the balance of the associated token account
            token_accounts = client.get_token_account_balance(token_account_address)

            if token_accounts.value.ui_amount:
                return token_accounts.value.ui_amount
            else:
                print("No token account balance found for the provided mint address.")
                return 0

    except Exception as e:
        print(f"Error fetching balance: {e}")
        return None

# sol_balance = get_balance_solflare("9q9MD5ujVSj1Ut7dQTurTfcrcS3CpScz3nLD1qJ3zpfe")
# print(f"SOL Balance: {sol_balance}")
