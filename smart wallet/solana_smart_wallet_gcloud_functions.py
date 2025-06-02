import os
import requests
import base58
import smtplib
from email.mime.text import MIMEText
import struct # For manual deserialization if borsh-py isn't perfect for complex types
import json # For parsing JSON response from GCF

# Solana SDK imports
from solders.keypair import Keypair
from solders.pubkey import Pubkey
from solders.transaction import Transaction # For building transactions
from solders.instruction import Instruction # For building instructions
from solana.rpc.api import Client # For interacting with Solana RPC
from solana.rpc.types import TxOpts # For transaction options
from solana.rpc.commitment import Commitment # For commitment levels
from solana.transaction import Transaction as SolanaTransaction # Use this for building transactions

# SPL Token imports
from spl.token.client import Token as SplTokenClient
from spl.token.constants import TOKEN_PROGRAM_ID, ASSOCIATED_TOKEN_PROGRAM_ID
from spl.token.instructions import get_associated_token_address # Helper to get ATA

# Borsh for serialization/deserialization (install with `pip install borsh`)
from borsh_construct import CStruct, U8, U64, Bool, String, Option, Vec, PublicKey, Enum

# --- Environment Variables (for Google Cloud Functions) ---
# IMPORTANT: For production, store WALLET_PRIVATE_KEY in Google Cloud Secret Manager
# and retrieve it securely within the function. Avoid direct environment variables for secrets.
PRIVATE_KEY = os.environ.get('WALLET_PRIVATE_KEY') # Private key for the external authority
SMART_WALLET_PROGRAM_ID_STR = os.environ.get('SMART_WALLET_PROGRAM_ID')
SMART_WALLET_ADDRESS_STR = os.environ.get('SMART_WALLET_ADDRESS') # PDA address of the smart wallet
# RAYDIUM_SWAP_PROGRAM_ID is not strictly needed as we are simulating Raydium for now
# but kept for future expansion if needed.
RAYDIUM_SWAP_PROGRAM_ID_STR = os.environ.get('RAYDIUM_SWAP_PROGRAM_ID', '675kPXNm7eGx6rD2kjsWJpXz4K9E6hNnUvR5rT') # Raydium AMM V4 Program ID
RPC_ENDPOINT = os.environ.get('SOLANA_RPC_ENDPOINT', 'https://api.mainnet-beta.solana.com')
EMAIL_SERVICE_HOST = os.environ.get('EMAIL_SERVICE_HOST', 'smtp.gmail.com')
EMAIL_SERVICE_PORT = int(os.environ.get('EMAIL_SERVICE_PORT', 587))
EMAIL_USER = os.environ.get('EMAIL_USER')
EMAIL_PASS = os.environ.get('EMAIL_PASS') # Use app-specific password for Gmail
EMAIL_FROM = os.environ.get('EMAIL_FROM', 'crypto-wallet@example.com')

# --- Solana Program ID Public Keys ---
SMART_WALLET_PROGRAM_ID = Pubkey.from_string(SMART_WALLET_PROGRAM_ID_STR)
SMART_WALLET_ADDRESS = Pubkey.from_string(SMART_WALLET_ADDRESS_STR)
RAYDIUM_SWAP_PROGRAM_ID = Pubkey.from_string(RAYDIUM_SWAP_PROGRAM_ID_STR)
USDC_MINT_PUBKEY = Pubkey.from_string('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v') # Mainnet USDC Mint

# --- Define SmartWallet State Structure (Python equivalent of Rust struct) ---
# This structure must exactly match the byte layout of the Rust `SmartWallet` struct
# when serialized with Borsh.
SmartWalletLayout = CStruct(
    "is_initialized" / Bool,
    "owner" / PublicKey,
    "authority_bump_seed" / U8,
    "authority_pubkey" / PublicKey,
    "is_active" / Bool,
    "external_authority" / Option(PublicKey),
    "usdc_token_mint" / PublicKey,
    "increment_amount" / U64,
    "max_tokens_per_run" / U8,
    "email_notifications" / Bool,
    "user_email" / String, # Borsh String is u32 length prefix + bytes
    "low_balance_notified" / Bool,
)

