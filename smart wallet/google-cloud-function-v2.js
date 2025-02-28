// Google Cloud Function (Node.js) to perform automated token purchases with USDC
const { Connection, PublicKey, Transaction, sendAndConfirmTransaction } = require('@solana/web3.js');
const { TokenSwap } = require('@solana/spl-token-swap');
const { Token, TOKEN_PROGRAM_ID } = require('@solana/spl-token');
const fetch = require('node-fetch');
const bs58 = require('bs58');
const nodemailer = require('nodemailer');

// These would be set as environment variables in Cloud Functions
const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY; // Private key for the external authority
const SMART_WALLET_PROGRAM_ID = process.env.SMART_WALLET_PROGRAM_ID;
const SMART_WALLET_ADDRESS = process.env.SMART_WALLET_ADDRESS;
const RAYDIUM_SWAP_PROGRAM_ID = process.env.RAYDIUM_SWAP_PROGRAM_ID;
const RPC_ENDPOINT = process.env.SOLANA_RPC_ENDPOINT || 'https://api.mainnet-beta.solana.com';
const EMAIL_SERVICE = process.env.EMAIL_SERVICE || 'gmail';
const EMAIL_USER = process.env.EMAIL_USER;
const EMAIL_PASS = process.env.EMAIL_PASS;
const EMAIL_FROM = process.env.EMAIL_FROM || 'crypto-wallet@example.com';

// Raydium API endpoint for trending tokens
const RAYDIUM_API_ENDPOINT = 'https://api.raydium.io/v2/main/pairs';

/**
 * Google Cloud Function that runs every hour to purchase trending tokens with USDC
 */
exports.automaticTokenPurchase = async (req, res) => {
  try {
    console.log('Starting automatic token purchase...');
    
    // Initialize Solana connection
    const connection = new Connection(RPC_ENDPOINT, 'confirmed');
    
    // Initialize wallet from private key
    const wallet = loadWalletFromPrivateKey(PRIVATE_KEY);
    
    // Get wallet data
    const walletData = await getWalletData(connection, new PublicKey(SMART_WALLET_ADDRESS));
    console.log('Wallet settings:', {
      incrementAmount: walletData.incrementAmount / 1_000_000, // Convert to USDC
      maxTokensPerRun: walletData.maxTokensPerRun,
      emailNotifications: walletData.emailNotifications,
    });
    
    // Get wallet USDC balance
    const usdcBalance = await getUSDCBalance(
      connection, 
      new PublicKey(SMART_WALLET_ADDRESS),
      walletData.usdcTokenMint
    );
    console.log(`Current USDC balance: ${usdcBalance / 1_000_000} USDC`);
    
    // Get trending tokens from Raydium API
    const trendingTokens = await getTrendingTokens(30); // Get top 30 to have options
    console.log(`Found ${trendingTokens.length} trending tokens`);
    
    // Check if balance is sufficient for at least one purchase
    const lowBalance = usdcBalance < walletData.incrementAmount;
    
    if (lowBalance) {
      console.log('Insufficient USDC balance for purchases');
      
      // Send low balance notification if notifications are enabled and not already sent
      if (walletData.emailNotifications && !walletData.lowBalanceNotified) {
        await sendLowBalanceEmail(
          walletData.userEmail, 
          usdcBalance / 1_000_000, 
          walletData.incrementAmount / 1_000_000
        );
        
        // Update the low balance notification flag
        await updateLowBalanceFlag(connection, wallet, true);
      }
      
      res.status(200).send({
        success: false,
        timestamp: new Date().toISOString(),
        message: 'Insufficient USDC balance for purchases',
        currentBalance: usdcBalance / 1_000_000,
        requiredBalance: walletData.incrementAmount / 1_000_000,
      });
      return;
    }
    
    // Determine how many tokens we can buy with our available balance
    const numTokensToBuy = Math.min(
      Math.floor(usdcBalance / walletData.incrementAmount),
      Math.min(trendingTokens.length, walletData.maxTokensPerRun)
    );
    
    console.log(`Will purchase ${numTokensToBuy} tokens with ${walletData.incrementAmount / 1_000_000} USDC each`);
    
    // Only use the tokens we're going to buy
    const selectedTokens = trendingTokens.slice(0, numTokensToBuy);
    
    // Execute the purchase transaction
    const result = await executePurchases(
      connection, 
      wallet, 
      selectedTokens,
      walletData.incrementAmount
    );
    
    // Check if remaining balance is below the increment amount
    const remainingBalance = usdcBalance - (numTokensToBuy * walletData.incrementAmount);
    const willBecomeLowBalance = remainingBalance < walletData.incrementAmount;
    
    if (willBecomeLowBalance && numTokensToBuy > 0) {
      console.log('Remaining balance will be below the increment amount after purchases');
      
      // Send low balance notification if notifications are enabled and not already sent
      if (walletData.emailNotifications && !walletData.lowBalanceNotified) {
        await sendLowBalanceEmail(
          walletData.userEmail, 
          remainingBalance / 1_000_000, 
          walletData.incrementAmount / 1_000_000
        );
        
        // Update the low balance notification flag
        await updateLowBalanceFlag(connection, wallet, true);
      }
    }
    
    // Return results
    res.status(200).send({
      success: true,
      timestamp: new Date().toISOString(),
      purchases: numTokensToBuy,
      purchaseIncrement: walletData.incrementAmount / 1_000_000,
      initialBalance: usdcBalance / 1_000_000,
      remainingBalance: remainingBalance / 1_000_000,
      txId: result?.txId || null,
      tokens: selectedTokens.map(t => t.toString())
    });
  } catch (error) {
    console.error('Error in automatic token purchase:', error);
    res.status(500).send({
      success: false,
      error: error.message
    });
  }
};

