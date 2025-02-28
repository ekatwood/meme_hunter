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
};
use std::convert::TryInto;

// Define our program's state struct with new fields
#[derive(Debug)]
pub struct SmartWallet {
    pub owner: Pubkey,
    pub authority_bump_seed: u8,
    pub authority_pubkey: Pubkey,
    pub is_active: bool,
    pub external_authority: Option<Pubkey>,
    pub usdc_token_mint: Pubkey,
    pub increment_amount: u64,  // Amount in USDC (scaled by decimals)
    pub max_tokens_per_run: u8, // Maximum number of tokens to buy in a single run
    pub email_notifications: bool,
    pub user_email: String,
    pub low_balance_notified: bool,
}

// Define instruction types with updated functionality
#[derive(Debug)]
pub enum SmartWalletInstruction {
    /// Initialize a new smart wallet
    /// 0. `[signer]` Funding account (must be wallet owner)
    /// 1. `[writable]` New wallet account
    /// 2. `[]` USDC token mint
    Initialize {
        increment_amount: u64,
        max_tokens_per_run: u8,
        email: String,
        enable_notifications: bool,
    },
    
    /// Deposit USDC into wallet
    /// 0. `[signer]` Source owner
    /// 1. `[writable]` Source USDC account
    /// 2. `[writable]` Wallet USDC account
    /// 3. `[]` Token program
    DepositUSDC { amount: u64 },
    
    /// Withdraw USDC from wallet
    /// 0. `[signer]` Owner
    /// 1. `[writable]` Wallet USDC account
    /// 2. `[writable]` Destination USDC account
    /// 3. `[]` Token program
    WithdrawUSDC { amount: u64 },
    
    /// Update wallet settings
    /// 0. `[signer]` Owner
    /// 1. `[writable]` Wallet account
    UpdateSettings {
        increment_amount: Option<u64>,
        max_tokens_per_run: Option<u8>,
        email: Option<String>,
        enable_notifications: Option<bool>,
    },
    
    /// Authorize an external authority (e.g., cloud function wallet)
    /// 0. `[signer]` Owner
    /// 1. `[writable]` Wallet account
    /// 2. `[]` New authority
    AuthorizeExternal,
    
    /// Execute token purchases
    /// 0. `[signer]` Authority (owner or external)
    /// 1. `[writable]` Wallet account
    /// 2. `[writable]` Wallet USDC account
    /// 3+ Token accounts and Raydium program accounts
    PurchaseTokens { token_mints: Vec<Pubkey> },
    
    /// Reset low balance notification flag
    /// 0. `[signer]` Owner or authority
    /// 1. `[writable]` Wallet account
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
    // First byte of instruction data determines the instruction type
    let instruction = match instruction_data[0] {
        0 => {
            // Parse the initialize instruction data
            if instruction_data.len() < 11 {
                return Err(ProgramError::InvalidInstructionData);
            }
            
            let increment_amount = instruction_data[1..9]
                .try_into()
                .map(u64::from_le_bytes)
                .map_err(|_| ProgramError::InvalidInstructionData)?;
                
            let max_tokens_per_run = instruction_data[9];
            
            // Parse email and notification settings (simplified)
            let email_len = instruction_data[10] as usize;
            let email = std::str::from_utf8(&instruction_data[11..11 + email_len])
                .map_err(|_| ProgramError::InvalidInstructionData)?
                .to_string();
                
            let enable_notifications = instruction_data[11 + email_len] != 0;
            
            SmartWalletInstruction::Initialize {
                increment_amount,
                max_tokens_per_run,
                email,
                enable_notifications,
            }
        },
        1 => {
            let amount = instruction_data[1..9]
                .try_into()
                .map(u64::from_le_bytes)
                .map_err(|_| ProgramError::InvalidInstructionData)?;
            SmartWalletInstruction::DepositUSDC { amount }
        },
        2 => {
            let amount = instruction_data[1..9]
                .try_into()
                .map(u64::from_le_bytes)
                .map_err(|_| ProgramError::InvalidInstructionData)?;
            SmartWalletInstruction::WithdrawUSDC { amount }
        },
        3 => {
            // Update settings instruction parsing (simplified)
            let mut offset = 1;
            
            // Parse increment amount if present
            let has_increment = instruction_data[offset] != 0;
            offset += 1;
            let increment_amount = if has_increment {
                let amount = instruction_data[offset..offset+8]
                    .try_into()
                    .map(u64::from_le_bytes)
                    .map_err(|_| ProgramError::InvalidInstructionData)?;
                offset += 8;
                Some(amount)
            } else {
                None
            };
            
            // Parse max tokens per run if present
            let has_max_tokens = instruction_data[offset] != 0;
            offset += 1;
            let max_tokens_per_run = if has_max_tokens {
                Some(instruction_data[offset])
            } else {
                None
            };
            offset += 1;
            
            // Parse email if present (simplified)
            let has_email = instruction_data[offset] != 0;
            offset += 1;
            let email = if has_email {
                let email_len = instruction_data[offset] as usize;
                offset += 1;
                let email = std::str::from_utf8(&instruction_data[offset..offset + email_len])
                    .map_err(|_| ProgramError::InvalidInstructionData)?
                    .to_string();
                offset += email_len;
                Some(email)
            } else {
                None
            };
            
            // Parse enable notifications if present
            let has_notifications = instruction_data[offset] != 0;
            offset += 1;
            let enable_notifications = if has_notifications {
                Some(instruction_data[offset] != 0)
            } else {
                None
            };
            
            SmartWalletInstruction::UpdateSettings {
                increment_amount,
                max_tokens_per_run,
                email,
                enable_notifications,
            }
        },
        4 => SmartWalletInstruction::AuthorizeExternal,
        5 => {
            // Parse token mints for purchase
            let num_tokens = instruction_data[1] as usize;
            let mut token_mints = Vec::with_capacity(num_tokens);
            
            for i in 0..num_tokens {
                let start = 2 + (i * 32);
                let end = start + 32;
                if end > instruction_data.len() {
                    return Err(ProgramError::InvalidInstructionData);
                }
                
                let mint_data = &instruction_data[start..end];
                let pubkey = Pubkey::new(mint_data);
                token_mints.push(pubkey);
            }
            
            SmartWalletInstruction::PurchaseTokens { token_mints }
        },
        6 => SmartWalletInstruction::ResetLowBalanceFlag,
        _ => return Err(ProgramError::InvalidInstructionData),
    };

