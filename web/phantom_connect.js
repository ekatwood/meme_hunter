async function connectPhantom() {
    //console.log("connectPhantom()");

    if (!window.solana) {
        //console.error("Error connecting Phantom Wallet.");
        return "Please make sure Phantom Wallet browser extension is installed.";
    }

    // Connect to Phantom
    const resp = await window.solana.connect();
    const publicKey = resp.publicKey.toString();

    return publicKey;
}