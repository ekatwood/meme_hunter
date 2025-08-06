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
