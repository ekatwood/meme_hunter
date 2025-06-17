async function connectMetaMask() {
  try {
    if (typeof window.ethereum === 'undefined') {
      //console.error("MetaMask not available.");
      return "MetaMask unavailable";
    }

    // 1. Request accounts to ensure wallet is connected
    const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
    const address = accounts[0];
    //console.log("MetaMask connected, address:", address);

    // Arbitrum One Chain ID (in hexadecimal)
    const ARBITRUM_CHAIN_ID = '0xa4b1'; // 42161 in decimal

    // Arbitrum One Network Details for adding the chain
    const ARBITRUM_NETWORK_DETAILS = {
      chainId: ARBITRUM_CHAIN_ID,
      chainName: 'Arbitrum One',
      rpcUrls: ['https://arb1.arbitrum.io/rpc'], // You can add more RPCs if needed
      nativeCurrency: {
        name: 'Ether',
        symbol: 'ETH', // Arbitrum uses ETH for gas
        decimals: 18,
      },
      blockExplorerUrls: ['https://arbiscan.io/'],
    };

    // 2. Get current chain ID
    let currentChainId = await window.ethereum.request({ method: 'eth_chainId' });
    //console.log("Current MetaMask Chain ID:", currentChainId);

    // 3. Check if on Arbitrum network
    if (currentChainId !== ARBITRUM_CHAIN_ID) {
      console.log("Switching or adding Arbitrum network...");
      try {
        // Try to switch to Arbitrum
        await window.ethereum.request({
          method: 'wallet_switchEthereumChain',
          params: [{ chainId: ARBITRUM_CHAIN_ID }],
        });
        console.log("Successfully switched to Arbitrum One.");
      } catch (switchError) {
        // This error indicates the chain might not be added yet (code 4902)
        if (switchError.code === 4902) {
          console.log("Arbitrum network not found, attempting to add it...");
          try {
            await window.ethereum.request({
              method: 'wallet_addEthereumChain',
              params: [ARBITRUM_NETWORK_DETAILS],
            });
            console.log("Arbitrum One added and switched successfully.");
          } catch (addError) {
            console.error("Failed to add Arbitrum network:", addError);
            if (addError.code === 4001) {
                return "User rejected";
            }
            return "MetaMask unavailable";
          }
        } else if (switchError.code === 4001) {
            return "User rejected";
        } else {
            console.error("Failed to switch network:", switchError);
            return "MetaMask unavailable";
        }
      }
      // Re-check chain ID after switch/add attempt
      currentChainId = await window.ethereum.request({ method: 'eth_chainId' });
      //console.log("currentChainId: " + currentChainId.toString());
      if (currentChainId !== ARBITRUM_CHAIN_ID) {
          console.error("Still not on Arbitrum One after attempt.");
          return "MetaMask unavailable";
      }
    }

    // If we reach here, the wallet is connected and on Arbitrum One
    return address;
  } catch (error) {
    console.error("Error connecting to MetaMask:", error);
    // Handle user rejection (error code 4001) specifically
    if (error.code === 4001) {
      return "User rejected";
    }
    return "MetaMask unavailable"; // Generic error for other issues
  }
}