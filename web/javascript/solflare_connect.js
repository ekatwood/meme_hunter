async function connectSolflare() {
  try {
    if (!window.solflare) {
      //console.error("Solflare unavailable.");
      return "Solflare unavailable";
    }

    const response = await window.solflare.connect();

    if (response) {
      //console.log(window.solflare.publicKey.toString());
      return window.solflare.publicKey.toString();
    }
  } catch (error) {
    //console.error("Error connecting to Solflare: ", error);
    return "Solflare unavailable";
  }
}

async function isSolflareConnected() {
  try {
    if (window.solflare) {
      const connected = window.solflare.isConnected;
      return {
        connected
      };
    } else {
      return {
        connected: false,
        error: "Solflare not available"
      };
    }
  } catch (error) {
    console.error("Error checking connection:", error);
    return {
      connected: false,
      error: error.message || "Failed to check connection"
    };
  }
}

//     async function signTransactionSolflare(transaction) {
//        try {
//          if (window.solflare) {
//            const signedTransaction = await window.solflare.signTransaction(transaction);
//            // Convert the signedTransaction to a plain JavaScript object
//            const signedTransactionObject = {
//                signature: signedTransaction.signature, // Example: adapt as needed
//                // Add other relevant properties from the signedTransaction
//            };
//            return { signedTransaction: signedTransactionObject };
//          } else {
//             return { error: "Solflare not available" };
//          }
//        } catch (error) {
//           console.error("Error signing transaction", error);
//           return { error: error.message || "Failed to sign transaction" };
//        }
//     }
//
//     async function signAndSendTransactionSolflare(transaction) {
//       try {
//         if (window.solflare) {
//           const signature = await window.solflare.signAndSendTransaction(transaction);
//           return { signature };
//         } else {
//           return { error: "Solflare not available" };
//         }
//
//       } catch (error) {
//         console.error("Error signing and sending transaction", error);
//         return { error: error.message || "Failed to sign and send transaction" };
//       }
//     }
//
//      async function signMessageSolflare(message) {
//        try {
//          if (window.solflare) {
//            const signedMessage = await window.solflare.signMessage(message);
//             // Convert the Uint8Array to a plain JavaScript array
//            const signedMessageArray = Array.from(signedMessage);
//            return { signedMessage: signedMessageArray };
//          } else {
//            return { error: "Solflare not available" };
//          }
//        } catch (error) {
//          console.error("Error signing message", error);
//          return { error: error.message || "Failed to sign message" };
//        }
//      }

     window.connectSolflare = connectSolflare;
     window.disconnectSolflare = disconnectSolflare;
     window.isSolflareConnected = isSolflareConnected;
//     window.signTransactionSolflare = signTransactionSolflare;
//     window.signAndSendTransactionSolflare = signAndSendTransactionSolflare;
//     window.signMessageSolflare = signMessageSolflare;