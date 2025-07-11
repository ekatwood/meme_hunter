# cd '' && '/usr/local/bin/python3'  'write_unique_trades_SOL.py'

import requests
import json
from datetime import datetime
from google.cloud import firestore
import firebase_admin
from firebase_admin import credentials, firestore, storage
from moralis import sol_api
import io

# Moralis API Key (replace with your actual key)
moralis_api_key = "x"

query = """
{
  Solana {
    DEXTradeByTokens(
      orderBy: {descendingByField: "buy"}
      where: {Trade: {Currency: {MintAddress: {notIn: ["So11111111111111111111111111111111111111112", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"]}}, Dex: {ProtocolFamily: {is: "Raydium"}}}, Transaction: {Result: {Success: true}}}
      limit: {count: 120}
    ) {
      Trade {
        Currency {
          Symbol
          Name
          MintAddress
        }
      }
      buy: sum(of: Trade_Side_AmountInUSD, if: {Trade: {Side: {Type: {is: buy}}}})
      sell: sum(of: Trade_Side_AmountInUSD, if: {Trade: {Side: {Type: {is: sell}}}})
    }
  }
}
"""

url = 'https://streaming.bitquery.io/eap'

headers = {
   'Content-Type': 'application/json',
   'X-API-KEY': 'x',
   'Authorization': 'Bearer x'
}

response = requests.post(url, headers=headers, json={'query': query})

if response.status_code == 200:
    data = response.json()
else:
    print(f"Error executing query: {response.status_code}")
    print(response.text)

# Extracting the data
counter = 1
trades = []
token_addresses = []

for item in data["data"]["Solana"]["DEXTradeByTokens"]:
    if len(str(item["Trade"]["Currency"]["Name"])) == 0 or len(str(item["Trade"]["Currency"]["Symbol"])) == 0:
        continue

    trade_info = {
        "Counter": counter,
        "Name": item["Trade"]["Currency"]["Name"],
        "MintAddress": item["Trade"]["Currency"]["MintAddress"],
        "Symbol": item["Trade"]["Currency"]["Symbol"]
    }
    trades.append(trade_info)
    token_addresses.append(item["Trade"]["Currency"]["MintAddress"])
    counter += 1

# Creating the new JSON structure
new_json = {"trades": trades}

# --- Moralis API Integration ---
moralis_token_metadata = {}

# Iterate through token_addresses in chunks of batch_size
for address in token_addresses:

    moralis_params = {
        "address": address,
        "network": "mainnet",
    }
    try:
        # Make a batch call to Moralis for the current chunk
        result = sol_api.token.get_token_metadata(
            api_key=moralis_api_key,
            params=moralis_params,
        )

        moralis_token_metadata[result['mint'].lower()] = result

    except Exception as e:
        print(f"Error fetching Moralis data for {address}: {e}")

# Enrich trades with Moralis metadata
for trade in new_json['trades']:
    address = trade["MintAddress"].lower()
    token_metadata = moralis_token_metadata.get(address, {})

    trade['logo'] = token_metadata.get('logo', "")
    trade['totalSupplyFormatted'] = token_metadata.get('totalSupplyFormatted', "")
    trade['fullyDilutedValue'] = token_metadata.get('fullyDilutedValue', "")

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
                filename = f"logos_SOL/{trade['MintAddress']}.{file_extension}"
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

# Get current date and hour, zeroing out minutes and seconds
current_time = datetime.now().replace(minute=0, second=0, microsecond=0)
timestamp = current_time.isoformat()

# Initialize Firestore client
db = firestore.Client(project='meme-hunter-4f1c1') # Hardcoded project ID

# Write data to Firestore
for trade in new_json['trades']:
    # Generate a unique ID for each document
    doc_ref = db.collection('tokens_by_timestamp_SOL').document()  # Generate a unique ID
    # Add timestamp field
    trade['timestamp'] = timestamp
    # Set the document in Firestore
    doc_ref.set(trade)

print('complete')
