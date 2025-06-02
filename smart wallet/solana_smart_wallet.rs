// Enhanced Solana smart wallet program with USDC-based token purchases
use solana_program::{
    account_info::{next_account_info, AccountInfo},
    entrypoint,
    entrypoint::ProgramResult,
    msg,
    program_error::ProgramError,
    pubkey::Pubkey,
    program::{invoke, invoke_signed},
    system_instruction,
    sysvar::{rent::Rent, Sysvar},
    borsh::try_from_slice_unchecked, // For deserializing instruction data
    program_pack::{IsInitialized, Pack, Sealed}, // For account state management
};
use spl_token::state::{Account as TokenAccount, Mint as TokenMint}; // For SPL token account state
use borsh::{BorshDeserialize, BorshSerialize}; // For state and instruction serialization
use std::convert::TryInto;

// Define custom program errors
#[derive(Debug, PartialEq, Eq)]
pub enum SmartWalletError {
    #[error("Account not initialized")]
    UninitializedAccount,
    #[error("Invalid account owner")]
    InvalidAccountOwner,
    #[error("Missing required signature")]
    MissingRequiredSignature,
    #[error("Invalid instruction data")]
    InvalidInstructionData,
    #[error("Insufficient funds")]
    InsufficientFunds,
    #[error("Owner does not match")]
    OwnerMismatch,
    #[error("Authority does not match")]
    AuthorityMismatch,
    #[error("Wallet account already initialized")]
    AlreadyInitialized,
    #[error("Account not rent exempt")]
    NotRentExempt,
    #[error("Invalid token program")]
    InvalidTokenProgram,
    #[error("Invalid token mint")]
    InvalidTokenMint,
    #[error("Invalid Associated Token Account")]
    InvalidAssociatedTokenAccount,
}

impl From<SmartWalletError> for ProgramError {
    fn from(e: SmartWalletError) -> Self {
        ProgramError::Custom(e as u32)
    }
}

// Define our program's state struct
// Added `#[derive(BorshSerialize, BorshDeserialize, Debug, PartialEq)]` for easy serialization
// and comparison, useful for testing and Python interoperability.
#[derive(BorshSerialize, BorshDeserialize, Debug, PartialEq)]
pub struct SmartWallet {
    pub is_initialized: bool, // Flag to indicate if the account has been initialized
    pub owner: Pubkey,
    pub authority_bump_seed: u8,
    pub authority_pubkey: Pubkey, // PDA for the wallet's control
    pub is_active: bool,
    pub external_authority: Option<Pubkey>, // Optional external authority (e.g., Cloud Function)
    pub usdc_token_mint: Pubkey, // The Pubkey of the USDC token mint
    pub increment_amount: u64,  // Amount in USDC (scaled by decimals, e.g., 20_000_000 for 20 USDC)
    pub max_tokens_per_run: u8, // Maximum number of tokens to buy in a single run
    pub email_notifications: bool,
    pub user_email: String,
    pub low_balance_notified: bool,
}

// Implement `Sealed` and `IsInitialized` for the SmartWallet struct
// `Sealed` is a marker trait that ensures the type can be packed.
impl Sealed for SmartWallet {}

// `IsInitialized` trait indicates whether the account has been initialized.
impl IsInitialized for SmartWallet {
    fn is_initialized(&self) -> bool {
        self.is_initialized
    }
}

