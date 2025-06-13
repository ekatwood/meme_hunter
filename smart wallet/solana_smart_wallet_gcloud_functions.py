# pip install firebase-admin

import os
import requests
import base58
import smtplib
from email.mime.text import MIMEText
import struct
import json
import base64
from typing import List, Dict, Any, Optional

# Firebase Admin SDK
import firebase_admin
from firebase_admin import credentials, firestore

# Solana SDK imports
from solders.keypair import Keypair
from solders.pubkey import Pubkey
from solders.transaction import Transaction as SolanaTransaction
from solders.instruction import Instruction as SolanaInstruction
from solana.rpc.api import Client
from solana.rpc.types import TxOpts
from solana.rpc.commitment import Commitment
from spl.token.constants import TOKEN_PROGRAM_ID, ASSOCIATED_TOKEN_PROGRAM_ID
from spl.token.instructions import get_associated_token_address

# Borsh for serialization/deserialization
from borsh_construct import CStruct, U8, U64, Bool, String, Option, Vec, PublicKey, Enum

# --- Firestore Initialization (MANDATORY GLOBALS) ---
# Check if __app_id is defined (it will be in Canvas environment)
app_id = os.environ.get('__app_id', 'default-app-id') # Use a default for local testing
firebase_config_str = os.environ.get('__firebase_config', '{}')
firebase_config = json.loads(firebase_config_str)

# Initialize Firebase Admin SDK
if not firebase_admin._apps: # Ensure it's initialized only once
    try:
        # Use Application Default Credentials in GCF environment
        cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred, {'projectId': firebase_config.get('projectId')})
    except ValueError:
        # Fallback for local testing outside GCF (e.g., using a service account key file)
        # IMPORTANT: Replace with your service account key path for local dev/testing if not in GCF
        # For GCF, ApplicationDefault() is sufficient.
        print("Falling back to local Firebase credentials for testing. DO NOT USE IN PRODUCTION GCF WITHOUT ADC.")
        if os.path.exists('path/to/your/serviceAccountKey.json'):
            cred = credentials.Certificate('path/to/your/serviceAccountKey.json')
            firebase_admin.initialize_app(cred)
        else:
            print("No service account key found for local testing. Firebase features will be limited.")

db = firestore.client()

# --- Environment Variables ---
PRIVATE_KEY = os.environ.get('WALLET_PRIVATE_KEY') # Private key for the external authority
SMART_WALLET_PROGRAM_ID_STR = os.environ.get('SMART_WALLET_PROGRAM_ID')
RPC_ENDPOINT = os.environ.get('SOLANA_RPC_ENDPOINT', 'https://api.mainnet-beta.solana.com')
EMAIL_SERVICE_HOST = os.environ.get('EMAIL_SERVICE_HOST', 'smtp.gmail.com')
EMAIL_SERVICE_PORT = int(os.environ.get('EMAIL_SERVICE_PORT', 587))
EMAIL_USER = os.environ.get('EMAIL_USER')
EMAIL_PASS = os.environ.get('EMAIL_PASS')
EMAIL_FROM = os.environ.get('EMAIL_FROM', 'crypto-wallet@example.com')
JUPITER_V6_SWAP_API_BASE = os.environ.get('JUPITER_V6_SWAP_API_BASE', 'https://quote-api.jup.ag/v6')

# --- Solana Program ID Public Keys ---
SMART_WALLET_PROGRAM_ID = Pubkey.from_string(SMART_WALLET_PROGRAM_ID_STR)
USDC_MINT_PUBKEY = Pubkey.from_string('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v') # Mainnet USDC Mint

# --- Define SmartWallet State Structure (Python equivalent of Rust struct) ---
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
    "user_email" / String,
    "low_balance_notified" / Bool,
)

# --- Define SmartWallet Instruction Structure (Python equivalent of Rust enum) ---
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
    "AuthorizeExternal" / CStruct(),
    "PurchaseTokens" / CStruct( # Note: token_mints is passed, Jupiter instruction data is a separate field
        "token_mints" / Vec(PublicKey),
        "jupiter_swap_ix_data" / Vec(U8), # Raw bytes of Jupiter swap instruction
    ),
    "ResetLowBalanceFlag" / CStruct(),
    "CancelSmartWallet" / CStruct(),
)

