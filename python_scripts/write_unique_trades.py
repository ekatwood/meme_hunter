# cd '' && '/usr/local/bin/python3'  'write_unique_trades.py'

import requests
import json
from datetime import datetime
from google.cloud import firestore
import firebase_admin
from firebase_admin import credentials, firestore, storage # Import storage
from moralis import evm_api
import io # To handle image data in memory

# Moralis API Key (replace with your actual key)
moralis_api_key = "x"

query = """
query find_unique_trades {
  EVM {
    DEXTradeByTokens(
      limit: { count: 150 }
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
    'X-API-KEY': 'x',
    'Authorization': 'Bearer x'
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

            if isinstance(batch_result, list):
                for token_data in batch_result:
                    if 'address' in token_data:
                        moralis_token_metadata[token_data['address'].lower()] = token_data
                    else:
                        print(f"Warning: Moralis batch result item missing 'address' key: {token_data}")
            else:
                print(f"Warning: Moralis API returned unexpected format for batch starting with {batch_addresses[0]}. Expected list, got {type(batch_result)}. Result: {batch_result}")

        except Exception as e:
            print(f"Error fetching Moralis data for batch {batch_addresses}: {e}")

# Enrich trades with Moralis metadata
for trade in new_json['trades']:
    address = trade["SmartContract"]
    token_metadata = moralis_token_metadata.get(address, {})

    trade['logo'] = token_metadata.get('logo', "")
    trade['circulating_supply'] = token_metadata.get('circulating_supply', "")
    trade['market_cap'] = token_metadata.get('market_cap', "")

    # Extracting twitter, website, and description
    links = token_metadata.get('links', {})
    trade['twitter_link'] = links.get('twitter', "")
    trade['website_link'] = links.get('website', "")
    trade['description'] = token_metadata.get('description', "")

# --- Firebase Initialization (ensure it's initialized only once) ---
try:
    cred = credentials.Certificate('meme-hunter-4f1c1-firebase-adminsdk-8if09-b0eff4234b.json')
    firebase_admin.initialize_app(cred, {'storageBucket': 'meme-hunter-4f1c1.firebasestorage.app'}) # Add storageBucket
except ValueError as e:
    if "The default Firebase app already exists" not in str(e):
        raise # Re-raise other ValueErrors
    # If already initialized, ensure storage bucket is associated if needed later
    print("Firebase app already initialized.")

db = firestore.Client(project='meme-hunter-4f1c1')
bucket = storage.bucket() # Get the default storage bucket

# --- Image Download and Upload to Firebase Storage ---
# We'll create a dictionary to store the Firebase Storage URLs to avoid
# re-downloading/re-uploading the same image multiple times if multiple
# tokens share the same logo URL.
uploaded_image_urls = {}

for trade in new_json['trades']:
    # Skip low market cap tokens
    if(len(trade['market_cap']) < 4 or float(trade['market_cap']) < 5000):
        print('skipping ' + trade['Name'] + ' low market cap: ' + trade['market_cap'])
        continue

    original_logo_url = trade['logo']

    if original_logo_url and original_logo_url.startswith('http'): # Ensure it's a valid URL
        if original_logo_url in uploaded_image_urls:
            # Use cached Firebase Storage URL if already uploaded
            trade['firebase_logo_url'] = uploaded_image_urls[original_logo_url]
            print(f"Using cached Firebase Storage URL for {original_logo_url}")
        else:
            try:
                # 1. Download the image
                print(f"Attempting to download: {original_logo_url}")
                image_response = requests.get(original_logo_url, stream=True)
                image_response.raise_for_status() # Raise an exception for bad status codes

                # Extract content type (e.g., 'image/webp') and determine file extension
                content_type = image_response.headers.get('Content-Type', 'application/octet-stream')
                file_extension = 'webp' # Default or derive from content_type
                if 'image/' in content_type:
                    file_extension = content_type.split('/')[-1].replace('jpeg', 'jpg').split(';')[0]

                image_data = io.BytesIO(image_response.content) # Store image data in memory

                # 2. Upload to Firebase Storage
                # Create a unique filename (e.g., smart_contract_address.webp)
                # You might want to sanitize the address for filenames
                filename = f"logos/{trade['SmartContract']}.{file_extension}"
                blob = bucket.blob(filename)

                # Set content type based on what was detected or expected
                blob.upload_from_file(image_data, content_type=content_type)
                blob.make_public() # Make the image publicly accessible

                # Get the public URL
                firebase_storage_url = blob.public_url
                trade['firebase_logo_url'] = firebase_storage_url
                uploaded_image_urls[original_logo_url] = firebase_storage_url # Cache the URL
                print(f"Uploaded {original_logo_url} to {firebase_storage_url}")

            except requests.exceptions.RequestException as e:
                print(f"Error downloading image {original_logo_url}: {e}")
                trade['firebase_logo_url'] = "" # Set to empty if download fails
            except Exception as e:
                print(f"Error uploading image {original_logo_url} to Firebase Storage: {e}")
                trade['firebase_logo_url'] = "" # Set to empty if upload fails
    else:
        trade['firebase_logo_url'] = "" # No valid logo URL

    # Remove the original 'logo' field if you only want the Firebase URL
    # Or keep it if you want both for debugging/fallback
    if 'logo' in trade:
        del trade['logo']


# --- Firestore Integration ---

# Get current date and hour, zeroing out minutes and seconds
current_time = datetime.now().replace(minute=0, second=0, microsecond=0)
timestamp = current_time.isoformat()

# Write data to Firestore
for trade in new_json['trades']:
    # Skip low market cap tokens
    if(len(trade['market_cap']) < 4 or float(trade['market_cap']) < 5000):
        print('skipping ' + trade['Name'] + ' low market cap: ' + trade['market_cap'])
        continue

    doc_ref = db.collection('tokens_by_timestamp').document()
    trade['timestamp'] = timestamp
    doc_ref.set(trade)

print('complete')