# --- Define SmartWallet Instruction Structure (Python equivalent of Rust enum) ---
# This structure must exactly match the byte layout of the Rust `SmartWalletInstruction` enum
# when serialized with Borsh.
SmartWalletInstructionLayout = Enum(
    "Initialize" / CStruct(
        "increment_amount" / U64,
        "max_tokens_per_run" / U8,
        "email" / String,
        "enable_notifications" / Bool,
    ),
    "DepositUSDC" / CStruct(
        "amount" / U64,
    ),
    "WithdrawUSDC" / CStruct(
        "amount" / U64,
    ),
    "UpdateSettings" / CStruct(
        "increment_amount" / Option(U64),
        "max_tokens_per_run" / Option(U8),
        "email" / Option(String),
        "enable_notifications" / Option(Bool),
    ),
    "AuthorizeExternal" / CStruct(), # No data for this instruction, just accounts
    "PurchaseTokens" / CStruct(
        "token_mints" / Vec(PublicKey), # Vec<Pubkey>
    ),
    "ResetLowBalanceFlag" / CStruct(), # No data for this instruction, just accounts
)

"""
Google Cloud Function that runs every hour to purchase trending tokens with USDC
"""
def automatic_token_purchase(request):
    try:
        print('Starting automatic token purchase...')

        # Initialize Solana connection
        connection = Client(RPC_ENDPOINT)

        # Initialize wallet from private key
        wallet_keypair = load_wallet_from_private_key(PRIVATE_KEY)
        print(f"External Authority Public Key: {wallet_keypair.pubkey()}")

        # Get wallet data from the smart wallet account (ACTUAL ON-CHAIN READ)
        wallet_data = get_wallet_data(connection, SMART_WALLET_ADDRESS)
        if not wallet_data:
            print(f"Smart wallet account {SMART_WALLET_ADDRESS} not found or uninitialized.")
            return {
                'success': False,
                'timestamp': f"{requests.utils.datetime.now().isoformat()}Z",
                'message': f"Smart wallet account {SMART_WALLET_ADDRESS} not found or uninitialized. Cannot proceed.",
            }, 500

        print('Wallet settings:', {
            'owner': str(wallet_data['owner']),
            'authority_pubkey': str(wallet_data['authority_pubkey']),
            'incrementAmount': wallet_data['increment_amount'] / 1_000_000, # Convert to USDC
            'maxTokensPerRun': wallet_data['max_tokens_per_run'],
            'emailNotifications': wallet_data['email_notifications'],
            'userEmail': wallet_data['user_email'],
            'lowBalanceNotified': wallet_data['low_balance_notified'],
            'usdcTokenMint': str(wallet_data['usdc_token_mint']),
        })

        # Get wallet USDC balance (ACTUAL ON-CHAIN READ)
        wallet_usdc_ata = get_associated_token_address(wallet_data['authority_pubkey'], wallet_data['usdc_token_mint'])
        usdc_balance = get_usdc_balance(connection, wallet_usdc_ata)
        print(f"Current USDC balance: {usdc_balance / 1_000_000} USDC (ATA: {wallet_usdc_ata})")

        # Check if balance is sufficient for at least one purchase
        low_balance = usdc_balance < wallet_data['increment_amount']

        if low_balance:
            print('Insufficient USDC balance for purchases.')

            # Send low balance notification if notifications are enabled and not already sent
            if wallet_data['email_notifications'] and not wallet_data['low_balance_notified']:
                send_low_balance_email(
                    wallet_data['user_email'],
                    usdc_balance / 1_000_000,
                    wallet_data['increment_amount'] / 1_000_000
                )

                # Update the low balance notification flag on-chain
                print("Sending transaction to update low balance flag...")
                tx_id = update_low_balance_flag(connection, wallet_keypair, SMART_WALLET_ADDRESS, True)
                print(f"Update low balance flag TX ID: {tx_id}")
            else:
                print("Email notifications disabled or already sent.")

            return {
                'success': False,
                'timestamp': f"{requests.utils.datetime.now().isoformat()}Z",
                'message': 'Insufficient USDC balance for purchases',
                'currentBalance': usdc_balance / 1_000_000,
                'requiredBalance': wallet_data['increment_amount'] / 1_000_000,
            }, 200

        # --- User specified: No need to check Raydium for trending tokens ---
        # Assume a predefined list of tokens to buy.
        # In a real scenario, this list might come from a database, another API,
        # or be part of the smart wallet's configuration.
        # For demonstration, let's use a dummy list of token mints.
        # These should be actual SPL Token mints on Solana.
        tokens_to_consider = [
            Pubkey.from_string("HZ1EMoR4R7z61r3W12bB273k9f49N6gP91h5X92k82"), # Dummy token 1
            Pubkey.from_string("JUPyiwrYJFskTgLCzQopdz4cZC6y7LqheB5JetgBMfS"), # JUP (real token)
            Pubkey.from_string("DezX8cCDKsBOVdPz2NoRBSVAj2D6FzZWxcrFxgeZPekE"), # Dummy token 2
            Pubkey.from_string("So11111111111111111111111111111111111111112"), # Wrapped SOL (real token)
        ]
        print(f"Using predefined list of {len(tokens_to_consider)} tokens to consider.")

        # Determine how many tokens we can buy with our available balance
        num_tokens_to_buy = min(
            usdc_balance // wallet_data['increment_amount'],
            min(len(tokens_to_consider), wallet_data['max_tokens_per_run'])
        )

        if num_tokens_to_buy == 0:
            print("No tokens to purchase based on current balance or max_tokens_per_run.")
            return {
                'success': True,
                'timestamp': f"{requests.utils.datetime.now().isoformat()}Z",
                'message': 'No tokens to purchase.',
                'initialBalance': usdc_balance / 1_000_000,
                'remainingBalance': usdc_balance / 1_000_000,
                'purchases': 0,
            }, 200

        print(f"Will purchase {num_tokens_to_buy} tokens with {wallet_data['increment_amount'] / 1_000_000} USDC each")

        # Only use the tokens we're going to buy
        selected_tokens_mints = tokens_to_consider[:num_tokens_to_buy]

        # Execute the purchase transaction (ACTUAL ON-CHAIN CALL)
        print("Sending purchase tokens transaction...")
        tx_id = execute_purchases(
            connection,
            wallet_keypair,
            SMART_WALLET_ADDRESS,
            wallet_data['authority_pubkey'],
            wallet_usdc_ata,
            selected_tokens_mints,
            wallet_data['increment_amount']
        )
        print(f"Purchase Tokens TX ID: {tx_id}")

        # Re-fetch balance after purchase to get the actual remaining balance
        # (assuming the Rust program actually performs the deduction via Raydium CPI)
        updated_usdc_balance = get_usdc_balance(connection, wallet_usdc_ata)
        print(f"Updated USDC balance after purchases: {updated_usdc_balance / 1_000_000} USDC")

        # Check if remaining balance is below the increment amount AFTER the purchase
        will_become_low_balance = updated_usdc_balance < wallet_data['increment_amount']

        if will_become_low_balance:
            print('Remaining balance is below the increment amount after purchases.')

            # Send low balance notification if notifications are enabled and not already sent
            # (Re-check low_balance_notified from fresh wallet_data if needed, or assume current state)
            # For simplicity, we'll send if it becomes low and wasn't already notified by the previous check.
            if wallet_data['email_notifications'] and not wallet_data['low_balance_notified']:
                send_low_balance_email(
                    wallet_data['user_email'],
                    updated_usdc_balance / 1_000_000,
                    wallet_data['increment_amount'] / 1_000_000
                )
                print("Sending transaction to update low balance flag after purchase...")
                tx_id_flag = update_low_balance_flag(connection, wallet_keypair, SMART_WALLET_ADDRESS, True)
                print(f"Update low balance flag TX ID (post-purchase): {tx_id_flag}")
            elif wallet_data['email_notifications'] and wallet_data['low_balance_notified']:
                print("Low balance notification already sent for this state.")
            else:
                print("Email notifications disabled.")

        # Return results
        return {
            'success': True,
            'timestamp': f"{requests.utils.datetime.now().isoformat()}Z",
            'purchases': num_tokens_to_buy,
            'purchaseIncrement': wallet_data['increment_amount'] / 1_000_000,
            'initialBalance': usdc_balance / 1_000_000,
            'remainingBalance': updated_usdc_balance / 1_000_000,
            'txId': tx_id,
            'tokensPurchased': [str(t) for t in selected_tokens_mints]
        }, 200

    except Exception as e:
        print(f"Error in automatic token purchase: {e}", flush=True)
        return {
            'success': False,
            'error': str(e)
        }, 500