// Implement `Pack` for the SmartWallet struct to manage account data.
// This defines how the struct is serialized into and deserialized from a byte slice.
impl Pack for SmartWallet {
    // Defines the fixed size of the serialized SmartWallet struct.
    // This size must be carefully calculated based on the types within the struct.
    // bool (1) + Pubkey (32) + u8 (1) + Pubkey (32) + bool (1) + Option<Pubkey> (1 + 32) + Pubkey (32) + u64 (8) + u8 (1) + bool (1) + String (max 255 bytes + 4 bytes for length) + bool (1)
    // For String, we need a fixed-size buffer or a length prefix + max size.
    // Let's assume a max email length of 100 bytes for simplicity, plus 4 bytes for length prefix.
    // Total: 1 + 32 + 1 + 32 + 1 + (1 + 32) + 32 + 8 + 1 + 1 + (4 + 100) + 1 = 246 bytes
    // For Option<Pubkey>, it's 1 byte for the discriminant (Some/None) + 32 bytes for the Pubkey if Some.
    // So, 1 + 32 + 1 + 32 + 1 + 33 + 32 + 8 + 1 + 1 + 104 + 1 = 247 bytes
    // Let's round up to a safe size, e.g., 256 bytes, or define a precise max for String.
    // For a fixed-size string, it's better to use an array like [u8; MAX_EMAIL_LEN] and store actual length.
    // For simplicity and to match Borsh's dynamic string serialization, we'll use a larger fixed size
    // and rely on the client to provide a reasonable email length.
    // A more robust solution would be to use a fixed-size byte array for the email and track its length.
    // For now, let's calculate based on the maximum possible size of the String (4 bytes length + max 255 content)
    // Let's set a max email length to avoid dynamic sizing issues with Pack.
    // If we use Borsh's default String serialization, it's a u32 length prefix + bytes.
    // So, for Pack, we need to decide on a max length. Let's say max 100 chars for email.
    // 1 (is_initialized) + 32 (owner) + 1 (bump) + 32 (authority) + 1 (is_active) + 33 (external_authority) + 32 (usdc_mint) + 8 (increment) + 1 (max_tokens) + 1 (email_notifications) + 4 (email_len) + 100 (email_data) + 1 (low_balance_notified)
    // = 1 + 32 + 1 + 32 + 1 + 33 + 32 + 8 + 1 + 1 + 4 + 100 + 1 = 247 bytes.
    // Let's make it 256 for alignment and safety for now.
    const LEN: usize = 256; // A sufficiently large size for the SmartWallet struct.
                            // In a real app, calculate precisely or use a fixed-size string buffer.

    // Packs the SmartWallet struct into a mutable byte slice.
    fn pack_into_slice(&self, dst: &mut [u8]) {
        let encoded = self.try_to_vec().expect("Failed to serialize SmartWallet");
        dst[..encoded.len()].copy_from_slice(&encoded);
        // Pad the rest with zeros if necessary (Pack requires fixed size)
        dst[encoded.len()..].fill(0);
    }

    // Unpacks a SmartWallet struct from a byte slice.
    fn unpack_from_slice(src: &[u8]) -> Result<Self, ProgramError> {
        // Use Borsh to deserialize from the slice.
        // This assumes the entire slice contains the serialized data.
        SmartWallet::try_from_slice(src)
            .map_err(|_| ProgramError::InvalidAccountData)
    }
}


// Define instruction types with updated functionality
// #[derive(BorshSerialize, BorshDeserialize)] for easy instruction data handling
#[derive(BorshSerialize, BorshDeserialize, Debug, PartialEq)]
pub enum SmartWalletInstruction {
    /// Initialize a new smart wallet
    /// Accounts:
    /// 0. `[signer]` Funding account (must be wallet owner)
    /// 1. `[writable]` New wallet account (PDA, owned by program)
    /// 2. `[]` USDC token mint (e.g., EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v)
    /// 3. `[]` System Program
    Initialize {
        increment_amount: u64,
        max_tokens_per_run: u8,
        email: String,
        enable_notifications: bool,
    },

    /// Deposit USDC into wallet
    /// Accounts:
    /// 0. `[signer]` Source owner
    /// 1. `[writable]` Source USDC account (ATA of source owner)
    /// 2. `[writable]` Wallet USDC account (ATA of wallet PDA)
    /// 3. `[]` Token program (spl-token program ID)
    DepositUSDC { amount: u64 },

