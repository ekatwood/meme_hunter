async function connectSolflare() {
  try {
    if (!window.solflare) {
      //console.error("Solflare unavailable.");
      return "Solflare unavailable";
    }

    const response = await window.solflare.connect();

    if (response) {
      // TODO: use the SOL amount in the app
      getBalanceSolflare(window.solflare.publicKey.toString(), null);
      return window.solflare.publicKey.toString();
    }
  } catch (error) {
    //console.error("Error connecting to Solflare: ", error);
    return "Solflare unavailable";
  }
}

const RPC_URL = "xx";
async function getBalanceSolflare(walletAddress, contractAddress) {
  try {
    const connection = new solanaWeb3.Connection(RPC_URL, 'confirmed');
    const publicKey = new solanaWeb3.PublicKey(walletAddress);

    if (!contractAddress) {
      // Case 1: Fetch native SOL balance
      const balanceInLamports = await connection.getBalance(publicKey);
      return balanceInLamports / solanaWeb3.LAMPORTS_PER_SOL;
    } else {
      // Case 2: Fetch SPL token balance using getParsedTokenAccountsByOwner
      const tokenMintAddress = new solanaWeb3.PublicKey(contractAddress);
      const tokenAccounts = await connection.getParsedTokenAccountsByOwner(
        publicKey,
        { programId: new solanaWeb3.PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA") }
      );
      // Find the correct token account for the given mint address
      const tokenAccount = tokenAccounts.value.find(
        (account) => account.account.data.parsed.info.mint === tokenMintAddress.toString()
      );
      if (tokenAccount) {
        return tokenAccount.account.data.parsed.info.tokenAmount.uiAmount;
      } else {
        console.warn("No token account found for the provided mint address.");
        return 0; // Return 0 if no token account is found
      }
    }
  } catch (error) {
    console.error("Error fetching balance:", error);
    return null;
  }
}