"""
Load wallet from private key string (base58 encoded)
"""
def load_wallet_from_private_key(private_key_string: str) -> Keypair:
    decoded_key = base58.b58decode(private_key_string)
    # Keypair.from_bytes expects a 64-byte secret key (32-byte private key + 32-byte public key)
    # or a 32-byte private key.
    # Assuming `PRIVATE_KEY` is the full 64-byte secret key.
    return Keypair.from_bytes(decoded_key)

"""
Get wallet data from the smart wallet account (reads actual on-chain data)
"""
def get_wallet_data(connection: Client, wallet_address: Pubkey) -> dict:
    print(f"Fetching wallet data for {wallet_address}...")
    account_info = connection.get_account_info(wallet_address, commitment=Commitment("confirmed"))

    if not account_info or not account_info.value:
        print(f"Account {wallet_address} not found or has no data.")
        return None

    # Deserialize the account data using the defined Borsh layout
    try:
        wallet_data = SmartWalletLayout.parse(account_info.value.data)
        print("Wallet data deserialized successfully.")
        return wallet_data
    except Exception as e:
        print(f"Failed to deserialize wallet data: {e}")
        return None

"""
Get USDC balance for the wallet's associated token account (reads actual on-chain data)
"""
def get_usdc_balance(connection: Client, wallet_usdc_ata: Pubkey) -> int:
    try:
        print(f"Fetching USDC balance for ATA {wallet_usdc_ata}...")
        token_account_balance = connection.get_token_account_balance(wallet_usdc_ata, commitment=Commitment("confirmed"))

        if token_account_balance and token_account_balance.value:
            amount = int(token_account_balance.value.amount)
            print(f"Found balance: {amount}")
            return amount
        else:
            print(f"No token account balance found for {wallet_usdc_ata}.")
            return 0
    except Exception as e:
        print(f"Error getting USDC balance for {wallet_usdc_ata}: {e}")
        return 0