    // Process the instruction
    match instruction {
        SmartWalletInstruction::Initialize { increment_amount, max_tokens_per_run, email, enable_notifications } => {
            initialize(program_id, accounts, increment_amount, max_tokens_per_run, email, enable_notifications)
        },
        SmartWalletInstruction::DepositUSDC { amount } => deposit_usdc(program_id, accounts, amount),
        SmartWalletInstruction::WithdrawUSDC { amount } => withdraw_usdc(program_id, accounts, amount),
        SmartWalletInstruction::UpdateSettings { increment_amount, max_tokens_per_run, email, enable_notifications } => {
            update_settings(program_id, accounts, increment_amount, max_tokens_per_run, email, enable_notifications)
        },
        SmartWalletInstruction::AuthorizeExternal => authorize_external(program_id, accounts),
        SmartWalletInstruction::PurchaseTokens { token_mints } => purchase_tokens(program_id, accounts, token_mints),
        SmartWalletInstruction::ResetLowBalanceFlag => reset_low_balance_flag(program_id, accounts),
    }
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

    // Verify the funder is a signer
    if !funder.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }

    // Create the wallet PDA (Program Derived Address)
    let (authority_pubkey, authority_bump_seed) = Pubkey::find_program_address(
        &[b"wallet", funder.key.as_ref()],
        program_id,
    );

    // Initialize wallet data
    let wallet_data = SmartWallet {
        owner: *funder.key,
        authority_bump_seed,
        authority_pubkey,
        is_active: true,
        external_authority: None,
        usdc_token_mint: *usdc_mint.key,
        increment_amount,
        max_tokens_per_run,
        email_notifications: enable_notifications,
        user_email: email,
        low_balance_notified: false,
    };

    // Serialize and store the wallet data
    // In a real implementation, you'd serialize the struct into the account data
    // This is simplified for example purposes
    msg!("Smart wallet initialized with USDC increment: {} and max tokens: {}", 
         increment_amount, max_tokens_per_run);

    Ok(())
}

// Deposit USDC into wallet
fn deposit_usdc(program_id: &Pubkey, accounts: &[AccountInfo], amount: u64) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let source_owner = next_account_info(account_info_iter)?;
    let source_usdc = next_account_info(account_info_iter)?;
    let wallet_usdc = next_account_info(account_info_iter)?;
    let token_program = next_account_info(account_info_iter)?;

    // Verify the source owner is a signer
    if !source_owner.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }

    // Create the transfer instruction for SPL tokens
    let transfer_ix = spl_token::instruction::transfer(
        token_program.key,
        source_usdc.key,
        wallet_usdc.key,
        source_owner.key,
        &[],
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
    // In a real implementation, you'd deserialize the account, update the flag,
    // and serialize it back to the account data
    
    msg!("Deposited {} USDC into wallet", amount);
    Ok(())
}

