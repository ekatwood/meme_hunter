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
