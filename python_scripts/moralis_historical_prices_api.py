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
# The old MAX_DATA_POINTS (20160) is now irrelevant as we no longer store the full 2 weeks of minute data.
MORALIS_API_KEY = "x"  # Replace with your actual Moralis API Key
MORALIS_BASE_URL = "https://deep-index.moralis.io/api/v2.2"
HEADERS = {
    "accept": "application/json",
    "X-API-Key": MORALIS_API_KEY,
}
MAX_LIMIT_PER_REQUEST = 1000  # Max limit for Moralis OHLCV endpoint

# --- Chart Timeframe Mapping (Matches client-side in token_details.dart) ---
# Used for server-side thinning from 1-hour OHLCV data.
# The index 0 (1H) is generated from 1-minute data and does not need thinning intervals.
TIME_FILTER_MAP = [
    {'key': 'data_1h', 'duration_hours': 1, 'sample_interval': 1}, # This uses 1-minute candles
    {'key': 'data_6h', 'duration_hours': 6, 'sample_interval': 3}, # Every 3rd 1-minute candle, but we will use 1-hour candles for all these
    {'key': 'data_12h', 'duration_hours': 12, 'sample_interval': 6},
    {'key': 'data_1d', 'duration_hours': 24, 'sample_interval': 10},
    {'key': 'data_1w', 'duration_hours': 168, 'sample_interval': 27},
    {'key': 'data_2w', 'duration_hours': 336, 'sample_interval': 55},
]


# --- Firestore Initialization (GCloud-friendly) ---

