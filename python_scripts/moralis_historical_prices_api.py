import requests
import json
import datetime
import time
import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
from google.cloud import firestore as gcf_firestore

# --- Constants ---
# Two weeks in hours and minutes
TWO_WEEKS_HOURS = 336
MAX_DATA_POINTS = 20160
MORALIS_API_KEY = "x"  # Replace with your actual Moralis API Key
MORALIS_BASE_URL = "https://deep-index.moralis.io/api/v2.2"
HEADERS = {
    "accept": "application/json",
    "X-API-Key": MORALIS_API_KEY,
}
MAX_LIMIT_PER_REQUEST = 1000  # Max limit for Moralis OHLCV endpoint

# --- Firestore Initialization (GCloud-friendly) ---

def initialize_firebase():
    """Initializes the Firebase Admin SDK."""
    try:
        # For GCloud environments, use Application Default Credentials (ADC) or explicitly load a key.
        # Since the original file used a service account file, we'll keep that structure,
        # but you should adjust 'serviceAccountKey.json' path for your specific GCloud setup.
        # If running in GCE/Cloud Functions with ADC enabled, you can simplify this.

        # NOTE: Using a placeholder key path, replace with your actual path or environment method
        cred = credentials.Certificate('meme-hunter-4f1c1-firebase-adminsdk-8if09-b0eff4234b.json')

        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred, {'projectId': 'meme-hunter-4f1c1'})

        # Use gcf_firestore.Client to potentially leverage ADC in Google Cloud
        db = gcf_firestore.Client()
        return db

    except Exception as e:
        print(f"Error initializing Firebase: {e}")
        # If the specific credential file is not found, attempt to use default credentials
        try:
            if not firebase_admin._apps:
                firebase_admin.initialize_app()
            db = gcf_firestore.Client()
            print("Successfully initialized Firebase using Application Default Credentials.")
            return db
        except Exception as e_default:
            print(f"Failed to initialize Firebase with Default Credentials: {e_default}")
            return None


# --- Firestore Query Functions ---

def get_latest_token_addresses(db: gcf_firestore.Client, chain: str) -> list[dict]:
    """
    Fetches token contract addresses and symbols from the latest batch in the database.
    Mimics fetchDocuments() logic from firestore_functions.dart.

    NOTE: Sorting by trade count has been removed as per user request. We are now only
    fetching all tokens associated with the latest batch timestamp.
    """
    if chain.lower() == 'eth':
        collection_name = 'tokens_by_timestamp'
    elif chain.lower() == 'sol':
        # TODO: Adjust collection name for SOL if necessary
        collection_name = 'tokens_by_timestamp_SOL'
    else:
        print(f"Unsupported chain: {chain}")
        return []

    print(f"\n--- Fetching latest tokens for {chain.upper()} from '{collection_name}' ---")

    try:
        # Step 1: Find the latest timestamp
        latest_ts_query = db.collection(collection_name).order_by('timestamp', direction=gcf_firestore.Query.DESCENDING).limit(1).stream()
        latest_ts_docs = list(latest_ts_query)

        if not latest_ts_docs:
            print(f"No documents found in '{collection_name}'.")
            return []

        latest_timestamp = latest_ts_docs[0].get('timestamp')
        print(f"Found latest batch timestamp: {latest_timestamp}")

        # Step 2: Query all documents with the latest timestamp. NO additional sorting.
        latest_tokens_query = db.collection(collection_name)\
            .where('timestamp', '==', latest_timestamp)\
            .stream()

        tokens = []
        for doc in latest_tokens_query:
            data = doc.to_dict()
            contract_address = data.get('SmartContract') # Assuming this is the field name
            symbol = data.get('Symbol')

            if contract_address and symbol:
                tokens.append({
                    'contract_address': contract_address,
                    'symbol': symbol,
                    'timestamp': latest_timestamp, # The timestamp of the batch
                })

        print(f"Found {len(tokens)} tokens in the latest {chain.upper()} batch.")
        return tokens

    except Exception as e:
        print(f"Error fetching latest tokens: {e}")
        return []