# --- Firestore Collection Reference ---
def get_user_wallets_ref():
    return db.collection(f'artifacts/{app_id}/users/user_wallets_map')

def get_public_wallets_ref():
    return db.collection(f'artifacts/{app_id}/public/smart_wallets')


# --- Helper Functions (reused from previous iteration) ---
def load_wallet_from_private_key(private_key_string: str) -> Keypair:
    decoded_key = base58.b58decode(private_key_string)
    return Keypair.from_bytes(decoded_key)

def get_wallet_data(connection: Client, wallet_address: Pubkey) -> Optional[Dict[str, Any]]:
    try:
        account_info = connection.get_account_info(wallet_address, commitment=Commitment("confirmed"))
        if not account_info or not account_info.value:
            print(f"Account {wallet_address} not found or has no data.")
            return None
        wallet_data = SmartWalletLayout.parse(account_info.value.data)
        return wallet_data
    except Exception as e:
        print(f"Failed to deserialize wallet data for {wallet_address}: {e}")
        return None

def get_usdc_balance(connection: Client, wallet_usdc_ata: Pubkey) -> int:
    try:
        token_account_balance = connection.get_token_account_balance(wallet_usdc_ata, commitment=Commitment("confirmed"))
        if token_account_balance and token_account_balance.value:
            return int(token_account_balance.value.amount)
        return 0
    except Exception as e:
        print(f"Error getting USDC balance for {wallet_usdc_ata}: {e}")
        return 0

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

        with smtplib.SMTP(EMAIL_SERVICE_HOST, EMAIL_SERVICE_PORT) as server:
            server.starttls()
            server.login(EMAIL_USER, EMAIL_PASS)
            server.send_message(msg)
        print(f"Low balance email sent to {recipient_email}")
    except Exception as e:
        print(f"Failed to send email: {e}")

def update_low_balance_flag(
    connection: Client,
    signer_keypair: Keypair,
    smart_wallet_address: Pubkey,
) -> str:
    print(f"Building ResetLowBalanceFlag transaction for {smart_wallet_address}...")
    instruction_data = SmartWalletInstructionLayout.ResetLowBalanceFlag.build({})
    keys = [
        {"pubkey": signer_keypair.pubkey(), "is_signer": True, "is_writable": False},
        {"pubkey": smart_wallet_address, "is_signer": False, "is_writable": True},
    ]
    instruction = SolanaInstruction(
        program_id=SMART_WALLET_PROGRAM_ID,
        data=instruction_data,
        keys=keys,
    )
    transaction = SolanaTransaction().add(instruction)
    try:
        recent_blockhash = connection.get_latest_blockhash(commitment=Commitment("confirmed")).value.blockhash
        transaction.recent_blockhash = recent_blockhash
        transaction.sign(signer_keypair)
        opts = TxOpts(skip_preflight=False, preflight_commitment=Commitment("confirmed"))
        tx_result = connection.send_and_confirm_transaction(transaction, signer_keypair, opts=opts)
        print(f"ResetLowBalanceFlag TX ID: {tx_result.value}")
        return str(tx_result.value)
    except Exception as e:
        print(f"Error sending ResetLowBalanceFlag transaction: {e}")
        raise

# --- New/Modified Jupiter & Batching Logic ---