// Withdraw USDC from wallet
fn withdraw_usdc(program_id: &Pubkey, accounts: &[AccountInfo], amount: u64) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let owner = next_account_info(account_info_iter)?;
    let wallet_usdc = next_account_info(account_info_iter)?;
    let destination_usdc = next_account_info(account_info_iter)?;
    let token_program = next_account_info(account_info_iter)?;

    // Verify owner is a signer
    if !owner.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }

    // Verify owner (in a real implementation, you'd deserialize the account to check the owner)
    // For simplicity, this example omits that check

    // Create the PDA signer seeds
    let wallet_seed = b"wallet";
    let authority_seeds = &[
        wallet_seed,
        owner.key.as_ref(),
        &[0], // The bump seed would be from the account data in a real implementation
    ];

    // Create the transfer instruction for SPL tokens
    let transfer_ix = spl_token::instruction::transfer(
        token_program.key,
        wallet_usdc.key,
        destination_usdc.key,
        &authority_seeds[0],  // PDA as the authority
        &[],
        amount,
    )?;

    // Execute the transfer with PDA signing
    invoke_signed(
        &transfer_ix,
        &[
            wallet_usdc.clone(),
            destination_usdc.clone(),
            token_program.clone(),
        ],
        &[authority_seeds],
    )?;

    msg!("Withdrew {} USDC from wallet", amount);
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
        return Err(ProgramError::MissingRequiredSignature);
    }

    // In a real implementation, you'd:
    // 1. Deserialize the wallet data from the account
    // 2. Verify the owner matches
    // 3. Update the fields that are present in the options
    // 4. Serialize the wallet data back to the account
    
    msg!("Smart wallet settings updated");
    Ok(())
}

// Authorize an external wallet (for the Google Cloud Function)
fn authorize_external(program_id: &Pubkey, accounts: &[AccountInfo]) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let owner = next_account_info(account_info_iter)?;
    let wallet_account = next_account_info(account_info_iter)?;
    let external_authority = next_account_info(account_info_iter)?;

    // Verify owner is a signer
    if !owner.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }

    // In a real implementation, you'd deserialize the account, update the external_authority field,
    // then serialize it back to the account data
    
    msg!("Authorized external authority: {:?}", external_authority.key);
    Ok(())
}

// Purchase tokens with USDC using Raydium
fn purchase_tokens(program_id: &Pubkey, accounts: &[AccountInfo], token_mints: Vec<Pubkey>) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let authority = next_account_info(account_info_iter)?;
    let wallet_account = next_account_info(account_info_iter)?;
    let wallet_usdc = next_account_info(account_info_iter)?;
    
    // Verify authority is a signer
    if !authority.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }
    
    // In a real implementation, you'd:
    // 1. Deserialize the wallet data
    // 2. Verify the authority is either the owner or the external authority
    // 3. Get the increment amount and max tokens per run from the wallet data
    // 4. Check if there's enough USDC balance
    
    // For this example, we'll use placeholder values
    let increment_amount = 20_000_000; // 20 USDC with 6 decimals
    let max_tokens_per_run = 5;
    
    // Check if we have enough USDC to make at least one purchase
    // In a real implementation, you'd deserialize the token account to get the real balance
    let usdc_balance = 100_000_000; // Placeholder for 100 USDC
    
    if usdc_balance < increment_amount {
        // Set the low balance notification flag if not already set
        // In a real implementation, you'd update the flag in the wallet data
        msg!("Insufficient USDC balance for purchases. Need at least {} USDC", increment_amount / 1_000_000);
        return Err(ProgramError::InsufficientFunds);
    }
    
    // Determine how many tokens we can buy with our available balance
    let num_tokens_to_buy = std::cmp::min(
        (usdc_balance / increment_amount) as usize,
        std::cmp::min(token_mints.len(), max_tokens_per_run as usize)
    );
    
    msg!("Purchasing {} tokens with {} USDC each", num_tokens_to_buy, increment_amount / 1_000_000);
    
    // In a real implementation, you'd execute Raydium swaps for each token
    // This would involve creating the proper Raydium swap instructions
    // and executing them for each token mint up to num_tokens_to_buy
    
    // For example (pseudo-code):
    // for i in 0..num_tokens_to_buy {
    //     let token_mint = token_mints[i];
    //     execute_raydium_swap(accounts, token_mint, increment_amount);
    // }
    
    // Check if the remaining balance is below the increment amount
    let remaining_balance = usdc_balance - (num_tokens_to_buy as u64 * increment_amount);
    if remaining_balance < increment_amount && num_tokens_to_buy > 0 {
        // Set the low balance notification flag if not already set
        // In a real implementation, you'd update the flag in the wallet data
        msg!("Remaining balance ({} USDC) is below the increment amount", remaining_balance / 1_000_000);
    }
    
    Ok(())
}

// Reset the low balance notification flag
fn reset_low_balance_flag(program_id: &Pubkey, accounts: &[AccountInfo]) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    let authority = next_account_info(account_info_iter)?;
    let wallet_account = next_account_info(account_info_iter)?;

    // Verify authority is a signer
    if !authority.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }
    
    // In a real implementation, you'd:
    // 1. Deserialize the wallet data
    // 2. Verify the authority is either the owner or the external authority
    // 3. Reset the low_balance_notified flag to false
    // 4. Serialize the wallet data back to the account
    
    msg!("Low balance notification flag reset");
    Ok(())
}