def get_latest_chart_timestamp(db: gcf_firestore.Client, contract_address: str) -> datetime.datetime:
    """
    Retrieves the latest saved timestamp from the charts collection for a token.
    If no data exists, returns a datetime object representing 2 weeks ago (the floor).
    """
    two_weeks_ago = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=TWO_WEEKS_HOURS)

    try:
        doc_ref = db.collection('charts').document(contract_address)
        doc = doc_ref.get()

        if doc.exists:
            data = doc.to_dict()
            minute_data = data.get('minute_data', [])

            if minute_data:
                # Find the latest timestamp in the minute_data array
                # The data structure is an array of maps: [{"timestamp": "...", "open": "..."}, ...]
                latest_ts_str = max(minute_data, key=lambda x: x.get('timestamp', ''))['timestamp']

                # Convert the ISO 8601 string to a datetime object
                latest_timestamp = datetime.datetime.fromisoformat(latest_ts_str.replace('Z', '+00:00'))

                # We want to start querying *after* this last saved point, so add 1 minute.
                new_query_start_time = latest_timestamp + datetime.timedelta(minutes=1)

                print(f"Historical data found. Latest saved timestamp: {latest_timestamp.isoformat()}")

                # We ensure the query doesn't start before the two-week floor,
                # although it generally won't since the data is pruned.
                return max(new_query_start_time, two_weeks_ago)

        print(f"No historical data found for {contract_address}. Starting from 2 weeks ago.")
        return two_weeks_ago

    except Exception as e:
        print(f"Error getting latest chart timestamp for {contract_address}: {e}")
        return two_weeks_ago


# --- Moralis API Functions ---

def find_most_liquid_pair(chain: str, token_address: str) -> dict | None:
    """Finds the most liquid trading pair for a given token contract address."""
    url = f"{MORALIS_BASE_URL}/erc20/{token_address}/pairs"
    params = {"chain": chain}

    # print(f"\n--- Finding liquid pair for {token_address} on {chain} ---")

    try:
        response = requests.get(url, headers=HEADERS, params=params)
        response.raise_for_status()
        data = response.json()

        pairs = data.get("pairs", [])
        if not pairs:
            # print("No trading pairs found for this token.")
            return None

        most_liquid_pair = max(
            pairs,
            key=lambda pair: pair.get('liquidity_usd', 0.0) if pair.get('liquidity_usd') is not None else -1
        )

        return most_liquid_pair if most_liquid_pair and most_liquid_pair.get('pair_address') else None

    except requests.exceptions.RequestException as e:
        print(f"Error finding pair for {token_address}: {e}")
        return None


def get_historical_ohlcv_range(chain: str, pair_address: str, from_date: datetime.datetime, to_date: datetime.datetime) -> list[dict]:
    """
    Queries historical minute OHLCV data for a given pair address within a specific range.
    Handles pagination backwards from to_date until from_date is reached.
    """
    all_ohlcv_data = []
    current_request_to_date = to_date

    print(f"Querying OHLCV from {from_date.isoformat(timespec='minutes')} to {to_date.isoformat(timespec='minutes')}")

    while current_request_to_date > from_date:

        from_date_str = from_date.isoformat(timespec='milliseconds').replace('+00:00', 'Z')
        to_date_str = current_request_to_date.isoformat(timespec='milliseconds').replace('+00:00', 'Z')

        url = f"{MORALIS_BASE_URL}/pairs/{pair_address}/ohlcv"
        params = {
            "chain": chain,
            "timeframe": "1min",
            "currency": "usd",
            "fromDate": from_date_str,
            "toDate": to_date_str,
            "limit": MAX_LIMIT_PER_REQUEST,
        }

        try:
            response = requests.get(url, headers=HEADERS, params=params)
            response.raise_for_status()
            data = response.json()

            ohlcv_results = data.get("result", [])

            if not ohlcv_results:
                # print("No more OHLCV data points returned. Stopping pagination.")
                break

            # Add new data. Moralis OHLCV returns oldest to newest within the requested window.
            all_ohlcv_data.extend(ohlcv_results)

            # Find the timestamp of the EARLIEST entry in this batch
            earliest_timestamp_in_batch_str = min(ohlcv_results, key=lambda x: x['timestamp'])['timestamp']

            # Set the next request's 'toDate' to be 1 millisecond before the earliest entry fetched
            current_request_to_date = datetime.datetime.fromisoformat(earliest_timestamp_in_batch_str.replace('Z', '+00:00')) - datetime.timedelta(milliseconds=1)

            # Stop if we've reached or passed the desired starting point
            if current_request_to_date < from_date:
                # print("Reached or surpassed the desired 'fromDate'. Stopping pagination.")
                break

            # Add a small delay for rate limit
            time.sleep(0.1)

        except requests.exceptions.RequestException as e:
            print(f"Error fetching OHLCV data: {e}")
            break

    # Filter the combined list to ensure correctness and adherence to the from_date
    final_ohlcv_data = [
        entry for entry in all_ohlcv_data
        if datetime.datetime.fromisoformat(entry['timestamp'].replace('Z', '+00:00')) >= from_date
    ]

    print(f"Total new OHLCV data points fetched: {len(final_ohlcv_data)}")
    return final_ohlcv_data


# --- Firestore Update Function ---

