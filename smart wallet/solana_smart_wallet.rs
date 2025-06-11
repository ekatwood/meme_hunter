// Dependencies for Cargo.toml:

//[dependencies]
//solana-program = "1.18.15" # Or latest compatible with Jupiter's SDK
//borsh = "0.10.3"
//spl-token = "4.0.0" # Ensure this is compatible with your solana-program version
//
//# If you decide to use a Jupiter Rust CPI crate directly:
//# jupiter-amm-v6 = { version = "0.1.0" } # Check for latest compatible version

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
use spl_token::{
    state::{Account as TokenAccount, Mint as TokenMint},
    instruction as spl_token_instruction,
}; // For SPL token account state
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
    #[error("Account not rent-paying")] // Added for close
    AccountNotRentPaying,
    #[error("Remaining accounts not provided for Jupiter swap")]
    MissingJupiterAccounts,
}

impl From<SmartWalletError> for ProgramError {
    fn from(e: SmartWalletError) -> Self {
        ProgramError::Custom(e as u32)
    }
}

// Define our program's state struct
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
impl Sealed for SmartWallet {}

impl IsInitialized for SmartWallet {
    fn is_initialized(&self) -> bool {
        self.is_initialized
    }
}

// Implement `Pack` for the SmartWallet struct to manage account data.
impl Pack for SmartWallet {
    const LEN: usize = 256; // A sufficiently large size for the SmartWallet struct.

    fn pack_into_slice(&self, dst: &mut [u8]) {
        let encoded = self.try_to_vec().expect("Failed to serialize SmartWallet");
        dst[..encoded.len()].copy_from_slice(&encoded);
        dst[encoded.len()..].fill(0); // Pad with zeros for fixed size
    }

    fn unpack_from_slice(src: &[u8]) -> Result<Self, ProgramError> {
        SmartWallet::try_from_slice(src)
            .map_err(|_| ProgramError::InvalidAccountData)
    }
}


// Define instruction types with updated functionality
#[derive(BorshSerialize, BorshDeserialize, Debug, PartialEq)]
pub enum SmartWalletInstruction {
    /// Initialize a new smart wallet
    /// Accounts:
    /// 0. `[signer]` Funding account (must be wallet owner)
    /// 1. `[writable]` New wallet account (PDA, owned by program)
    /// 2. `[]` USDC token mint (e.g., EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v)
    /// 3. `[]` System Program
    /// 4. `[]` Rent Sysvar
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
    /// 4. `[writable]` Wallet account (PDA, owned by program) - to update low_balance_notified
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

    /// Execute token purchases using Jupiter
    /// Accounts:
    /// 0. `[signer]` Authority (owner or external authority)
    /// 1. `[writable]` Wallet account (PDA, owned by program) - to update low_balance_notified
    /// 2. `[writable]` Wallet USDC account (ATA of wallet PDA)
    /// 3. `[]` SPL Token Program
    /// 4. `[]` System Program
    /// 5. `[]` Rent Sysvar
    /// 6. `[]` Sysvar:Instructions (for CPI checks)
    /// 7. `[optional]` All other accounts required by Jupiter's swap instruction (dynamic list)
    PurchaseTokens { token_mints: Vec<Pubkey>, jupiter_swap_ix_data: Vec<u8> },

    /// Reset low balance notification flag
    /// Accounts:
    /// 0. `[signer]` Authority (owner or external authority)
    /// 1. `[writable]` Wallet account (PDA, owned by program)
    ResetLowBalanceFlag,