async def execute_purchase_for_wallet(
    connection: Client,
    signer_keypair: Keypair, # External authority keypair
    smart_wallet_address: Pubkey,
    wallet_data: Dict[str, Any], # Deserialized SmartWallet data
    wallet_usdc_ata: Pubkey,
    tokens_to_consider: List[Pubkey], # Predefined list
) -> Optional[str]: # Returns TX ID if successful
    print(f"Processing purchase for wallet: {smart_wallet_address}")

    # 1. Check current USDC balance again (in case it changed since initial fetch)
    current_usdc_balance = get_usdc_balance(connection, wallet_usdc_ata)
    if current_usdc_balance < wallet_data['increment_amount']:
        print(f"Wallet {smart_wallet_address} insufficient USDC balance ({current_usdc_balance}) for increment ({wallet_data['increment_amount']}). Skipping purchase.")
        if wallet_data['email_notifications'] and not wallet_data['low_balance_notified']:
            send_low_balance_email(
                wallet_data['user_email'],
                current_usdc_balance / 1_000_000,
                wallet_data['increment_amount'] / 1_000_000
            )
            update_low_balance_flag(connection, signer_keypair, smart_wallet_address)
        return None

    num_tokens_to_buy = min(
        current_usdc_balance // wallet_data['increment_amount'],
        min(len(tokens_to_consider), wallet_data['max_tokens_per_run'])
    )

    if num_tokens_to_buy == 0:
        print(f"Wallet {smart_wallet_address} - No tokens to purchase based on balance/max_tokens_per_run.")
        return None

    # For simplicity, we'll process only ONE swap per trigger for now
    # In a real batch, you could do more, but transaction size for Jupiter CPIs can get big.
    selected_token_mint = tokens_to_consider[0] # Pick the first available trending token

    print(f"Fetching Jupiter quote for {wallet_data['increment_amount']} USDC to {selected_token_mint}...")
    quote_url = f"{JUPITER_V6_SWAP_API_BASE}/quote?inputMint={USDC_MINT_PUBKEY}&outputMint={selected_token_mint}&amount={wallet_data['increment_amount']}&slippageBps=50" # 0.5% slippage

    quote_response = requests.get(quote_url).json()

    if not quote_response or not quote_response.get('swapInstruction'):
        print(f"Failed to get Jupiter quote for {selected_token_mint} for wallet {smart_wallet_address}. Skipping.")
        return None

    print(f"Getting Jupiter swap instructions for wallet: {smart_wallet_address}")
    swap_url = f"{JUPITER_V6_SWAP_API_BASE}/swap"
    swap_payload = {
        "quoteResponse": quote_response,
        "userPublicKey": str(wallet_data['authority_pubkey']), # The smart wallet PDA is the user for Jupiter
        "wrapUnwrapSol": False, # We assume no SOL <-> wSOL swaps
        "prioritizationFeeLamports": "auto", # Jupiter handles priority fees
    }
    swap_response = requests.post(swap_url, json=swap_payload).json()

    if not swap_response or not swap_response.get('swapInstruction'):
        print(f"Failed to get Jupiter swap instructions for wallet {smart_wallet_address}. Skipping.")
        return None

    jupiter_swap_ix_data_base64 = swap_response['swapInstruction']['data']
    jupiter_swap_accounts_meta = swap_response['swapInstruction']['accounts']
    jupiter_program_id_str = swap_response['swapInstruction']['programId']

    jupiter_swap_ix_data = base64.b64decode(jupiter_swap_ix_data_base64)

    # Convert Jupiter's accounts_meta to AccountMeta dicts for SolanaInstruction
    jupiter_accounts_for_cpi = []
    for acc in jupiter_swap_accounts_meta:
        jupiter_accounts_for_cpi.append({
            "pubkey": Pubkey.from_string(acc['pubkey']),
            "is_signer": acc['isSigner'],
            "is_writable": acc['isWritable'],
        })

    # Construct YOUR program's PurchaseTokens instruction for this specific wallet
    program_instruction_data = SmartWalletInstructionLayout.PurchaseTokens.build({
        "token_mints": [selected_token_mint], # Pass the single token mint
        "jupiter_swap_ix_data": list(jupiter_swap_ix_data), # Raw bytes
    })

    # Accounts for YOUR program's PurchaseTokens instruction (order must match Rust)
    # 0. Authority (GCF keypair)
    # 1. Wallet account (PDA)
    # 2. Wallet USDC ATA
    # 3. SPL Token Program
    # 4. System Program
    # 5. Rent Sysvar
    # 6. Sysvar:Instructions
    # 7+. ALL accounts required by Jupiter's swap instruction
    keys = [
        {"pubkey": signer_keypair.pubkey(), "is_signer": True, "is_writable": False}, # GCF is signer
        {"pubkey": smart_wallet_address, "is_signer": False, "is_writable": True},
        {"pubkey": wallet_usdc_ata, "is_signer": False, "is_writable": True},
        {"pubkey": TOKEN_PROGRAM_ID, "is_signer": False, "is_writable": False},
        {"pubkey": Pubkey.from_string("11111111111111111111111111111111"), "is_signer": False, "is_writable": False}, # System Program
        {"pubkey": Pubkey.from_string("SysvarRent111111111111111111111111111111111"), "is_signer": False, "is_writable": False}, # Rent Sysvar
        {"pubkey": Pubkey.from_string("Sysvar1nstructions1111111111111111111111111"), "is_signer": False, "is_writable": False}, # Sysvar:Instructions
    ]

    # Append Jupiter's accounts. Ensure Jupiter's Program ID is the first of these dynamic accounts.
    # Jupiter's API already provides its program ID in `swapInstruction.programId`.
    # Add it as the first item, then extend with other accounts.
    keys.append({"pubkey": Pubkey.from_string(jupiter_program_id_str), "is_signer": False, "is_writable": False})
    keys.extend(jupiter_accounts_for_cpi)

    # Filter out duplicate keys and ensure proper order
    # (Accounts list should contain unique keys, and program_id should be first)
    unique_keys_map = {str(k['pubkey']): k for k in keys}
    final_keys = list(unique_keys_map.values()) # Convert back to list

    # Reorder final_keys to ensure wallet_data['authority_pubkey'] is the first signer after payer
    # (Important for `invoke_signed` in Rust if PDA is signer for Jupiter CPI)
    # The Rust program receives the PDA in `wallet_account` and uses its key to sign.
    # So, the Jupiter instruction itself needs the PDA listed correctly.
    # Jupiter's API often adds the `userPublicKey` (our PDA) as a signer already.

    instruction = SolanaInstruction(
        program_id=SMART_WALLET_PROGRAM_ID,
        data=program_instruction_data,
        keys=final_keys, # Use the combined list of keys
    )

    transaction = SolanaTransaction().add(instruction)

    try:
        recent_blockhash = connection.get_latest_blockhash(commitment=Commitment("confirmed")).value.blockhash
        transaction.recent_blockhash = recent_blockhash
        transaction.sign(signer_keypair) # GCF's external authority signs
        opts = TxOpts(skip_preflight=False, preflight_commitment=Commitment("confirmed"))
        tx_result = connection.send_and_confirm_transaction(transaction, signer_keypair, opts=opts)
        print(f"PurchaseTokens TX ID for wallet {smart_wallet_address}: {tx_result.value}")
        return str(tx_result.value)
    except Exception as e:
        print(f"Error executing PurchaseTokens for wallet {smart_wallet_address}: {e}")
        return None