"""
Execute token purchases using the smart wallet contract
Constructs and sends a real Solana transaction.
"""
def execute_purchases(
    connection: Client,
    signer_keypair: Keypair, # External authority keypair
    smart_wallet_address: Pubkey, # PDA of the smart wallet
    wallet_authority_pubkey: Pubkey, # The PDA Pubkey itself
    wallet_usdc_ata: Pubkey, # Wallet's USDC Associated Token Account
    token_mints: list[Pubkey],
    increment_amount: int
) -> str:
    print(f"Building PurchaseTokens transaction for {len(token_mints)} tokens...")

    # 1. Construct the instruction data for SmartWalletInstruction::PurchaseTokens
    instruction_data = SmartWalletInstructionLayout.PurchaseTokens.build({
        "token_mints": token_mints
    })

    # 2. Identify all necessary accounts for the PurchaseTokens instruction on the smart contract side:
    # These must match the order and type expected by the Rust program's `purchase_tokens` function.
    # Order: authority, wallet_account, wallet_usdc_account, token_program, ...dummy_raydium_accounts...
    keys = [
        # 0. `[signer]` Authority (owner or external authority)
        {"pubkey": signer_keypair.pubkey(), "is_signer": True, "is_writable": False},
        # 1. `[writable]` Wallet account (PDA, owned by program)
        {"pubkey": smart_wallet_address, "is_signer": False, "is_writable": True},
        # 2. `[writable]` Wallet USDC account (ATA of wallet PDA)
        {"pubkey": wallet_usdc_ata, "is_signer": False, "is_writable": True},
        # 3. `[]` Token program (spl-token program ID)
        {"pubkey": TOKEN_PROGRAM_ID, "is_signer": False, "is_writable": False},
    ]

    # --- Dummy Accounts for Raydium Simulation ---
    # These accounts are consumed by `next_account_info` in the Rust program,
    # even if the actual Raydium swap logic is simulated.
    # Their specific values don't matter for the simulation, but their presence does.
    # In a real Raydium integration, these would be actual Raydium AMM, market, and vault accounts.
    dummy_pubkey = Pubkey.new_unique() # Generate unique dummy pubkeys
    dummy_keys = [
        {"pubkey": RAYDIUM_SWAP_PROGRAM_ID, "is_signer": False, "is_writable": False}, # _dummy_raydium_program
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_pool_account
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_open_orders
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_target_orders
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_withdraw_queue
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_lp_mint
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": False}, # _dummy_amm_authority
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_coin_vault
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_pc_vault
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": False}, # _dummy_market_program
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_market_account
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_market_bids
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_market_asks
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_market_event_queue
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_market_base_vault
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": True}, # _dummy_market_quote_vault
        {"pubkey": dummy_pubkey, "is_signer": False, "is_writable": False}, # _dummy_serum_authority
    ]
    keys.extend(dummy_keys)

    # Create the instruction
    instruction = Instruction(
        program_id=SMART_WALLET_PROGRAM_ID,
        data=instruction_data,
        keys=keys,
    )

    # 3. Build Transaction
    transaction = SolanaTransaction().add(instruction)

    # 4. Sign and Send
    try:
        # Fetch recent blockhash
        recent_blockhash = connection.get_latest_blockhash(commitment=Commitment("confirmed")).value.blockhash
        transaction.recent_blockhash = recent_blockhash
        transaction.sign(signer_keypair)

        # Send and confirm transaction
        opts = TxOpts(skip_preflight=False, preflight_commitment=Commitment("confirmed"))
        tx_result = connection.send_and_confirm_transaction(transaction, signer_keypair, opts=opts)

        print(f"Transaction sent. Signature: {tx_result.value}")
        return str(tx_result.value) # Return transaction signature
    except Exception as e:
        print(f"Error sending transaction: {e}")
        raise