def initialize_firebase():
    """Initializes the Firebase Admin SDK."""
    try:
        cred = credentials.Certificate('meme-hunter-4f1c1-firebase-adminsdk-8if09-b0eff4234b.json')

        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred, {'projectId': 'meme-hunter-4f1c1'})

        db = gcf_firestore.Client()
        return db

    except Exception as e:
        print(f"Error initializing Firebase: {e}")
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

        # Step 2: Query all documents with the latest timestamp.
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
    Now only tracks the latest timestamp from the 'data_1h' field for continuity.
    """
    # We only need the latest timestamp of the 1-hour data to know where to start querying the new minute data.
    one_hour_ago = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)

    try:
        doc_ref = db.collection('charts').document(contract_address)
        doc = doc_ref.get()

        if doc.exists:
            data = doc.to_dict()
            # Check the most granular data field, which is data_1h (contains 1-minute candles)
            minute_data = data.get('data_1h', [])

            if minute_data:
                # Find the latest timestamp in the minute_data array
                latest_ts_str = max(minute_data, key=lambda x: x.get('timestamp', ''))['timestamp']

                # Convert the ISO 8601 string to a datetime object
                latest_timestamp = datetime.datetime.fromisoformat(latest_ts_str.replace('Z', '+00:00'))

                # We want to start querying *after* this last saved point, so add 1 minute.
                new_query_start_time = latest_timestamp + datetime.timedelta(minutes=1)

                print(f"Historical 1-minute data found. Latest saved timestamp: {latest_timestamp.isoformat()}")

                # The floor for the 1-minute query is 1 hour ago.
                return max(new_query_start_time, one_hour_ago)

        print(f"No historical data found for {contract_address}. Starting 1-minute query from 1 hour ago.")
        return one_hour_ago

    except Exception as e:
        print(f"Error getting latest chart timestamp for {contract_address}: {e}")
        return one_hour_ago


# --- Moralis API Functions ---

def find_most_liquid_pair(chain: str, token_address: str) -> dict | None:
    """Finds the most liquid trading pair for a given token contract address."""
    url = f"{MORALIS_BASE_URL}/erc20/{token_address}/pairs"
    params = {"chain": chain}

    try:
        response = requests.get(url, headers=HEADERS, params=params)
        response.raise_for_status()
        data = response.json()

        pairs = data.get("pairs", [])
        if not pairs:
            return None

        most_liquid_pair = max(
            pairs,
            key=lambda pair: pair.get('liquidity_usd', 0.0) if pair.get('liquidity_usd') is not None else -1
        )

        return most_liquid_pair if most_liquid_pair and most_liquid_pair.get('pair_address') else None

    except requests.exceptions.RequestException as e:
        print(f"Error finding pair for {token_address}: {e}")
        return None

def get_historical_ohlcv_range(chain: str, pair_address: str, from_date: datetime.datetime, to_date: datetime.datetime, timeframe: str) -> list[dict]:
    """
    Queries historical OHLCV data for a given pair address within a specific range.
    Handles pagination backwards from to_date until from_date is reached.
    """
    all_ohlcv_data = []
    current_request_to_date = to_date

    print(f"Querying {timeframe} OHLCV from {from_date.isoformat(timespec='minutes')} to {to_date.isoformat(timespec='minutes')}")

    while current_request_to_date > from_date:

        # Moralis API call parameters
        from_date_str = from_date.isoformat(timespec='milliseconds').replace('+00:00', 'Z')
        to_date_str = current_request_to_date.isoformat(timespec='milliseconds').replace('+00:00', 'Z')

        url = f"{MORALIS_BASE_URL}/pairs/{pair_address}/ohlcv"
        params = {
            "chain": chain,
            "timeframe": timeframe,
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
                break

            # Add new data. Moralis OHLCV returns oldest to newest within the requested window.
            all_ohlcv_data.extend(ohlcv_results)

            # Find the timestamp of the EARLIEST entry in this batch
            earliest_timestamp_in_batch_str = min(ohlcv_results, key=lambda x: x['timestamp'])['timestamp']

            # Set the next request's 'toDate' to be 1 millisecond before the earliest entry fetched
            current_request_to_date = datetime.datetime.fromisoformat(earliest_timestamp_in_batch_str.replace('Z', '+00:00')) - datetime.timedelta(milliseconds=1)

            # Stop if we've reached or passed the desired starting point
            if current_request_to_date < from_date:
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

    print(f"Total new {timeframe} OHLCV data points fetched: {len(final_ohlcv_data)}")
    return final_ohlcv_data


def fetch_and_get_existing_minute_data(db: gcf_firestore.Client, contract_address: str) -> list[dict]:
    """Fetches the existing data_1h array from Firestore."""
    try:
        doc_ref = db.collection('charts').document(contract_address)
        doc = doc_ref.get()
        if doc.exists:
            # We only need the existing 1-minute data for the data_1h chart continuity
            return doc.to_dict().get('data_1h', [])
    except Exception as e:
        print(f"Error fetching existing chart data_1h: {e}. Returning empty list.")
    return []


# --- Firestore Update Function ---

def update_ohlcv_in_firestore(db: gcf_firestore.Client, contract_address: str, new_minute_data: list[dict], new_hourly_data: list[dict]):
    """
    Merges new 1-minute data with existing, prunes to 1 hour, then uses hourly data
    to generate and save six pre-thinned chart arrays (data_1h, data_6h, ... data_2w).
    """
    charts_ref = db.collection('charts').document(contract_address)
    charts_to_save = {}

    # --- 1. Process 1-Minute Data for the 'data_1h' Chart ---

    # Fetch existing minute data (only the last 1-hour worth)
    existing_minute_data = fetch_and_get_existing_minute_data(db, contract_address)

    # Combine and deduplicate
    combined_data_map = {}
    for entry in existing_minute_data + new_minute_data:
        key = entry.get("timestamp")
        # Ensure we only store the required fields for the client-side ChartData model: timestamp and open
        if key:
            combined_data_map[key] = {"timestamp": key, "open": entry.get("open")}

    # Convert back to a list and sort chronologically
    sorted_minute_data = sorted(
        combined_data_map.values(),
        key=lambda x: datetime.datetime.fromisoformat(x['timestamp'].replace('Z', '+00:00'))
    )

    # Prune to exactly the last 60 minutes for the 'data_1h' chart
    charts_to_save['data_1h'] = sorted_minute_data[-60:]
    print(f"  Generated 'data_1h' with {len(charts_to_save['data_1h'])} points (last 60 mins).")

    # --- 2. Process 1-Hour Data for Long Timeframe Charts (6H to 2W) ---

    # Sort the new hourly data just in case, and convert to the simplified structure
    sorted_hourly_data = sorted(
        [{"timestamp": entry['timestamp'], "open": entry['open']} for entry in new_hourly_data],
        key=lambda x: datetime.datetime.fromisoformat(x['timestamp'].replace('Z', '+00:00'))
    )

    # Generate the 5 longer timeframe charts (skipping the 1H index 0)
    # The client-side logic samples every N minutes. Here, we can simply take the last N hours.
    for i in range(1, len(TIME_FILTER_MAP)):
        filter_spec = TIME_FILTER_MAP[i]
        key = filter_spec['key']
        duration_hours = filter_spec['duration_hours']

        # Take the last 'duration_hours' of data points from the sorted_hourly_data
        # Note: 1 data point = 1 hour, so we slice by the number of hours.
        thinned_data = sorted_hourly_data[-duration_hours:]

        charts_to_save[key] = thinned_data
        print(f"  Generated '{key}' with {len(thinned_data)} points (last {duration_hours} hours).")


    # --- 3. Save All Six Charts to Firestore ---
    if not charts_to_save:
        print(f"No data to save for {contract_address}.")
        return

    try:
        charts_ref.set(charts_to_save)
        print(f"Successfully updated {contract_address} with 6 pre-thinned chart arrays.")
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

        # 1. Determine the query start time for 1-minute data (last hour)
        minute_start_date = get_latest_chart_timestamp(db, contract_address)
        end_date = current_time_utc

        # Check if the start date is in the future or too close to the end date
        if minute_start_date >= end_date - datetime.timedelta(minutes=1):
            print(f"  {symbol} minute data is already up to date. Skipping Moralis queries.")
            continue # Move to the next token

        # 2. Find the most liquid pair
        pair_info = find_most_liquid_pair(BLOCKCHAIN_ETH, contract_address)

        if pair_info and pair_info.get("pair_address"):
            pair_address = pair_info["pair_address"]
            print(f"  Pair found: {pair_address} ({pair_info.get('exchange_name')})")

            # --- A. Fetch 1-HOUR data for the full 2-week history (Low cost, 336 points max) ---
            # This data is used to generate the 6H, 12H, 1D, 1W, 2W charts.
            hourly_start_date = current_time_utc - datetime.timedelta(hours=TWO_WEEKS_HOURS)
            new_hourly_data = get_historical_ohlcv_range(BLOCKCHAIN_ETH, pair_address, hourly_start_date, end_date, "1hour")

            # --- B. Fetch 1-MINUTE data for the last 1 hour (Granular update) ---
            # This data is used to update the 1H chart.
            new_minute_data = get_historical_ohlcv_range(BLOCKCHAIN_ETH, pair_address, minute_start_date, end_date, "1min")

            if new_minute_data or new_hourly_data:
                # 3. Pre-process and update all 6 chart arrays in Firestore
                update_ohlcv_in_firestore(db, contract_address, new_minute_data, new_hourly_data)
            else:
                print(f"  No new OHLCV data fetched for {symbol} in the required ranges.")
        else:
            print(f"  Could not find liquid pair for {symbol}. Skipping OHLCV query.")

        # Add a small delay between processing tokens to respect potential API burst limits
        time.sleep(0.5)

    # --- 2. Process SOL Tokens (TODO) ---

    print("\n" + "="*50)
    print("TODO: Implement Solana (SOL) Token Processing Here.")
    print("="*50 + "\n")

    print("Script finished successfully.")


if __name__ == "__main__":
    main()