# --- Cloud Function: trigger_smart_wallet_processing (HTTP Trigger for Flutter) ---
def trigger_smart_wallet_processing(request):
    """
    HTTP Cloud Function to trigger a single smart wallet's purchase logic.
    Called by the Flutter frontend.
    """
    if request.method == 'OPTIONS':
        # Respond to CORS preflight request
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)

    headers = {
        'Access-Control-Allow-Origin': '*'
    }

    request_json = request.get_json(silent=True)
    if not request_json:
        return ({'status': 'error', 'message': 'Invalid JSON'}, 400, headers)

    user_wallet_address = request_json.get('userWalletAddress')
    if not user_wallet_address:
        return ({'status': 'error', 'message': 'userWalletAddress is required'}, 400, headers)

    try:
        # Retrieve smart wallet address from Firestore
        doc_ref = get_user_wallets_ref().document(user_wallet_address)
        doc = doc_ref.get()
        if not doc.exists:
            return ({'status': 'error', 'message': 'No smart wallet registered for this user.'}, 404, headers)

        smart_wallet_address_str = doc.to_dict().get('smartWalletAddress')
        if not smart_wallet_address_str:
            return ({'status': 'error', 'message': 'Smart wallet address not found in mapping.'}, 404, headers)

        smart_wallet_address = Pubkey.from_string(smart_wallet_address_str)

        connection = Client(RPC_ENDPOINT)
        signer_keypair = load_wallet_from_private_key(PRIVATE_KEY)

        wallet_data = get_wallet_data(connection, smart_wallet_address)
        if not wallet_data:
            return ({'status': 'error', 'message': f'Smart wallet account {smart_wallet_address} not found on-chain.'}, 404, headers)

        wallet_usdc_ata = get_associated_token_address(wallet_data['authority_pubkey'], wallet_data['usdc_token_mint'])

        # Predefined list of tokens to consider (can be dynamic, from a config, or another DB)
        tokens_to_consider = [
            Pubkey.from_string("JUPyiwrYJFskTgLCzQopdz4cZC6y7LqheB5JetgBMfS"), # JUP
            Pubkey.from_string("So11111111111111111111111111111111111111112"), # wSOL
            # Add more relevant token mints here
        ]

        tx_id = execute_purchase_for_wallet(connection, signer_keypair, smart_wallet_address, wallet_data, wallet_usdc_ata, tokens_to_consider)

        if tx_id:
            return ({'status': 'success', 'message': 'Purchase initiated.', 'txId': tx_id}, 200, headers)
        else:
            return ({'status': 'failed', 'message': 'Purchase could not be initiated.'}, 500, headers)

    except Exception as e:
        print(f"Error in trigger_smart_wallet_processing: {e}")
        return ({'status': 'error', 'message': str(e)}, 500, headers)