"""
Update the low balance notification flag on the smart wallet.
Sends an UpdateSettings instruction to the smart contract.
"""
def update_low_balance_flag(
    connection: Client,
    signer_keypair: Keypair, # External authority keypair
    smart_wallet_address: Pubkey, # PDA of the smart wallet
    is_notified: bool
) -> str:
    print(f"Building UpdateSettings transaction to set low_balance_notified to {is_notified}...")

    # 1. Construct the instruction data for SmartWalletInstruction::UpdateSettings
    instruction_data = SmartWalletInstructionLayout.UpdateSettings.build({
        "increment_amount": None,
        "max_tokens_per_run": None,
        "email": None,
        "enable_notifications": None,
        "low_balance_notified": is_notified, # This field is not directly in UpdateSettings in Rust
                                             # We need to send ResetLowBalanceFlag instruction instead
    })
    # Corrected: Use ResetLowBalanceFlag instruction
    instruction_data = SmartWalletInstructionLayout.ResetLowBalanceFlag.build({})


    # 2. Identify accounts for the instruction
    keys = [
        # 0. `[signer]` Authority (owner or external authority)
        {"pubkey": signer_keypair.pubkey(), "is_signer": True, "is_writable": False},
        # 1. `[writable]` Wallet account (PDA, owned by program)
        {"pubkey": smart_wallet_address, "is_signer": False, "is_writable": True},
    ]

    # Create the instruction
    instruction = Instruction(
        program_id=SMART_WALLET_PROGRAM_ID,
        data=instruction_data,
        keys=keys,
    )

    # 3. Build Transaction
    transaction = SolanaTransaction().add(instruction)

    # 4. Sign and Send
    try:
        recent_blockhash = connection.get_latest_blockhash(commitment=Commitment("confirmed")).value.blockhash
        transaction.recent_blockhash = recent_blockhash
        transaction.sign(signer_keypair)

        opts = TxOpts(skip_preflight=False, preflight_commitment=Commitment("confirmed"))
        tx_result = connection.send_and_confirm_transaction(transaction, signer_keypair, opts=opts)

        print(f"Transaction sent. Signature: {tx_result.value}")
        return str(tx_result.value)
    except Exception as e:
        print(f"Error sending transaction to update low balance flag: {e}")
        raise