def update_ohlcv_in_firestore(db: gcf_firestore.Client, contract_address: str, new_ohlcv_data: list[dict]):
    """
    Fetches existing data, merges new data, prunes to 2 weeks (MAX_DATA_POINTS), and saves.
    """
    charts_ref = db.collection('charts').document(contract_address)

    # 1. Fetch existing data
    existing_data = []
    try:
        doc = charts_ref.get()
        if doc.exists:
            existing_data = doc.to_dict().get('minute_data', [])
    except Exception as e:
        print(f"Error fetching existing chart data: {e}. Proceeding with new data only.")

    # 2. Combine and prepare data
    # Create a dictionary for quick lookup and deduplication, using timestamp as key
    combined_data_map = {}

    # Add existing data
    for entry in existing_data:
        # Store only the required fields: timestamp and open
        key = entry.get("timestamp")
        if key:
            combined_data_map[key] = {"timestamp": key, "open": entry.get("open")}

    # Add new data, which will overwrite existing keys (deduplication)
    for entry in new_ohlcv_data:
        key = entry.get("timestamp")
        if key:
            combined_data_map[key] = {"timestamp": key, "open": entry.get("open")}

    # Convert back to a list and sort chronologically.
    # This step is CRITICAL to ensure the subsequent pruning keeps the *most recent* data.
    sorted_data = sorted(
        combined_data_map.values(),
        key=lambda x: datetime.datetime.fromisoformat(x['timestamp'].replace('Z', '+00:00'))
    )

    # 3. Prune data to the last MAX_DATA_POINTS (2 weeks)
    pruned_data = sorted_data[-MAX_DATA_POINTS:]

    # 4. Save to Firestore
    if not pruned_data:
        print(f"No data to save for {contract_address}.")
        return

    try:
        # Use SET with merge=True if only updating a field, but here we replace the whole minute_data array
        charts_ref.set({"minute_data": pruned_data})
        print(f"Successfully updated {contract_address} with {len(pruned_data)} total data points (2 week max).")
    except Exception as e:
        print(f"CRITICAL: Error saving data to Firestore for {contract_address}: {e}")

# --- Main Execution ---

def main():
    """Main function to run the scheduled task."""
    db = initialize_firebase()
    if not db:
        print("FATAL: Firestore connection failed. Exiting script.")
        return

    # --- 1. Process ETH Tokens ---

    BLOCKCHAIN_ETH = "eth"
    eth_tokens = get_latest_token_addresses(db, BLOCKCHAIN_ETH)

    print(f"\n--- Starting Data Fetch for {BLOCKCHAIN_ETH.upper()} Tokens ({len(eth_tokens)} found) ---")

    current_time_utc = datetime.datetime.now(datetime.timezone.utc)

    for token in eth_tokens:
        contract_address = token['contract_address']
        symbol = token['symbol']
        print(f"\n[Processing {symbol} ({contract_address[:6]}...)]")

        # 1. Determine the query start time
        start_date = get_latest_chart_timestamp(db, contract_address)

        # Determine the query end time (Current time)
        end_date = current_time_utc

        # Check if the start date is in the future or too close to the end date (e.g., already up to date)
        if start_date >= end_date - datetime.timedelta(minutes=1):
            print(f"  {symbol} is already up to date or data is in the future. Skipping Moralis query.")
            continue

        # 2. Find the most liquid pair
        pair_info = find_most_liquid_pair(BLOCKCHAIN_ETH, contract_address)

        if pair_info and pair_info.get("pair_address"):
            pair_address = pair_info["pair_address"]
            print(f"  Pair found: {pair_address} ({pair_info.get('exchange_name')})")

            # 3. Get historical minute OHLCV data
            new_ohlcv_data = get_historical_ohlcv_range(BLOCKCHAIN_ETH, pair_address, start_date, end_date)

            if new_ohlcv_data:
                # 4. Merge, prune, and update in Firestore
                update_ohlcv_in_firestore(db, contract_address, new_ohlcv_data)
            else:
                print(f"  No new OHLCV data fetched for {symbol} in the range.")
        else:
            print(f"  Could not find liquid pair for {symbol}. Skipping OHLCV query.")

    # --- 2. Process SOL Tokens (TODO) ---

    print("\n" + "="*50)
    print("TODO: Implement Solana (SOL) Token Processing Here.")
    print("="*50 + "\n")
    # BLOCKCHAIN_SOL = "sol"
    # sol_tokens = get_latest_token_addresses(db, BLOCKCHAIN_SOL)
    #
    # for token in sol_tokens:
    #     ... process solana tokens ...

    print("Script finished successfully.")


if __name__ == "__main__":
    main()