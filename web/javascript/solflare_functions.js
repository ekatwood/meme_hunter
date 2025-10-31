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
 * Signs a Solana transaction using the Solflare wallet and returns the Base64-encoded,
 * fully signed transaction for subsequent broadcast via the GCloud function.
 * @param {string} base64Transaction - A base64-encoded string of the Solana transaction.
 * @returns {Promise<string|null>} The Base64 serialized transaction if successful, null otherwise.
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

    // Deserialize the byte array back into a VersionedTransaction object
    // This is correct as Jupiter returns a V0 transaction
    const transaction = solanaWeb3.VersionedTransaction.deserialize(decodedBytes);

    console.log("Deserialized transaction successfully.");

    // Sign the transaction with Solflare
    const signedTransaction = await window.solflare.signTransaction(transaction);
    console.log("Solflare signed the transaction.");

    // --- FIX APPLIED HERE ---
    // Serialize the signed transaction to a Base64 string for broadcast via GCloud.
    const serializedTransactionBytes = signedTransaction.serialize();
    const serializedTransactionBase64 = btoa(String.fromCharCode.apply(null, serializedTransactionBytes));
    // ------------------------

    return serializedTransactionBase64;

  } catch (error) {
    console.error("Error signing Solana transaction:", error);
    if (error.code === 4001 || error.message.includes("User rejected")) {
      console.warn("Solflare user rejected the transaction.");
    }
    return null;
  }
}

// Helper to format large numbers to standard display (e.g., 1000000 -> 1,000,000)
// Not used in this file but kept for consistency
function formatNumber(number) {
    const formatted = new Intl.NumberFormat('en-US', {
        minimumFractionDigits: 0,
        maximumFractionDigits: 9,
    }).format(number);
    return formatted.replace(/\.?0+$/, '');
}