"""
Send low balance email notification
"""
def send_low_balance_email(recipient_email: str, current_balance: float, required_balance: float):
    try:
        msg = MIMEText(
            f"Your Solana smart wallet balance is low.\n"
            f"Current balance: {current_balance:.2f} USDC\n"
            f"Required for purchases: {required_balance:.2f} USDC\n"
            f"Please deposit more USDC to continue automated purchases."
        )
        msg['Subject'] = 'Solana Smart Wallet Low Balance Alert'
        msg['From'] = EMAIL_FROM
        msg['To'] = recipient_email

        print(f"Attempting to send email to {recipient_email} via {EMAIL_SERVICE_HOST}:{EMAIL_SERVICE_PORT}...")
        with smtplib.SMTP(EMAIL_SERVICE_HOST, EMAIL_SERVICE_PORT) as server:
            server.starttls() # Enable TLS
            server.login(EMAIL_USER, EMAIL_PASS)
            server.send_message(msg)
        print(f"Low balance email sent to {recipient_email}")
    except Exception as e:
        print(f"Failed to send email: {e}")
        # In a real Cloud Function, consider using a dedicated email service API
        # like SendGrid or Mailgun for better reliability and error reporting.


# Example of how you would expose this for Google Cloud Functions
# For HTTP-triggered functions, the main entry point needs to accept `request`
# For Pub/Sub triggered functions, it would be `(event, context)`
# To run this locally for testing:
# if __name__ == '__main__':
#     # Set dummy environment variables for local testing
#     # REPLACE THESE WITH ACTUAL VALUES FOR TESTING
#     os.environ['WALLET_PRIVATE_KEY'] = 'YOUR_64_BYTE_BASE58_ENCODED_PRIVATE_KEY_HERE'
#     os.environ['SMART_WALLET_PROGRAM_ID'] = 'YourSmartWalletProgramIdHere'
#     os.environ['SMART_WALLET_ADDRESS'] = 'YourSmartWalletPDAAddressHere'
#     os.environ['SOLANA_RPC_ENDPOINT'] = 'https://api.devnet.solana.com' # Or 'https://api.mainnet-beta.solana.com'
#     os.environ['EMAIL_USER'] = 'your_email@gmail.com'
#     os.environ['EMAIL_PASS'] = 'your_app_password_for_gmail' # IMPORTANT: Use an app password for Gmail
#     os.environ['EMAIL_FROM'] = 'your_email@gmail.com'
#
#     # Simulate a request object
#     class MockRequest:
#         def __init__(self):
#             self.args = {}
#             self.json = {}
#     mock_req = MockRequest()
#     response, status_code = automatic_token_purchase(mock_req)
#     print("\n--- Simulated Cloud Function Response ---")
#     print(f"Status Code: {status_code}")
#     print(f"Response: {json.dumps(response, indent=2)}")

