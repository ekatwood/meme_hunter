# cd '' && '/usr/local/bin/python3'  'moralis_historical_prices_api.py'
import requests
import json
import datetime
import time
import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore

# --- Configuration ---
MORALIS_API_KEY = "x"  # Replace with your actual Moralis API Key
MORALIS_BASE_URL = "https://deep-index.moralis.io/api/v2.2"

# --- Inputs ---
BLOCKCHAIN = "eth"  # e.g., "eth", "bsc", "polygon"
TOKEN_CONTRACT_ADDRESS = "0x95af4af910c28e8ece4512bfe46f1f33687424ce"
HOURS_BACK = 120  # How many hours of minute data to query

# --- API Headers ---
HEADERS = {
    "accept": "application/json",
    "X-API-Key": MORALIS_API_KEY,
}

def find_most_liquid_pair(chain: str, token_address: str) -> dict | None:
    """
    Finds the most liquid trading pair for a given token contract address.
    Returns the pair data (including pair_address and liquidity_usd) or None if not found.
    """
    url = f"{MORALIS_BASE_URL}/erc20/{token_address}/pairs"
    params = {
        "chain": chain
    }

    print(f"\n--- Step 1: Finding most liquid pair for {token_address} on {chain} ---")
    print(f"Querying URL: {url} with params: {params}")

    try:
        response = requests.get(url, headers=HEADERS, params=params)
        response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
        data = response.json()

        pairs = data.get("pairs", [])
        if not pairs:
            print("No trading pairs found for this token.")
            return None

        # Sort pairs by 'liquidity_usd' in descending order
        most_liquid_pair = None
        max_liquidity = -1

        for pair in pairs:
            liquidity = pair.get('liquidity_usd', 0.0) # Use .get() with default to handle missing key
            if liquidity is not None and liquidity > max_liquidity:
                max_liquidity = liquidity
                most_liquid_pair = pair

        if most_liquid_pair:
            print(f"Found most liquid pair:")
            print(f"  Pair Address: {most_liquid_pair.get('pair_address')}")
            print(f"  Exchange Name: {most_liquid_pair.get('exchange_name')}")
            print(f"  Liquidity (USD): ${most_liquid_pair.get('liquidity_usd'):,.2f}")
            print(f"  Pair Label: {most_liquid_pair.get('pair_label')}")
            return most_liquid_pair
        else:
            print("No liquid pairs found among the results.")
            return None

    except requests.exceptions.RequestException as e:
        print(f"Error finding pair: {e}")
        print(f"Response content: {response.text if 'response' in locals() else 'N/A'}")
        return None

def get_historical_ohlcv(chain: str, pair_address: str, hours_back: int) -> list[dict]:
    """
    Queries historical minute OHLCV data for a given pair address, handling pagination.
    """
    all_ohlcv_data = []

    # Define the absolute target end time (latest point we want data up to, which is now)
    target_end_time = datetime.datetime.now(datetime.timezone.utc)

    # Define the absolute target start time (earliest point we want data from)
    target_start_time = target_end_time - datetime.timedelta(hours=hours_back)

    # The 'toDate' parameter for our API calls will start at target_end_time
    # and progressively move backward in time with each pagination step.
    current_request_to_date = target_end_time

    MAX_LIMIT_PER_REQUEST = 1000 # Corrected max limit for Moralis OHLCV endpoint

    print(f"\n--- Step 2: Querying historical OHLCV data for {pair_address} on {chain} ---")

    # Use a flag or counter to control the loop instead of 'while True'
    # We will loop as long as `current_request_to_date` is after `target_start_time`
    # and we are still getting data back from the API.
    while current_request_to_date > target_start_time:
        # Format dates to ISO 8601 string with 'Z' for UTC
        # The 'fromDate' for each request should always be `target_start_time`
        # to ensure we don't miss data if the pagination jumps too far back.
        # The 'toDate' will define the upper bound of the current chunk.
        from_date_str = target_start_time.isoformat(timespec='milliseconds').replace('+00:00', 'Z')
        to_date_str = current_request_to_date.isoformat(timespec='milliseconds').replace('+00:00', 'Z')

        url = f"{MORALIS_BASE_URL}/pairs/{pair_address}/ohlcv"
        params = {
            "chain": chain,
            "timeframe": "1min",  # Requesting minute data
            "currency": "usd",
            "fromDate": from_date_str,
            "toDate": to_date_str,
            "limit": MAX_LIMIT_PER_REQUEST,
        }

        print(f"Querying URL: {url} with params: {params}")

        try:
            response = requests.get(url, headers=HEADERS, params=params)
            response.raise_for_status()
            data = response.json()

            ohlcv_results = data.get("result", [])
            print(f"Fetched {len(ohlcv_results)} OHLCV data points in this request.")

            if not ohlcv_results:
                print("No more OHLCV data points returned for this time range or we reached end. Stopping pagination.")
                break # No more data to fetch

            # Moralis OHLCV data is typically returned from oldest to newest within the specified range.
            # We add them to our master list.
            all_ohlcv_data.extend(ohlcv_results)

            # To paginate backwards, we need to set the `current_request_to_date` for the *next* request
            # to be just before the `timestamp` of the *earliest* entry fetched in the current batch.
            # This ensures we continue fetching older data.

            # Sort the current batch by timestamp to reliably find the earliest entry
            # (although Moralis usually returns them sorted, it's safer to ensure)
            ohlcv_results.sort(key=lambda x: datetime.datetime.fromisoformat(x['timestamp'].replace('Z', '+00:00')))

            # The earliest entry in this batch is ohlcv_results[0]
            earliest_timestamp_in_batch_str = ohlcv_results[0]['timestamp']

            # Convert to datetime object and set it as the new 'current_request_to_date' for the next iteration.
            # Subtract 1 millisecond to ensure the next request's range starts just before this entry.
            current_request_to_date = datetime.datetime.fromisoformat(earliest_timestamp_in_batch_str.replace('Z', '+00:00')) - datetime.timedelta(milliseconds=1)

            # --- Important check for stopping the loop ---
            # If the current_request_to_date has moved past or met our target_start_time, we've gathered enough data.
            if current_request_to_date <= target_start_time:
                print("Reached or surpassed the desired 'fromDate'. Stopping pagination.")
                break

            # Also, if we fetched less than the MAX_LIMIT_PER_REQUEST, it means we got all available data
            # up to `current_request_to_date` for this segment, so no more older data might be available.
            if len(ohlcv_results) < MAX_LIMIT_PER_REQUEST:
                print("Less than max limit received, assuming all available data for this segment fetched. Stopping pagination.")
                break

            # Add a small delay to avoid hitting rate limits too quickly
            time.sleep(0.1) # Be mindful of Moralis rate limits; adjust as needed

        except requests.exceptions.RequestException as e:
            print(f"Error fetching OHLCV data: {e}")
            print(f"Response content: {response.text if 'response' in locals() else 'N/A'}")
            break # Stop if an error occurs

    # After fetching all data, sort the combined list by timestamp to ensure it's in perfect chronological order
    all_ohlcv_data.sort(key=lambda x: datetime.datetime.fromisoformat(x['timestamp'].replace('Z', '+00:00')))
    print(f"Total fetched OHLCV data points: {len(all_ohlcv_data)}")

    # Filter out data points that are outside our desired target_start_time,
    # as the pagination might fetch slightly beyond it due to millisecond adjustments.
    final_ohlcv_data = [
        entry for entry in all_ohlcv_data
        if datetime.datetime.fromisoformat(entry['timestamp'].replace('Z', '+00:00')) >= target_start_time
    ]
    print(f"Total filtered OHLCV data points within range: {len(final_ohlcv_data)}")
    return final_ohlcv_data