    /// Withdraw USDC from wallet
    /// Accounts:
    /// 0. `[signer]` Owner (must be the wallet owner)
    /// 1. `[writable]` Wallet account (PDA, owned by program)
    /// 2. `[writable]` Wallet USDC account (ATA of wallet PDA)
    /// 3. `[writable]` Destination USDC account (ATA of owner)
    /// 4. `[]` Token program (spl-token program ID)
    WithdrawUSDC { amount: u64 },

    /// Update wallet settings
    /// Accounts:
    /// 0. `[signer]` Owner (must be the wallet owner)
    /// 1. `[writable]` Wallet account (PDA, owned by program)
    UpdateSettings {
        increment_amount: Option<u64>,
        max_tokens_per_run: Option<u8>,
        email: Option<String>,
        enable_notifications: Option<bool>,
    },

    /// Authorize an external authority (e.g., cloud function wallet)
    /// Accounts:
    /// 0. `[signer]` Owner (must be the wallet owner)
    /// 1. `[writable]` Wallet account (PDA, owned by program)
    /// 2. `[]` New external authority Pubkey
    AuthorizeExternal,

    /// Execute token purchases
    /// Accounts:
    /// 0. `[signer]` Authority (owner or external authority)
    /// 1. `[writable]` Wallet account (PDA, owned by program)
    /// 2. `[writable]` Wallet USDC account (ATA of wallet PDA)
    /// 3. `[]` Token program (spl-token program ID)
    /// 4. `[]` (Optional, if needed for Raydium simulation) Dummy account for Raydium program ID
    /// 5+ `[writable]` (Optional, if needed for Raydium simulation) Dummy accounts for Raydium pools/mints/etc.
    ///    Note: In a real Raydium integration, this list would be extensive and specific to the swap.
    PurchaseTokens { token_mints: Vec<Pubkey> },

    /// Reset low balance notification flag
    /// Accounts:
    /// 0. `[signer]` Authority (owner or external authority)
    /// 1. `[writable]` Wallet account (PDA, owned by program)
    ResetLowBalanceFlag,
}

// Program entry point
entrypoint!(process_instruction);

// Process instructions
fn process_instruction(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    instruction_data: &[u8],
) -> ProgramResult {
    // Deserialize the instruction data using Borsh
    let instruction = SmartWalletInstruction::try_from_slice(instruction_data)
        .map_err(|_| ProgramError::InvalidInstructionData)?;

    // Process the instruction
    match instruction {
        SmartWalletInstruction::Initialize { increment_amount, max_tokens_per_run, email, enable_notifications } => {
            msg!("Instruction: Initialize");
            initialize(program_id, accounts, increment_amount, max_tokens_per_run, email, enable_notifications)
        },
        SmartWalletInstruction::DepositUSDC { amount } => {
            msg!("Instruction: DepositUSDC");
            deposit_usdc(program_id, accounts, amount)
        },
        SmartWalletInstruction::WithdrawUSDC { amount } => {
            msg!("Instruction: WithdrawUSDC");
            withdraw_usdc(program_id, accounts, amount)
        },
        SmartWalletInstruction::UpdateSettings { increment_amount, max_tokens_per_run, email, enable_notifications } => {
            msg!("Instruction: UpdateSettings");
            update_settings(program_id, accounts, increment_amount, max_tokens_per_run, email, enable_notifications)
        },
        SmartWalletInstruction::AuthorizeExternal => {
            msg!("Instruction: AuthorizeExternal");
            authorize_external(program_id, accounts)
        },
        SmartWalletInstruction::PurchaseTokens { token_mints } => {
            msg!("Instruction: PurchaseTokens");
            purchase_tokens(program_id, accounts, token_mints)
        },
        SmartWalletInstruction::ResetLowBalanceFlag => {
            msg!("Instruction: ResetLowBalanceFlag");
            reset_low_balance_flag(program_id, accounts)
        },
    }
}

