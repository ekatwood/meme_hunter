# cd '' && '/usr/local/bin/python3'  'write_unique_trades.py'

import requests
import json
from datetime import datetime
from google.cloud import firestore
import firebase_admin
from firebase_admin import credentials, firestore

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
   'X-API-KEY': 'BQY75FRZd1W7E0IsogU1Itsf8XJJJLzJ',
   'Authorization': 'Bearer ory_at_J0x9GDUlu4LOmRRqrzb3cRO5ZxBoSZB_Pwyn1O0FZSA._87lfdF4TTTw6qPP-Bm4nw-PZn4z7OfzHfSWvtRWiX8'
}

response = requests.post(url, headers=headers, json={'query': query})

if response.status_code == 200:
    data = response.json()
else:
    print(f"Error executing query: {response.status_code}")
    print(response.text)

# Extracting the data
trades = []
for item in data["data"]["EVM"]["DEXTradeByTokens"]:
    trade_info = {
        "Name": item["Trade"]["Currency"]["Name"],
        "mintAddress": item["Trade"]["Currency"]["Address"],
        "Symbol": item["Trade"]["Currency"]["Symbol"],
        "tradesCountWithUniqueTraders": int(item["tradesCountWithUniqueTraders"])
    }
    trades.append(trade_info)

# Creating the new JSON structure
new_json = {"trades": trades}

# for t in trades:
#     print(t)

# Get current date and hour, zeroing out minutes and seconds
current_time = datetime.now().replace(minute=0, second=0, microsecond=0)
timestamp = current_time.isoformat()

# Initialize Firebase Admin SDK
cred = credentials.Certificate('meme-hunter-4f1c1-firebase-adminsdk-8if09-b0eff4234b.json')
firebase_admin.initialize_app(cred)

# Initialize Firestore client
db = firestore.Client()

# Write data to Firestore
for trade in new_json['trades']:
    # Generate a unique ID for each document
    doc_ref = db.collection('tokens_by_timestamp').document()  # Generate a unique ID
    # Add timestamp field
    trade['timestamp'] = timestamp
    # Set the document in Firestore
    doc_ref.set(trade)

print('complete')