def add_ohlcv_to_firestore(ohlcv_data: list[dict], token_contract_address: str):
    """
    Adds OHLCV timestamp and open price data to a Firestore collection 'charts'.
    The document ID for each entry will be the token_contract_address.
    Each document will contain a list of maps, where each map has 'timestamp' and 'open'.
    """

    if not ohlcv_data:
        print("No OHLCV data to add to Firestore.")
        return

    # Initialize firebase
    try:
        cred = credentials.Certificate('meme-hunter-4f1c1-firebase-adminsdk-8if09-b0eff4234b.json')
        firebase_admin.initialize_app(cred)
    except ValueError as e:
        if "The default Firebase app already exists" not in str(e):
            raise # Re-raise other ValueErrors
        # If already initialized, ensure storage bucket is associated if needed later
        print("Firebase app already initialized.")

    db = firestore.Client(project='meme-hunter-4f1c1')

    print(f"\n--- Step 3: Adding OHLCV data to Firestore for {token_contract_address} ---")

    charts_ref = db.collection('charts').document(token_contract_address)

    # Prepare the data in the desired format
    data_to_store = []
    for entry in ohlcv_data:
        data_to_store.append({
            "timestamp": entry.get("timestamp"),
            "open": entry.get("open")
        })

    try:
        # Set the entire list under a field, for example, 'minute_data'
        # This will overwrite the document if it already exists.
        # If you want to append, you'd need to fetch existing data, append, and then update.
        charts_ref.set({"minute_data": data_to_store})
        print(f"Successfully added {len(data_to_store)} OHLCV data points to Firestore "
              f"document '{token_contract_address}' in collection 'charts'.")
    except Exception as e:
        print(f"Error adding data to Firestore: {e}")

# --- Main Execution ---
if __name__ == "__main__":
    # Find the most liquid pair
    pair_info = find_most_liquid_pair(BLOCKCHAIN, TOKEN_CONTRACT_ADDRESS)

    if pair_info and pair_info.get("pair_address"):
        pair_address = pair_info["pair_address"]

        # Get historical minute OHLCV data
        ohlcv_data = get_historical_ohlcv(BLOCKCHAIN, pair_address, HOURS_BACK)

        if ohlcv_data:
            # print("\n--- First 5 OHLCV data points: ---")
            # for i, entry in enumerate(ohlcv_data[:5]):
            #     print(f"  {json.dumps(entry, indent=2)}") # Pretty-print each entry with 2-space indent
            # if len(ohlcv_data) > 5:
            #     print(f"  ... and {len(ohlcv_data) - 5} more.")
            #
            # print("\n--- Last 5 OHLCV data points: ---")
            # for i, entry in enumerate(ohlcv_data[-5:]):
            #     print(f"  {json.dumps(entry, indent=2)}") # Pretty-print each entry with 2-space indent
            add_ohlcv_to_firestore(ohlcv_data, TOKEN_CONTRACT_ADDRESS)
        else:
            print("\nNo OHLCV data was fetched.")

    else:
        print("\nCould not proceed with OHLCV query as no liquid pair was found.")