// Helper function to load and validate the wallet account
fn get_and_validate_wallet_account<'a>(
    program_id: &Pubkey,
    wallet_account_info: &'a AccountInfo,
) -> Result<SmartWallet, ProgramError> {
    if wallet_account_info.owner != program_id {
        return Err(SmartWalletError::InvalidAccountOwner.into());
    }
    let wallet_data = SmartWallet::unpack(&wallet_account_info.data.borrow())?;
    if !wallet_data.is_initialized() {
        return Err(SmartWalletError::UninitializedAccount.into());
    }
    Ok(wallet_data)
}

// Initialize a new smart wallet with USDC settings
fn initialize(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    increment_amount: u64,
    max_tokens_per_run: u8,
    email: String,
    enable_notifications: bool,
) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let funder = next_account_info(account_info_iter)?;
    let wallet_account = next_account_info(account_info_iter)?;
    let usdc_mint = next_account_info(account_info_iter)?;
    let system_program = next_account_info(account_info_iter)?; // System program for rent check

    // Verify the funder is a signer
    if !funder.is_signer {
        return Err(SmartWalletError::MissingRequiredSignature.into());
    }

    // Verify wallet account is not already initialized
    if wallet_account.owner == program_id && wallet_account.data_len() > 0 {
        let existing_wallet = SmartWallet::unpack_from_slice(&wallet_account.data.borrow())?;
        if existing_wallet.is_initialized() {
            return Err(SmartWalletError::AlreadyInitialized.into());
        }
    }

    // Create the wallet PDA (Program Derived Address)
    let (authority_pubkey, authority_bump_seed) = Pubkey::find_program_address(
        &[b"wallet", funder.key.as_ref()], // Seed based on "wallet" and owner's pubkey
        program_id,
    );

    // Check if the provided wallet_account matches the derived PDA
    if *wallet_account.key != authority_pubkey {
        msg!("Provided wallet account key: {}", wallet_account.key);
        msg!("Derived PDA authority key: {}", authority_pubkey);
        return Err(ProgramError::InvalidSeeds); // Or a more specific error
    }

    // Ensure the wallet account has enough space and is rent-exempt
    let rent = &Rent::from_account_info(next_account_info(account_info_iter)?)?; // Rent sysvar
    if !rent.is_exempt(wallet_account.lamports(), SmartWallet::LEN) {
        return Err(SmartWalletError::NotRentExempt.into());
    }

    // Initialize wallet data
    let wallet_data = SmartWallet {
        is_initialized: true,
        owner: *funder.key,
        authority_bump_seed,
        authority_pubkey,
        is_active: true, // Wallet is active upon creation
        external_authority: None, // No external authority initially
        usdc_token_mint: *usdc_mint.key,
        increment_amount,
        max_tokens_per_run,
        email_notifications: enable_notifications,
        user_email: email,
        low_balance_notified: false,
    };

    // Pack and store the wallet data into the wallet account
    SmartWallet::pack(wallet_data, &mut wallet_account.data.borrow_mut())?;

    msg!("Smart wallet initialized for owner {} with PDA {} and USDC increment: {} and max tokens: {}",
         funder.key, authority_pubkey, increment_amount, max_tokens_per_run);

    Ok(())
}