# --- Cloud Function: hourly_smart_wallet_processing (Pub/Sub Trigger for Batching) ---
def hourly_smart_wallet_processing(event, context):
    """
    Pub/Sub Cloud Function triggered by Cloud Scheduler to process all active smart wallets in batches.
    """
    print("Starting hourly batch processing of smart wallets...")

    connection = Client(RPC_ENDPOINT)
    signer_keypair = load_wallet_from_private_key(PRIVATE_KEY)

    # Predefined list of tokens to consider for all wallets (can be dynamic, from a config, or another DB)
    # For a real application, this might come from a separate service or a daily update.
    tokens_to_consider = [
        Pubkey.from_string("JUPyiwrYJFskTgLCzQopdz4cZC6y7LqheB5JetgBMfS"), # JUP
        Pubkey.from_string("So11111111111111111111111111111111111111112"), # wSOL
        Pubkey.from_string("EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm"), # BONK (example)
        # Add more relevant token mints here
    ]

    # Get all active smart wallet entries from Firestore
    # In a very large scale, you might paginate this query.
    active_wallets_snapshot = get_public_wallets_ref().where('is_active', '==', True).stream()

    wallets_to_process = []
    for doc in active_wallets_snapshot:
        wallet_map_data = doc.to_dict()
        smart_wallet_address_str = doc.id # Document ID is the smart wallet address
        user_wallet_address = wallet_map_data.get('owner_wallet_address') # Original owner

        # Fetch on-chain data for each wallet
        smart_wallet_address = Pubkey.from_string(smart_wallet_address_str)
        wallet_data = get_wallet_data(connection, smart_wallet_address)

        if wallet_data and wallet_data['is_active']:
            wallet_usdc_ata = get_associated_token_address(wallet_data['authority_pubkey'], wallet_data['usdc_token_mint'])
            wallets_to_process.append({
                'smart_wallet_address': smart_wallet_address,
                'wallet_data': wallet_data,
                'wallet_usdc_ata': wallet_usdc_ata,
                'user_wallet_address': user_wallet_address,
            })
        else:
            print(f"Skipping inactive or uninitialized wallet: {smart_wallet_address_str}")

    print(f"Found {len(wallets_to_process)} active wallets to process.")

    # Batch processing logic
    # Solana transaction limits: ~10-15 CPIs, ~30-35 unique accounts, ~1232 bytes
    # Jupiter CPIs can be large. Let's aim for 1-2 PurchaseTokens instructions per batch transaction.
    # This might need adjustment based on real-world transaction sizes.
    BATCH_SIZE = 1 # Number of PurchaseTokens instructions per Solana transaction
    processed_count = 0

    for i in range(0, len(wallets_to_process), BATCH_SIZE):
        batch = wallets_to_process[i : i + BATCH_SIZE]

        batch_instructions: List[SolanaInstruction] = []

        for wallet_info in batch:
            smart_wallet_address = wallet_info['smart_wallet_address']
            wallet_data = wallet_info['wallet_data']
            wallet_usdc_ata = wallet_info['wallet_usdc_ata']

            print(f"Preparing batch instruction for wallet {smart_wallet_address}...")

            # This is the core logic that creates the PurchaseTokens instruction
            # It includes Jupiter API calls for quote and swap instructions.
            try:
                # 1. Get Jupiter Quote
                quote_url = f"{JUPITER_V6_SWAP_API_BASE}/quote?inputMint={USDC_MINT_PUBKEY}&outputMint={tokens_to_consider[0]}&amount={wallet_data['increment_amount']}&slippageBps=50"
                quote_response = requests.get(quote_url).json()

                if not quote_response or not quote_response.get('swapInstruction'):
                    print(f"Skipping wallet {smart_wallet_address}: Failed to get Jupiter quote for {tokens_to_consider[0]}.")
                    continue

                # 2. Get Jupiter Swap Instructions (for CPI)
                swap_url = f"{JUPITER_V6_SWAP_API_BASE}/swap"
                swap_payload = {
                    "quoteResponse": quote_response,
                    "userPublicKey": str(wallet_data['authority_pubkey']), # The smart wallet PDA is the user for Jupiter
                    "wrapUnwrapSol": False,
                    "prioritizationFeeLamports": "auto",
                }
                swap_response = requests.post(swap_url, json=swap_payload).json()

                if not swap_response or not swap_response.get('swapInstruction'):
                    print(f"Skipping wallet {smart_wallet_address}: Failed to get Jupiter swap instructions.")
                    continue

                jupiter_swap_ix_data_base64 = swap_response['swapInstruction']['data']
                jupiter_swap_accounts_meta = swap_response['swapInstruction']['accounts']
                jupiter_program_id_str = swap_response['swapInstruction']['programId']

                jupiter_swap_ix_data = base64.b64decode(jupiter_swap_ix_data_base64)

                jupiter_accounts_for_cpi_meta = []
                for acc in jupiter_swap_accounts_meta:
                    jupiter_accounts_for_cpi_meta.append({
                        "pubkey": Pubkey.from_string(acc['pubkey']),
                        "is_signer": acc['isSigner'],
                        "is_writable": acc['isWritable'],
                    })

                # Construct YOUR program's PurchaseTokens instruction for this specific wallet
                program_instruction_data = SmartWalletInstructionLayout.PurchaseTokens.build({
                    "token_mints": [tokens_to_consider[0]],
                    "jupiter_swap_ix_data": list(jupiter_swap_ix_data),
                })

                # Accounts for YOUR program's PurchaseTokens instruction (order must match Rust)
                # 0. Authority (GCF keypair) - will be signer_keypair.pubkey()
                # 1. Wallet account (PDA) - smart_wallet_address
                # 2. Wallet USDC ATA - wallet_usdc_ata
                # 3. SPL Token Program
                # 4. System Program
                # 5. Rent Sysvar
                # 6. Sysvar:Instructions
                # 7+. ALL accounts required by Jupiter's swap instruction
                keys = [
                    {"pubkey": signer_keypair.pubkey(), "is_signer": True, "is_writable": False}, # GCF is signer
                    {"pubkey": smart_wallet_address, "is_signer": False, "is_writable": True},
                    {"pubkey": wallet_usdc_ata, "is_signer": False, "is_writable": True},
                    {"pubkey": TOKEN_PROGRAM_ID, "is_signer": False, "is_writable": False},
                    {"pubkey": Pubkey.from_string("11111111111111111111111111111111"), "is_signer": False, "is_writable": False}, # System Program
                    {"pubkey": Pubkey.from_string("SysvarRent111111111111111111111111111111111"), "is_signer": False, "is_writable": False}, # Rent Sysvar
                    {"pubkey": Pubkey.from_string("Sysvar1nstructions1111111111111111111111111"), "is_signer": False, "is_writable": False}, # Sysvar:Instructions
                    {"pubkey": Pubkey.from_string(jupiter_program_id_str), "is_signer": False, "is_writable": False},
                ]
                keys.extend(jupiter_accounts_for_cpi_meta)

                # Filter out duplicate keys and ensure proper order
                unique_keys_map = {}
                for k in keys:
                    unique_keys_map[str(k['pubkey'])] = k
                final_keys = list(unique_keys_map.values())

                batch_instructions.append(SolanaInstruction(
                    program_id=SMART_WALLET_PROGRAM_ID,
                    data=program_instruction_data,
                    keys=final_keys,
                ))

            except Exception as e:
                print(f"Error preparing instruction for wallet {smart_wallet_address}: {e}. Skipping this wallet.")
                continue

        if not batch_instructions:
            print(f"No instructions prepared for current batch {i} to {i + BATCH_SIZE}. Skipping batch.")
            continue

        # Create and send the batch transaction
        batch_transaction = SolanaTransaction()
        for ix in batch_instructions:
            batch_transaction.add(ix)

        try:
            recent_blockhash = connection.get_latest_blockhash(commitment=Commitment("confirmed")).value.blockhash
            batch_transaction.recent_blockhash = recent_blockhash
            batch_transaction.sign(signer_keypair)
            opts = TxOpts(skip_preflight=False, preflight_commitment=Commitment("confirmed"))
            tx_result = connection.send_and_confirm_transaction(batch_transaction, signer_keypair, opts=opts)
            print(f"Successfully sent batch transaction. TX ID: {tx_result.value}")
            processed_count += len(batch)
        except Exception as e:
            print(f"Failed to send batch transaction for wallets {batch[0]['smart_wallet_address']}...: {e}")
            # Implement more robust error handling: log, retry, notify

    print(f"Finished hourly batch processing. Processed {processed_count} wallets.")

