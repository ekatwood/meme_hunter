async function connectSolflare() {
  try {
    if (!window.solflare) {
      //console.error("Solflare unavailable.");
      return "Solflare unavailable";
    }

    const response = await window.solflare.connect();

    if (response) {
      return window.solflare.publicKey.toString();
    }
  } catch (error) {
    //console.error("Error connecting to Solflare: ", error);
    return "Solflare unavailable";
  }
}

/**
 * Signs a Solana transaction using the Solflare wallet and sends it to a
 * Google Cloud Function for broadcast.
 * @param {string} base64Transaction - A base64-encoded string of the Solana transaction.
 * @returns {Promise<string|null>} The transaction signature if successful, null otherwise.
 */
async function signTransactionSolana(base64Transaction) {
  try {
    if (!window.solflare) {
      console.error("Solflare not detected.");
      return null;
    }

    // Decode the base64 string to a byte array
    const decodedBytes = Uint8Array.from(atob(base64Transaction), c => c.charCodeAt(0));

    // Check for the global solanaWeb3 object
    if (typeof solanaWeb3 === 'undefined') {
      console.error("Solana Web3.js library not available.");
      return null;
    }

    // Deserialize the byte array back into a Transaction object
    const transaction = solanaWeb3.VersionedTransaction.deserialize(decodedBytes);

    console.log("Deserialized transaction successfully.");

    // Sign the transaction with Solflare
    const signedTransaction = await window.solflare.signTransaction(transaction);
    console.log("Solflare signed the transaction.");

    // Serialize the signed transaction to base64 using the global bs58 object
    const serializedTransaction = bs58.encode(signedTransaction.serialize());

    // Assuming the GCloud function returns the signature
    return serializedTransaction;

  } catch (error) {
    console.error("Error signing Solana transaction:", error);
    if (error.code === 4001 || error.message.includes("User rejected")) {
      console.warn("Solflare user rejected the transaction.");
    }
    return null;
  }
}