// Deposit USDC into wallet
fn deposit_usdc(program_id: &Pubkey, accounts: &[AccountInfo], amount: u64) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let source_owner = next_account_info(account_info_iter)?;
    let source_usdc = next_account_info(account_info_iter)?;
    let wallet_usdc = next_account_info(account_info_iter)?;
    let token_program = next_account_info(account_info_iter)?;
    let wallet_account = next_account_info(account_info_iter)?; // Wallet account to update state

    // Verify the source owner is a signer
    if !source_owner.is_signer {
        return Err(SmartWalletError::MissingRequiredSignature.into());
    }

    // Verify token program is the SPL Token program
    if token_program.key != &spl_token::id() {
        return Err(SmartWalletError::InvalidTokenProgram.into());
    }

    // Deserialize wallet account and update low_balance_notified flag
    let mut wallet_data = get_and_validate_wallet_account(program_id, wallet_account)?;

    // Basic check: Ensure source_usdc is an ATA of source_owner
    let source_usdc_account_data = TokenAccount::unpack(&source_usdc.data.borrow())?;
    if source_usdc_account_data.owner != *source_owner.key {
        return Err(SmartWalletError::InvalidAssociatedTokenAccount.into());
    }
    if source_usdc_account_data.mint != wallet_data.usdc_token_mint {
        return Err(SmartWalletError::InvalidTokenMint.into());
    }

    // Basic check: Ensure wallet_usdc is an ATA of the wallet PDA
    let wallet_usdc_account_data = TokenAccount::unpack(&wallet_usdc.data.borrow())?;
    if wallet_usdc_account_data.owner != wallet_data.authority_pubkey {
        return Err(SmartWalletError::InvalidAssociatedTokenAccount.into());
    }
    if wallet_usdc_account_data.mint != wallet_data.usdc_token_mint {
        return Err(SmartWalletError::InvalidTokenMint.into());
    }

    // Create the transfer instruction for SPL tokens
    let transfer_ix = spl_token::instruction::transfer(
        token_program.key,
        source_usdc.key,
        wallet_usdc.key,
        source_owner.key,
        &[], // No signers for the source_owner, as it's provided directly
        amount,
    )?;

    // Execute the transfer
    invoke(
        &transfer_ix,
        &[
            source_usdc.clone(),
            wallet_usdc.clone(),
            source_owner.clone(),
            token_program.clone(),
        ],
    )?;

    // Reset the low balance notification flag when new funds are added
    wallet_data.low_balance_notified = false;
    SmartWallet::pack(wallet_data, &mut wallet_account.data.borrow_mut())?;

    msg!("Deposited {} USDC into wallet. Low balance flag reset.", amount);
    Ok(())
}

// Withdraw USDC from wallet
fn withdraw_usdc(program_id: &Pubkey, accounts: &[AccountInfo], amount: u64) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let owner = next_account_info(account_info_iter)?;
    let wallet_account = next_account_info(account_info_iter)?; // Wallet account (PDA)
    let wallet_usdc = next_account_info(account_info_iter)?; // Wallet's USDC ATA
    let destination_usdc = next_account_info(account_info_iter)?; // Destination USDC ATA
    let token_program = next_account_info(account_info_iter)?; // SPL Token Program

    // Verify owner is a signer
    if !owner.is_signer {
        return Err(SmartWalletError::MissingRequiredSignature.into());
    }

    // Deserialize wallet account and verify ownership
    let wallet_data = get_and_validate_wallet_account(program_id, wallet_account)?;
    if wallet_data.owner != *owner.key {
        return Err(SmartWalletError::OwnerMismatch.into());
    }

    // Verify token program is the SPL Token program
    if token_program.key != &spl_token::id() {
        return Err(SmartWalletError::InvalidTokenProgram.into());
    }

    // Basic check: Ensure wallet_usdc is an ATA of the wallet PDA
    let wallet_usdc_account_data = TokenAccount::unpack(&wallet_usdc.data.borrow())?;
    if wallet_usdc_account_data.owner != wallet_data.authority_pubkey {
        return Err(SmartWalletError::InvalidAssociatedTokenAccount.into());
    }
    if wallet_usdc_account_data.mint != wallet_data.usdc_token_mint {
        return Err(SmartWalletError::InvalidTokenMint.into());
    }
    if wallet_usdc_account_data.amount < amount {
        return Err(SmartWalletError::InsufficientFunds.into());
    }

    // Basic check: Ensure destination_usdc is an ATA for the owner and correct mint
    let destination_usdc_account_data = TokenAccount::unpack(&destination_usdc.data.borrow())?;
    if destination_usdc_account_data.owner != *owner.key {
        return Err(SmartWalletError::InvalidAssociatedTokenAccount.into());
    }
    if destination_usdc_account_data.mint != wallet_data.usdc_token_mint {
        return Err(SmartWalletError::InvalidTokenMint.into());
    }


    // Create the PDA signer seeds
    let wallet_seed = b"wallet";
    let authority_seeds = &[
        wallet_seed,
        owner.key.as_ref(), // Use the owner's key as part of the seed
        &[wallet_data.authority_bump_seed], // Use the stored bump seed
    ];

    // Create the transfer instruction for SPL tokens
    let transfer_ix = spl_token::instruction::transfer(
        token_program.key,
        wallet_usdc.key,
        destination_usdc.key,
        &wallet_data.authority_pubkey, // PDA as the authority
        &[],
        amount,
    )?;

    // Execute the transfer with PDA signing
    invoke_signed(
        &transfer_ix,
        &[
            wallet_usdc.clone(),
            destination_usdc.clone(),
            wallet_account.clone(), // The wallet PDA account must be passed for signing
            token_program.clone(),
        ],
        &[authority_seeds], // Array of signer seed arrays
    )?;

    msg!("Withdrew {} USDC from wallet to {}", amount, destination_usdc.key);
    Ok(())
}