# --- Firestore Functions ---
def add_smart_wallet_to_firestore(user_wallet_address: str, smart_wallet_address: str, owner_pubkey: str):
    """Adds or updates a user's smart wallet mapping in Firestore."""
    user_wallets_doc_ref = get_user_wallets_ref().document(user_wallet_address)
    user_wallets_doc_ref.set({
        'smartWalletAddress': smart_wallet_address,
        'last_updated': firestore.SERVER_TIMESTAMP,
        'owner_pubkey_str': owner_pubkey # Redundant but useful for lookup
    })

    # Also add to public collection for batch processing
    public_wallets_doc_ref = get_public_wallets_ref().document(smart_wallet_address)
    public_wallets_doc_ref.set({
        'owner_wallet_address': user_wallet_address, # Original user's wallet
        'is_active': True,
        'created_at': firestore.SERVER_TIMESTAMP,
        'last_processed': None,
        # ... other metadata from smart wallet init if desired
    }, merge=True) # merge=True to update if already exists

def update_smart_wallet_firestore_status(smart_wallet_address: str, is_active: bool):
    """Updates the active status of a smart wallet in the public Firestore collection."""
    public_wallets_doc_ref = get_public_wallets_ref().document(smart_wallet_address)
    public_wallets_doc_ref.update({
        'is_active': is_active,
        'last_processed': firestore.SERVER_TIMESTAMP,
    })

def delete_smart_wallet_from_firestore(user_wallet_address: str, smart_wallet_address: str):
    """Removes a user's smart wallet mapping and its public entry from Firestore."""
    get_user_wallets_ref().document(user_wallet_address).delete()
    get_public_wallets_ref().document(smart_wallet_address).delete()