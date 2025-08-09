async function connectMetaMask() {
  try {
    // Check if MetaMask is available in the browser
    if (typeof window.ethereum === 'undefined') {
      console.error("MetaMask not available.");
      return "MetaMask unavailable";
    }

    // Request accounts to ensure the wallet is connected and get the user's address
    // This will prompt the user to connect their MetaMask wallet if they haven't already.
    const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });

    // If accounts are successfully retrieved, return the first address
    if (accounts.length > 0) {
      const address = accounts[0];
      console.log("MetaMask connected, address:", address);

      return address;
    } else {
      // This case should ideally not be reached if eth_requestAccounts succeeds but returns no accounts
      console.error("No accounts found after MetaMask connection request.");
      return "MetaMask unavailable";
    }

  } catch (error) {
    // Log the error for debugging purposes
    console.error("Error connecting to MetaMask:", error);

    // Handle specific error codes
    if (error.code === 4001) {
      // User rejected the connection request
      return "User rejected";
    }
    // For any other errors, return a generic "MetaMask unavailable" message
    return "MetaMask unavailable";
  }
}

// WETH: 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
async function getBalanceMetaMask(walletAddress, contractAddress) {
  // Check if ethers (v6) is available globally
  // Now, 'ethers' should be directly available from the UMD build
  if (typeof ethers === 'undefined') {
    console.error("Ethers.js v6 library not found. Ensure the UMD CDN is loaded correctly.");
    return null;
  }

  // Check if MetaMask (window.ethereum) is available
  if (typeof window.ethereum === 'undefined') {
    console.error("MetaMask is not installed or detected.");
    return null;
  }

  try {
    // V6 change: Use BrowserProvider for interacting with window.ethereum
    // 'ethers' is now globally available
    const provider = new ethers.BrowserProvider(window.ethereum);

    // The minimum ABI required to get the ERC-20 token balance and decimals
    const minABI = [
      // balanceOf
      {
        "inputs": [{ "internalType": "address", "name": "account", "type": "address" }],
        "name": "balanceOf",
        "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }],
        "stateMutability": "view",
        "type": "function"
      },
      // decimals (optional, but highly recommended for correct formatting)
      {
        "inputs": [],
        "name": "decimals",
        "outputs": [{ "internalType": "uint8", "name": "", "type": "uint8" }],
        "stateMutability": "view",
        "type": "function"
      }
    ];

    // Create a contract instance
    // V6 change: Contract constructor takes (address, abi, provider/signer)
    // 'ethers' is now globally available
    const tokenContract = new ethers.Contract(contractAddress, minABI, provider);

    // Get the raw balance (as a BigNumber)
    const balanceBigNumber = await tokenContract.balanceOf(walletAddress);

    // Get the number of decimals for the token
    const decimalsBigInt = await tokenContract.decimals();
    const decimals = Number(decimalsBigInt);

    // Format the balance using the token's decimals
    const formattedBalance = formatBigIntWithDecimals(balanceBigNumber, decimals);

    console.log("WETH amount:", formattedBalance);
    return formattedBalance;

  } catch (error) {
    console.error("Error retrieving token balance:", error);
    // Handle specific errors, e.g., user denied access
    if (error.code === 4001) {
      console.warn("User rejected the connection request.");
    }
    return null;
  }
}

function formatBigIntWithDecimals(rawBigIntValue, decimals) {
  // Convert the BigInt to a string
  let strValue = rawBigIntValue.toString();

  // Handle cases where the value is too short for the decimals
  // Pad with leading zeros if necessary
  if (strValue.length <= decimals) {
    strValue = '0'.repeat(decimals - strValue.length + 1) + strValue;
  }

  // Calculate the position for the decimal point
  const decimalPointPosition = strValue.length - decimals;

  // Insert the decimal point
  const formatted = strValue.substring(0, decimalPointPosition) + '.' + strValue.substring(decimalPointPosition);

  // Remove trailing zeros after the decimal point if any (optional, for cleaner output)
  // This step is important for numbers like "1.000000000" to become "1"
  return formatted.replace(/\.?0+$/, '');
}