// Update wallet settings
fn update_settings(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    increment_amount: Option<u64>,
    max_tokens_per_run: Option<u8>,
    email: Option<String>,
    enable_notifications: Option<bool>,
) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let owner = next_account_info(account_info_iter)?;
    let wallet_account = next_account_info(account_info_iter)?;

    // Verify owner is a signer
    if !owner.is_signer {
        return Err(SmartWalletError::MissingRequiredSignature.into());
    }

    // Deserialize the wallet data and verify owner
    let mut wallet_data = get_and_validate_wallet_account(program_id, wallet_account)?;
    if wallet_data.owner != *owner.key {
        return Err(SmartWalletError::OwnerMismatch.into());
    }

    // Apply updates from the options
    if let Some(amount) = increment_amount {
        wallet_data.increment_amount = amount;
    }
    if let Some(max_tokens) = max_tokens_per_run {
        wallet_data.max_tokens_per_run = max_tokens;
    }
    if let Some(user_email) = email {
        wallet_data.user_email = user_email;
    }
    if let Some(enable) = enable_notifications {
        wallet_data.email_notifications = enable;
    }

    // Pack the updated wallet data back to the account
    SmartWallet::pack(wallet_data, &mut wallet_account.data.borrow_mut())?;

    msg!("Smart wallet settings updated by owner {}", owner.key);
    Ok(())
}

// Authorize an external wallet (for the Google Cloud Function)
fn authorize_external(program_id: &Pubkey, accounts: &[AccountInfo]) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let owner = next_account_info(account_info_iter)?;
    let wallet_account = next_account_info(account_info_iter)?;
    let external_authority_pubkey = next_account_info(account_info_iter)?; // The Pubkey to authorize

    // Verify owner is a signer
    if !owner.is_signer {
        return Err(SmartWalletError::MissingRequiredSignature.into());
    }

    // Deserialize the wallet data and verify owner
    let mut wallet_data = get_and_validate_wallet_account(program_id, wallet_account)?;
    if wallet_data.owner != *owner.key {
        return Err(SmartWalletError::OwnerMismatch.into());
    }

    // Update the external_authority field
    wallet_data.external_authority = Some(*external_authority_pubkey.key);

    // Pack the updated wallet data back to the account
    SmartWallet::pack(wallet_data, &mut wallet_account.data.borrow_mut())?;

    msg!("Authorized external authority: {} for wallet {}", external_authority_pubkey.key, wallet_account.key);
    Ok(())
}