/**
 * Load wallet from private key
 */
function loadWalletFromPrivateKey(privateKeyString) {
  const decodedKey = bs58.decode(privateKeyString);
  return {
    publicKey: new PublicKey(bs58.encode(decodedKey.slice(0, 32))),
    secretKey: decodedKey
  };
}

/**
 * Get wallet data from the smart wallet account
 * This is a placeholder - in a real implementation, you'd deserialize 
 * the actual account data using Borsh or another serialization format
 */
async function getWalletData(connection, walletAddress) {
  // In a real implementation, you'd fetch the account and deserialize it
  // For this example, we'll return placeholder data
  
  // Fetch account data
  const accountInfo = await connection.getAccountInfo(walletAddress);
  if (!accountInfo) {
    throw new Error('Wallet account not found');
  }
  
  // This would be replaced with proper deserialization
  return {
    incrementAmount: 20_000_000, // 20 USDC with 6 decimals
    maxTokensPerRun: 5,
    emailNotifications: true,
    userEmail: 'user@example.com',
    lowBalanceNotified: false,
    usdcTokenMint: new PublicKey('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v') // Mainnet USDC
  };
}

/**
 * Get USDC balance for the wallet
 */
async function getUSDCBalance(connection, walletAddress, usdcMint) {
  try {
    // Find the associated token account
    const tokenAccount = await Token.getAssociatedTokenAddress(
      new PublicKey('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL'), // SPL-TOKEN ASSOCIATED PROGRAM ID
      TOKEN_PROGRAM_ID,
      usdcMint,
      walletAddress,
      true // Allow ownerless account
    );
    
    // Get token account info
    const tokenAccountInfo = await connection.getAccountInfo(tokenAccount);
    if (!tokenAccountInfo) {
      return 0; // No token account exists yet
    }
    
    // Deserialize and return balance
    // In a real implementation, you'd use proper deserialization
    // This is a simplified version
    return 100_000_000; // Placeholder for 100 USDC
  } catch (error) {
    console.error('Error getting USDC balance:', error);
    return 0;
  }
}

/**
 * Get list of trending tokens from Raydium API
 */
async function getTrendingTokens(limit = 30) {
  try {
    const response = await fetch(RAYDIUM_API_ENDPOINT);
    const data = await response.json();
    
    // Filter for liquid pairs and sort by volume
    const sortedPairs = data
      .filter(pair => 
        pair.liquidity > 50000 && // Only pairs with significant liquidity
        pair.volume24h > 10000    // Only pairs with sufficient trading volume
      )
      .sort((a, b) => b.volume24h - a.volume24h); // Sort by 24h volume
    
    // Extract token mints from pairs
    const tokenMints = sortedPairs.slice(0, limit).map(pair => new PublicKey(pair.baseMint));
    
    return tokenMints;
  } catch (error) {
    console.error('Error fetching trending tokens:', error);
    throw error;
  }
}

/**
 * Execute token purchases using the smart wallet contract
 */
async function executePurchases(connection, wallet, tokenMints, incrementAmount) {
  if (tokenMints.length === 0) {
    return { success: false, message: 'No tokens to purchase' };
  }
  
  const smartWalletProgram = new Public