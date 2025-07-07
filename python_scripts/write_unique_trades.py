# cd '' && '/usr/local/bin/python3'  'write_unique_trades.py'

import requests
import json
from datetime import datetime
from google.cloud import firestore
import firebase_admin
from firebase_admin import credentials, firestore
from moralis import evm_api # Import moralis evm_api

# Moralis API Key (replace with your actual key)
moralis_api_key = "todo: hide api key"

query = """
query find_unique_trades {
  EVM {
    DEXTradeByTokens(
      limit: { count: 120 }
      orderBy: { descendingByField: "tradesCountWithUniqueTraders" }
    ) {
      Trade {
        Currency {
          Name
          Symbol
          SmartContract
        }
      }
      tradesCountWithUniqueTraders: count(distinct: Transaction_From)
    }
  }
}
"""

url = 'https://streaming.bitquery.io/graphql'

headers = {
   'Content-Type': 'application/json',
   'X-API-KEY': 'todo: hide api key',
   'Authorization': 'Bearer todo: hide api key'
}

response = requests.post(url, headers=headers, json={'query': query})

if response.status_code == 200:
    data = response.json()
else:
    print(f"Error executing BitQuery: {response.status_code}")
    print(response.text)
    exit() # Exit if BitQuery fails

# Extracting the data
trades = []
raw_token_addresses = []

for item in data["data"]["EVM"]["DEXTradeByTokens"]:
    trade_info = {
        "Name": item["Trade"]["Currency"]["Name"],
        "SmartContract": item["Trade"]["Currency"]["SmartContract"],
        "Symbol": item["Trade"]["Currency"]["Symbol"],
        "tradesCountWithUniqueTraders": int(item["tradesCountWithUniqueTraders"])
    }
    trades.append(trade_info)
    raw_token_addresses.append(item["Trade"]["Currency"]["SmartContract"])

# Creating the new JSON structure
new_json = {"trades": trades}

# --- Filter out invalid addresses before calling Moralis API ---
token_addresses = []
for address in raw_token_addresses:
    # Basic validation for Ethereum addresses: starts with '0x' and is 42 characters long
    # (0x + 40 hex characters)
    if isinstance(address, str) and address.startswith('0x') and len(address) == 42:
        token_addresses.append(address.lower()) # Convert to lowercase for consistency
    else:
        print(f"Skipping invalid token address: {address}")

# --- Moralis API Integration (Batching Requests) ---
moralis_token_metadata = {}
if token_addresses: # Only call Moralis if there are addresses to query
    # Define the batch size for Moralis API (max 10 addresses)
    batch_size = 10

    # Iterate through token_addresses in chunks of batch_size
    for i in range(0, len(token_addresses), batch_size):
        batch_addresses = token_addresses[i:i + batch_size]

        moralis_params = {
            "addresses": batch_addresses,
            "chain": "eth",
        }
        try:
            # Make a batch call to Moralis for the current chunk
            batch_result = evm_api.token.get_token_metadata(
                api_key=moralis_api_key,
                params=moralis_params,
            )

            # CONFIRMED CHANGE: Iterate through batch_result (which is a list of dicts)
            # and add each token's data to our main moralis_token_metadata dict.
            if isinstance(batch_result, list):
                for token_data in batch_result:
                    # Ensure the 'address' key exists before using it
                    if 'address' in token_data:
                        moralis_token_metadata[token_data['address'].lower()] = token_data # Store address as lower-case for consistent lookups
                    else:
                        print(f"Warning: Moralis batch result item missing 'address' key: {token_data}")
            else:
                # This 'else' block should theoretically not be hit if the format is consistent
                # but it's good for debugging if an unexpected format occurs.
                print(f"Warning: Moralis API returned unexpected format for batch starting with {batch_addresses[0]}. Expected list, got {type(batch_result)}. Result: {batch_result}")

        except Exception as e:
            print(f"Error fetching Moralis data for batch {batch_addresses}: {e}")

# ... (rest of the code remains the same) ...
# Enrich trades with Moralis metadata
for trade in new_json['trades']:
    address = trade["SmartContract"]
    # Get metadata for the current token from the aggregated dictionary
    token_metadata = moralis_token_metadata.get(address, {}) # Use .get() with default empty dict for safety

    # Assign Moralis fields, defaulting to an empty string if not found or null
    # Using .get() with a default empty string for robustness
    trade['logo'] = token_metadata.get('logo', "")
    trade['circulating_supply'] = token_metadata.get('circulating_supply', "")
    trade['market_cap'] = token_metadata.get('market_cap', "")

# --- Firestore Integration ---

# Get current date and hour, zeroing out minutes and seconds
current_time = datetime.now().replace(minute=0, second=0, microsecond=0)
timestamp = current_time.isoformat()

# Initialize Firebase Admin SDK
try:
    cred = credentials.Certificate('meme-hunter-4f1c1-firebase-adminsdk-8if09-b0eff4234b.json')
    firebase_admin.initialize_app(cred)
except ValueError as e:
    # If the app is already initialized (e.g., in a cloud function environment), skip re-initialization
    if "The default Firebase app already exists" not in str(e):
        pass # Do nothing, app is already initialized
    else:
        raise # Re-raise other ValueErrors
    print("Firebase app already initialized (or skipped re-initialization).")


# Initialize Firestore client
db = firestore.Client(project='meme-hunter-4f1c1') # Hardcoded project ID

# Write data to Firestore
for trade in new_json['trades']:
    # Generate a unique ID for each document
    doc_ref = db.collection('tokens_by_timestamp').document()  # Generate a unique ID
    # Add timestamp field
    trade['timestamp'] = timestamp
    # Set the document in Firestore
    doc_ref.set(trade)

print('complete')