// Purchase tokens with USDC (Raydium simulation)
fn purchase_tokens(program_id: &Pubkey, accounts: &[AccountInfo], token_mints: Vec<Pubkey>) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let authority = next_account_info(account_info_iter)?; // Signer: owner or external authority
    let wallet_account = next_account_info(account_info_iter)?; // Smart wallet PDA account
    let wallet_usdc_account = next_account_info(account_info_iter)?; // Wallet's USDC ATA
    let token_program = next_account_info(account_info_iter)?; // SPL Token Program

    // For Raydium simulation, we might need additional dummy accounts to satisfy `next_account_info` calls
    // in a real Raydium swap instruction. Let's consume some dummy accounts for now.
    // In a real scenario, these would be specific Raydium pool, market, and token accounts.
    let _dummy_raydium_program = next_account_info(account_info_iter)?;
    let _dummy_pool_account = next_account_info(account_info_iter)?;
    let _dummy_open_orders = next_account_info(account_info_iter)?;
    let _dummy_target_orders = next_account_info(account_info_iter)?;
    let _dummy_withdraw_queue = next_account_info(account_info_iter)?;
    let _dummy_lp_mint = next_account_info(account_info_iter)?;
    let _dummy_amm_authority = next_account_info(account_info_iter)?;
    let _dummy_coin_vault = next_account_info(account_info_iter)?;
    let _dummy_pc_vault = next_account_info(account_info_iter)?;
    let _dummy_market_program = next_account_info(account_info_iter)?;
    let _dummy_market_account = next_account_info(account_info_iter)?;
    let _dummy_market_bids = next_account_info(account_info_iter)?;
    let _dummy_market_asks = next_account_info(account_info_iter)?;
    let _dummy_market_event_queue = next_account_info(account_info_iter)?;
    let _dummy_market_base_vault = next_account_info(account_info_iter)?;
    let _dummy_market_quote_vault = next_account_info(account_info_iter)?;
    let _dummy_serum_authority = next_account_info(account_info_iter)?;
    // This list can grow significantly for a real swap.

    // Verify authority is a signer
    if !authority.is_signer {
        return Err(SmartWalletError::MissingRequiredSignature.into());
    }

    // Deserialize the wallet data
    let mut wallet_data = get_and_validate_wallet_account(program_id, wallet_account)?;

    // Verify authority is either the owner or the external authority
    let is_owner = wallet_data.owner == *authority.key;
    let is_external_authority = wallet_data.external_authority.map_or(false, |ea| ea == *authority.key);
    if !is_owner && !is_external_authority {
        return Err(SmartWalletError::AuthorityMismatch.into());
    }

    // Verify token program is the SPL Token program
    if token_program.key != &spl_token::id() {
        return Err(SmartWalletError::InvalidTokenProgram.into());
    }

    // Verify wallet_usdc_account is owned by the wallet PDA and is the correct mint
    let wallet_usdc_token_account_data = TokenAccount::unpack(&wallet_usdc_account.data.borrow())?;
    if wallet_usdc_token_account_data.owner != wallet_data.authority_pubkey {
        return Err(SmartWalletError::InvalidAssociatedTokenAccount.into());
    }
    if wallet_usdc_token_account_data.mint != wallet_data.usdc_token_mint {
        return Err(SmartWalletError::InvalidTokenMint.into());
    }

    let usdc_balance = wallet_usdc_token_account_data.amount;

    if usdc_balance < wallet_data.increment_amount {
        msg!("Insufficient USDC balance for purchases. Need at least {} USDC (scaled)", wallet_data.increment_amount);
        wallet_data.low_balance_notified = true; // Set flag
        SmartWallet::pack(wallet_data, &mut wallet_account.data.borrow_mut())?; // Pack updated state
        return Err(SmartWalletError::InsufficientFunds.into());
    }

    // Determine how many tokens we can buy with our available balance
    let num_tokens_to_buy = std::cmp::min(
        (usdc_balance / wallet_data.increment_amount) as usize,
        std::cmp::min(token_mints.len(), wallet_data.max_tokens_per_run as usize)
    );

    if num_tokens_to_buy == 0 {
        msg!("No tokens to purchase based on current balance or max_tokens_per_run.");
        return Ok(()); // Nothing to do
    }

    msg!("Purchasing {} tokens with {} USDC (scaled) each", num_tokens_to_buy, wallet_data.increment_amount);

    // --- Raydium Swap Simulation ---
    // In a real implementation, you'd iterate through selected token_mints and:
    // 1. Find the appropriate Raydium pool for USDC -> token_mint.
    // 2. Construct the Raydium swap instruction using the pool's specific accounts.
    // 3. Create the necessary associated token accounts for the new tokens if they don't exist.
    // 4. Invoke the Raydium program with `invoke_signed`, using the wallet's PDA as the signer.
    //
    // For this simulation, we'll just log the intended action and deduct the balance.
    // The actual token transfer would happen via the Raydium CPI.

    let total_cost = (num_tokens_to_buy as u64) * wallet_data.increment_amount;

    // Simulate transfer of USDC from wallet_usdc_account to a dummy Raydium vault
    // This is a placeholder for the actual swap logic that would involve Raydium's program.
    // In a real scenario, the USDC would be transferred to Raydium's pool vault.
    // Here, we just ensure the wallet has enough funds and simulate the deduction.

    // A real swap would involve:
    // spl_token::instruction::transfer(
    //     token_program.key,
    //     wallet_usdc_account.key,
    //     raydium_usdc_vault_account.key, // Raydium's USDC vault
    //     &wallet_data.authority_pubkey,
    //     &[],
    //     total_cost,
    // )?;
    // invoke_signed(
    //     &transfer_to_raydium_ix,
    //     &[wallet_usdc_account.clone(), raydium_usdc_vault_account.clone(), wallet_account.clone(), token_program.clone()],
    //     &[&[b"wallet", wallet_data.owner.as_ref(), &[wallet_data.authority_bump_seed]]]
    // )?;
    //
    // Then, invoke the Raydium swap instruction.
    //
    // For now, we only check the balance and update the flag.
    // The actual USDC deduction from `wallet_usdc_account` would happen via the Raydium CPI.
    // Since we're not doing the actual CPI, the balance on `wallet_usdc_account` won't change here.
    // This means the GCF will need to re-fetch the balance to get the updated amount.

    let remaining_balance_after_simulated_purchase = usdc_balance - total_cost;

    // Check if the remaining balance is below the increment amount
    if remaining_balance_after_simulated_purchase < wallet_data.increment_amount {
        wallet_data.low_balance_notified = true; // Set flag
        msg!("Remaining balance ({} USDC scaled) is below the increment amount. Low balance flag set.", remaining_balance_after_simulated_purchase);
    } else {
        wallet_data.low_balance_notified = false; // Ensure flag is false if balance is sufficient
    }

    // Pack the updated wallet data back to the account
    SmartWallet::pack(wallet_data, &mut wallet_account.data.borrow_mut())?;

    msg!("Simulated token purchases completed for {} tokens. Total cost: {} USDC (scaled).", num_tokens_to_buy, total_cost);
    Ok(())
}

// Reset the low balance notification flag
fn reset_low_balance_flag(program_id: &Pubkey, accounts: &[AccountInfo]) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let authority = next_account_info(account_info_iter)?; // Signer: owner or external authority
    let wallet_account = next_account_info(account_info_iter)?;

    // Verify authority is a signer
    if !authority.is_signer {
        return Err(SmartWalletError::MissingRequiredSignature.into());
    }

    // Deserialize the wallet data
    let mut wallet_data = get_and_validate_wallet_account(program_id, wallet_account)?;

    // Verify authority is either the owner or the external authority
    let is_owner = wallet_data.owner == *authority.key;
    let is_external_authority = wallet_data.external_authority.map_or(false, |ea| ea == *authority.key);
    if !is_owner && !is_external_authority {
        return Err(SmartWalletError::AuthorityMismatch.into());
    }

    // Reset the low_balance_notified flag to false
    wallet_data.low_balance_notified = false;

    // Pack the updated wallet data back to the account
    SmartWallet::pack(wallet_data, &mut wallet_account.data.borrow_mut())?;

    msg!("Low balance notification flag reset for wallet {}", wallet_account.key);
    Ok(())
}