    /// Cancel smart wallet and reclaim SOL/tokens
    /// Accounts:
    /// 0. `[signer]` Owner (must be the wallet owner)
    /// 1. `[writable]` Wallet account (PDA, owned by program) - to be closed
    /// 2. `[writable]` Wallet USDC account (ATA of wallet PDA) - to be closed (funds reclaimed)
    /// 3. `[writable]` Owner's USDC account (ATA of owner) - where USDC goes
    /// 4. `[]` SPL Token Program
    /// 5. `[writable]` Owner's SOL account (system account) - where SOL rent exemption goes
    CancelSmartWallet,
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
        SmartWalletInstruction::PurchaseTokens { token_mints, jupiter_swap_ix_data } => {
            msg!("Instruction: PurchaseTokens");
            purchase_tokens(program_id, accounts, token_mints, jupiter_swap_ix_data)
        },
        SmartWalletInstruction::ResetLowBalanceFlag => {
            msg!("Instruction: ResetLowBalanceFlag");
            reset_low_balance_flag(program_id, accounts)
        },
        SmartWalletInstruction::CancelSmartWallet => {
            msg!("Instruction: CancelSmartWallet");
            cancel_smart_wallet(program_id, accounts)
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
    let rent_sysvar = next_account_info(account_info_iter)?; // Rent sysvar account

    // Verify the funder is a signer
    if !funder.is_signer {
        return Err(SmartWalletError::MissingRequiredSignature.into());
    }

    // Verify wallet account is not already initialized
    // Check if the account is owned by the program and has data
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
    let rent = &Rent::from_account_info(rent_sysvar)?; // Rent sysvar
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
    let transfer_ix = spl_token_instruction::transfer(
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
    let transfer_ix = spl_token_instruction::transfer(
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
        // Basic length check for email
        if user_email.len() > 100 { // Max 100 chars for email
            return Err(ProgramError::InvalidArgument);
        }
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

// Purchase tokens using Jupiter
fn purchase_tokens(program_id: &Pubkey, accounts: &[AccountInfo], token_mints: Vec<Pubkey>, jupiter_swap_ix_data: Vec<u8>) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let authority = next_account_info(account_info_iter)?; // Signer: owner or external authority
    let wallet_account = next_account_info(account_info_iter)?; // Smart wallet PDA account
    let wallet_usdc_account = next_account_info(account_info_iter)?; // Wallet's USDC ATA
    let token_program = next_account_info(account_info_iter)?; // SPL Token Program
    let system_program = next_account_info(account_info_iter)?; // System Program
    let rent_sysvar = next_account_info(account_info_iter)?; // Rent Sysvar
    let sysvar_instructions = next_account_info(account_info_iter)?; // Sysvar:Instructions for CPI

    // The rest of the accounts are for Jupiter. We consume them all as remaining accounts.
    let mut jupiter_cpi_accounts_infos = vec![];
    while let Ok(account) = next_account_info(account_info_iter) {
        jupiter_cpi_accounts_infos.push(account.clone());
    }

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
    // This is a simple count; Jupiter will handle actual swap logic based on jupiter_swap_ix_data
    let num_tokens_to_buy = std::cmp::min(
        (usdc_balance / wallet_data.increment_amount) as usize,
        std::cmp::min(token_mints.len(), wallet_data.max_tokens_per_run as usize)
    );

    if num_tokens_to_buy == 0 || jupiter_swap_ix_data.is_empty() {
        msg!("No tokens to purchase or Jupiter swap data provided.");
        return Ok(()); // Nothing to do
    }

    msg!("Executing Jupiter swap for {} USDC (scaled) from wallet {} to buy tokens.",
         wallet_data.increment_amount, wallet_account.key);

    // --- Jupiter Swap CPI ---
    // The `jupiter_swap_ix_data` contains the serialized instruction data for Jupiter's swap.
    // The `jupiter_cpi_accounts_infos` contains the AccountInfo for all accounts required by Jupiter.

    // Verify Jupiter accounts are provided (at least Jupiter Program ID and necessary token accounts)
    if jupiter_cpi_accounts_infos.is_empty() {
        return Err(SmartWalletError::MissingJupiterAccounts.into());
    }

    // Construct the Jupiter Instruction from the provided data and accounts.
    // The first account in jupiter_cpi_accounts_infos is expected to be Jupiter's Program ID.
    let jupiter_program_id = jupiter_cpi_accounts_infos[0].key;

    // Create AccountMeta vector from AccountInfo vector
    let jupiter_accounts_meta: Vec<solana_program::instruction::AccountMeta> =
        jupiter_cpi_accounts_infos.iter().map(|acc_info| {
            solana_program::instruction::AccountMeta {
                pubkey: *acc_info.key,
                is_signer: acc_info.is_signer,
                is_writable: acc_info.is_writable,
            }
        }).collect();

    let jupiter_swap_ix = solana_program::instruction::Instruction {
        program_id: *jupiter_program_id,
        accounts: jupiter_accounts_meta,
        data: jupiter_swap_ix_data,
    };

    // Prepare signers seeds for the wallet PDA
    let wallet_seed = b"wallet";
    let authority_seeds = &[
        wallet_seed,
        wallet_data.owner.as_ref(),
        &[wallet_data.authority_bump_seed],
    ];

    // Invoke Jupiter swap with PDA signing
    // All accounts listed in `jupiter_swap_ix.accounts` must be passed to `invoke_signed`.
    // The mutable accounts must be writable clones.
    invoke_signed(
        &jupiter_swap_ix,
        &jupiter_cpi_accounts_infos, // Pass the same AccountInfos that Jupiter expects
        &[authority_seeds],
    )?;

    msg!("Jupiter swap executed successfully!");

    // Check if the remaining balance is below the increment amount
    // After a Jupiter swap, the balance of wallet_usdc_account will be updated.
    // We would re-fetch the balance to make an accurate assessment for the flag.
    // For simplicity, we'll assume it might be low and set the flag if needed.
    // A more robust solution would re-read `wallet_usdc_account.data` here.
    let updated_wallet_usdc_token_account_data = TokenAccount::unpack(&wallet_usdc_account.data.borrow())?;
    let remaining_balance = updated_wallet_usdc_token_account_data.amount;

    if remaining_balance < wallet_data.increment_amount {
        wallet_data.low_balance_notified = true; // Set flag
        msg!("Remaining balance ({} USDC scaled) is below the increment amount. Low balance flag set.", remaining_balance);
    } else {
        wallet_data.low_balance_notified = false; // Ensure flag is false if balance is sufficient
    }

    // Pack the updated wallet data back to the account
    SmartWallet::pack(wallet_data, &mut wallet_account.data.borrow_mut())?;

    msg!("Smart wallet state updated after Jupiter swap.");
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

// Cancel smart wallet and reclaim SOL/tokens
fn cancel_smart_wallet(program_id: &Pubkey, accounts: &[AccountInfo]) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let owner = next_account_info(account_info_iter)?; // Owner (signer)
    let wallet_account = next_account_info(account_info_iter)?; // Wallet PDA account
    let wallet_usdc_account = next_account_info(account_info_iter)?; // Wallet's USDC ATA
    let owner_usdc_account = next_account_info(account_info_iter)?; // Owner's USDC ATA
    let token_program = next_account_info(account_info_iter)?; // SPL Token Program
    let owner_sol_account = next_account_info(account_info_iter)?; // Owner's SOL account (system account)

    // Verify owner is a signer
    if !owner.is_signer {
        return Err(SmartWalletError::MissingRequiredSignature.into());
    }

    // Deserialize wallet account and verify ownership
    let wallet_data = get_and_validate_wallet_account(program_id, wallet_account)?;
    if wallet_data.owner != *owner.key {
        return Err(SmartWalletError::OwnerMismatch.into());
    }

    // Verify token program
    if token_program.key != &spl_token::id() {
        return Err(SmartWalletError::InvalidTokenProgram.into());
    }

    // Close Wallet USDC ATA first: transfer all remaining USDC to owner's USDC ATA
    let wallet_usdc_token_data = TokenAccount::unpack(&wallet_usdc_account.data.borrow())?;
    if wallet_usdc_token_data.owner != wallet_data.authority_pubkey {
        return Err(SmartWalletError::InvalidAssociatedTokenAccount.into());
    }
    if wallet_usdc_token_data.mint != wallet_data.usdc_token_mint {
        return Err(SmartWalletError::InvalidTokenMint.into());
    }

    let usdc_balance = wallet_usdc_token_data.amount;
    if usdc_balance > 0 {
        msg!("Transferring {} USDC from wallet ATA to owner's ATA.", usdc_balance);
        let wallet_seed = b"wallet";
        let authority_seeds = &[
            wallet_seed,
            owner.key.as_ref(),
            &[wallet_data.authority_bump_seed],
        ];

        let transfer_usdc_ix = spl_token_instruction::transfer(
            token_program.key,
            wallet_usdc_account.key,
            owner_usdc_account.key,
            &wallet_data.authority_pubkey, // PDA as authority
            &[],
            usdc_balance,
        )?;

        invoke_signed(
            &transfer_usdc_ix,
            &[
                wallet_usdc_account.clone(),
                owner_usdc_account.clone(),
                wallet_account.clone(), // PDA account needed for signing
                token_program.clone(),
            ],
            &[authority_seeds],
        )?;
    }

    // Close the wallet's USDC ATA, reclaiming its rent exemption to owner's SOL account
    msg!("Closing wallet USDC ATA.");
    let close_usdc_ix = spl_token_instruction::close_account(
        token_program.key,
        wallet_usdc_account.key,
        owner_sol_account.key, // Destination for SOL rent
        &wallet_data.authority_pubkey, // Authority to close
        &[],
    )?;

    let wallet_seed = b"wallet";
    let authority_seeds = &[
        wallet_seed,
        owner.key.as_ref(),
        &[wallet_data.authority_bump_seed],
    ];

    invoke_signed(
        &close_usdc_ix,
        &[
            wallet_usdc_account.clone(),
            owner_sol_account.clone(),
            wallet_account.clone(), // PDA account needed for signing
            token_program.clone(),
        ],
        &[authority_seeds],
    )?;

    // Close the main Smart Wallet PDA account, reclaiming its SOL rent to owner's SOL account
    msg!("Closing main smart wallet PDA account.");
    let transfer_sol_ix = system_instruction::transfer(
        wallet_account.key,
        owner_sol_account.key,
        wallet_account.lamports(),
    );

    let wallet_seed = b"wallet";
    let authority_seeds = &[
        wallet_seed,
        owner.key.as_ref(),
        &[wallet_data.authority_bump_seed],
    ];

    invoke_signed(
        &transfer_sol_ix,
        &[
            wallet_account.clone(),
            owner_sol_account.clone(),
            system_program::id().to_account_info().clone(), // System program
        ],
        &[authority_seeds],
    )?;

    // At this point, the wallet_account should effectively be closed and its lamports transferred.
    // The runtime will zero out the data and reset the owner for closed accounts.
    msg!("Smart wallet {} cancelled. All funds reclaimed.", wallet_account.key);

    Ok(())
}