// lib/smart_wallet_service.dart

import 'package:flutter/foundation.dart'; // For @required
import 'package:solana/solana.dart';
import 'package:solana_wallet_adapter/solana_wallet_adapter.dart';
import 'package:solana_wallet_adapter/solana_wallet_adapter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data'; // For ByteData

// --- SmartWalletService ---
class SmartWalletService extends ChangeNotifier { // Make it ChangeNotifier for Provider
  final String rpcUrl;
  final Pubkey programId;
  final String gcfTriggerUrl; // For triggering single wallet processing
  // You might need a GCF URL for other Firestore operations if done via GCF
  // For now, Flutter app directly interacts with Solana for init/update/cancel transactions.
  // The Firestore updates for these are handled by the GCFs or via a backend webhook.

  WalletAdapter? _walletAdapter;
  String? _userWalletAddress; // Connected Solflare wallet address
  bool _isConnected = false;

  SmartWalletService({
    required this.rpcUrl,
    required this.programId,
    required this.gcfTriggerUrl,
  });

  String? get userWalletAddress => _userWalletAddress;
  bool get isConnected => _isConnected;

  SolanaClient get solanaClient => SolanaClient(rpcUrl: Uri.parse(rpcUrl));

  Future<void> connectWallet() async {
    _walletAdapter = WalletAdapter(config: WalletAdapterConfig(
      cluster: Cluster.devnet,
      wallets: [
        SolflareWalletAdapter(),
        PhantomWalletAdapter(),
      ],
    ));

    try {
      await _walletAdapter!.connect();
      _userWalletAddress = _walletAdapter!.publicKey?.toBase58();
      if (_userWalletAddress == null) {
        throw Exception("Failed to connect wallet: No public key found.");
      }
      _isConnected = true;
      print('Wallet connected: $_userWalletAddress');
      notifyListeners(); // Notify listeners of state change
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      rethrow; // Re-throw the error for UI to handle
    }
  }

  Future<void> disconnectWallet() async {
    try {
      if (_walletAdapter != null && _walletAdapter!.connected) {
        await _walletAdapter!.disconnect();
        _userWalletAddress = null;
        _isConnected = false;
        print('Wallet disconnected.');
        notifyListeners();
      }
    } catch (e) {
      print('Error disconnecting wallet: $e');
      rethrow;
    }
  }

  // Helper to serialize U64 (8 bytes) to List<int>
  List<int> _u64ToBytes(int value) {
    final byteData = ByteData(8);
    byteData.setUint64(0, value, Endian.little);
    return byteData.buffer.asUint8List();
  }

  // Helper to serialize U32 (4 bytes) length prefix for String
  List<int> _u32ToBytes(int value) {
    final byteData = ByteData(4);
    byteData.setUint32(0, value, Endian.little);
    return byteData.buffer.asUint8List();
  }

  Future<String> createSmartWallet({
    required int incrementAmount,
    required int maxTokensPerRun,
    required String email,
    required bool enableNotifications,
  }) async {
    if (!_isConnected || _userWalletAddress == null) throw Exception("Wallet not connected.");
    if (_walletAdapter == null) throw Exception("Wallet adapter unavailable.");

    final ownerPubkey = Pubkey.fromBase58(_userWalletAddress!);

    // Derive PDA
    final List<int> walletSeed = 'wallet'.codeUnits;
    final (walletPda, walletBump) = await Pubkey.findProgramAddress(
      seeds: [walletSeed, ownerPubkey.bytes],
      programId: programId,
    );

    // Get rent-exempt lamports for SmartWallet account
    final rent = await solanaClient.rpcClient.getRentExemptionAmount(
      dataLength: 256, // SmartWallet.LEN from Rust program
    );
    final lamports = rent.value;

    // Create SystemInstruction for account creation
    final createAccountIx = SystemInstruction.createAccount(
      from: ownerPubkey,
      newAccountPubkey: walletPda,
      lamports: lamports,
      space: 256,
      owner: programId,
    );

    // Create custom Initialize instruction data (Borsh-like manual serialization)
    final List<int> initInstructionData = [];
    initInstructionData.add(0); // Enum variant for Initialize
    initInstructionData.addAll(_u64ToBytes(incrementAmount));
    initInstructionData.add(maxTokensPerRun);
    initInstructionData.addAll(_u32ToBytes(email.length));
    initInstructionData.addAll(utf8.encode(email));
    initInstructionData.add(enableNotifications ? 1 : 0);

    final initializeIx = Instruction(
      programId: programId,
      accounts: [
        AccountMeta.new(ownerPubkey, isSigner: true, isWritable: false), // 0. Funder (owner)
        AccountMeta.new(walletPda, isSigner: false, isWritable: true),   // 1. New wallet account (PDA)
        AccountMeta.newReadOnly(Pubkey.fromBase58('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'), isSigner: false), // 2. USDC Mint
        AccountMeta.newReadOnly(SystemProgram.programId, isSigner: false), // 3. System Program
        AccountMeta.newReadOnly(Sysvar.rent, isSigner: false), // 4. Rent Sysvar
      ],
      data: initInstructionData,
    );

    // Create ATA for wallet's USDC
    final usdcMintPubkey = Pubkey.fromBase58('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v');
    final walletUsdcAta = getAssociatedTokenAddress(owner: walletPda, mint: usdcMintPubkey);
    final createWalletUsdcAtaIx = AssociatedTokenAccountProgram.createAssociatedTokenAccount(
      payer: ownerPubkey,
      associatedToken: walletUsdcAta,
      owner: walletPda,
      mint: usdcMintPubkey,
    );

    final transaction = Transaction(
      feePayer: ownerPubkey,
      recentBlockhash: await solanaClient.rpcClient.getLatestBlockhash().then((value) => value.value.blockhash),
      instructions: [
        createAccountIx,
        initializeIx,
        createWalletUsdcAtaIx,
      ],
    );

    final signedTransaction = await _walletAdapter!.signTransaction(transaction: transaction);
    final txId = await solanaClient.rpcClient.sendRawTransaction(signedTransaction.serialize());
    await solanaClient.rpcClient.confirmTransaction(txId);
    print('Smart wallet created. TX ID: $txId');
    return walletPda.toBase58();
  }

  Future<void> updateSmartWalletSettings({
    required String walletPdaAddress,
    int? incrementAmount,
    int? maxTokensPerRun,
    String? email,
    bool? enableNotifications,
  }) async {
    if (!_isConnected || _userWalletAddress == null) throw Exception("Wallet not connected.");
    if (_walletAdapter == null) throw Exception("Wallet adapter unavailable.");

    final ownerPubkey = Pubkey.fromBase58(_userWalletAddress!);
    final walletPda = Pubkey.fromBase58(walletPdaAddress);

    // Build instruction data (Borsh-like manual serialization)
    final List<int> updateInstructionData = [];
    updateInstructionData.add(3); // Enum variant for UpdateSettings

    // incrementAmount: Option<u64>
    updateInstructionData.add(incrementAmount != null ? 1 : 0);
    if (incrementAmount != null) updateInstructionData.addAll(_u64ToBytes(incrementAmount));

    // maxTokensPerRun: Option<u8>
    updateInstructionData.add(maxTokensPerRun != null ? 1 : 0);
    if (maxTokensPerRun != null) updateInstructionData.add(maxTokensPerRun);

    // email: Option<String>
    updateInstructionData.add(email != null ? 1 : 0);
    if (email != null) {
      updateInstructionData.addAll(_u32ToBytes(email.length));
      updateInstructionData.addAll(utf8.encode(email));
    }

    // enableNotifications: Option<bool>
    updateInstructionData.add(enableNotifications != null ? 1 : 0);
    if (enableNotifications != null) updateInstructionData.add(enableNotifications ? 1 : 0);

    final updateIx = Instruction(
      programId: programId,
      accounts: [
        AccountMeta.new(ownerPubkey, isSigner: true, isWritable: false), // 0. Owner (signer)
        AccountMeta.new(walletPda, isSigner: false, isWritable: true),   // 1. Wallet account (writable)
      ],
      data: updateInstructionData,
    );

    final transaction = Transaction(
      feePayer: ownerPubkey,
      recentBlockhash: await solanaClient.rpcClient.getLatestBlockhash().then((value) => value.value.blockhash),
      instructions: [updateIx],
    );

    final signedTransaction = await _walletAdapter!.signTransaction(transaction: transaction);
    final txId = await solanaClient.rpcClient.sendRawTransaction(signedTransaction.serialize());
    await solanaClient.rpcClient.confirmTransaction(txId);
    print('Smart wallet settings updated. TX ID: $txId');
  }

  Future<void> cancelSmartWallet({required String walletPdaAddress}) async {
    if (!_isConnected || _userWalletAddress == null) throw Exception("Wallet not connected.");
    if (_walletAdapter == null) throw Exception("Wallet adapter unavailable.");

    final ownerPubkey = Pubkey.fromBase58(_userWalletAddress!);
    final walletPda = Pubkey.fromBase58(walletPdaAddress);
    final usdcMintPubkey = Pubkey.fromBase58('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v');
    final walletUsdcAta = getAssociatedTokenAddress(owner: walletPda, mint: usdcMintPubkey);
    final ownerUsdcAta = getAssociatedTokenAddress(owner: ownerPubkey, mint: usdcMintPubkey);

    // Build instruction data (Borsh-like manual serialization)
    final List<int> cancelInstructionData = [];
    cancelInstructionData.add(6); // Enum variant for CancelSmartWallet (assuming 6 based on 0-indexed instructions)

    final cancelIx = Instruction(
      programId: programId,
      accounts: [
        AccountMeta.new(ownerPubkey, isSigner: true, isWritable: false),    // 0. Owner (signer)
        AccountMeta.new(walletPda, isSigner: false, isWritable: true),      // 1. Wallet account (PDA) - to be closed
        AccountMeta.new(walletUsdcAta, isSigner: false, isWritable: true),  // 2. Wallet USDC ATA - to be closed
        AccountMeta.new(ownerUsdcAta, isSigner: false, isWritable: true),   // 3. Owner's USDC ATA - where funds go
        AccountMeta.newReadOnly(TokenProgram.programId, isSigner: false),   // 4. SPL Token Program
        AccountMeta.new(ownerPubkey, isSigner: false, isWritable: true), // 5. Owner's SOL account (system account) - for rent reclaim
      ],
      data: cancelInstructionData,
    );

    final transaction = Transaction(
      feePayer: ownerPubkey,
      recentBlockhash: await solanaClient.rpcClient.getLatestBlockhash().then((value) => value.value.blockhash),
      instructions: [cancelIx],
    );

    final signedTransaction = await _walletAdapter!.signTransaction(transaction: transaction);
    final txId = await solanaClient.rpcClient.sendRawTransaction(signedTransaction.serialize());
    await solanaClient.rpcClient.confirmTransaction(txId);
    print('Smart wallet cancelled. TX ID: $txId');
  }

  // --- Read Smart Wallet Data from On-chain ---
  Future<Map<String, dynamic>?> getSmartWalletData(String walletPdaAddress) async {
    final walletPda = Pubkey.fromBase58(walletPdaAddress);
    try {
      final accountInfo = await solanaClient.rpcClient.getAccountInfo(walletPda);
      if (accountInfo.value == null || accountInfo.value!.data.isEmpty) {
        return null;
      }

      final dataBytes = accountInfo.value!.data;
      // Manual deserialization matching Rust's `SmartWallet` struct and Borsh encoding
      int offset = 0;

      final bool isInitialized = dataBytes[offset] == 1; offset += 1;
      if (!isInitialized) return {"is_initialized": false};

      final Pubkey owner = Pubkey.new(dataBytes.sublist(offset, offset + 32)); offset += 32;
      final int authorityBumpSeed = dataBytes[offset]; offset += 1;
      final Pubkey authorityPubkey = Pubkey.new(dataBytes.sublist(offset, offset + 32)); offset += 32;
      final bool isActive = dataBytes[offset] == 1; offset += 1;

      final bool hasExternalAuthority = dataBytes[offset] == 1; offset += 1;
      Pubkey? externalAuthority;
      if (hasExternalAuthority) {
        externalAuthority = Pubkey.new(dataBytes.sublist(offset, offset + 32)); offset += 32;
      }

      final Pubkey usdcTokenMint = Pubkey.new(dataBytes.sublist(offset, offset + 32)); offset += 32;
      final int incrementAmount = ByteData.view(Uint8List.fromList(dataBytes.sublist(offset, offset + 8)).buffer).getUint64(0, Endian.little); offset += 8;
      final int maxTokensPerRun = dataBytes[offset]; offset += 1;
      final bool emailNotifications = dataBytes[offset] == 1; offset += 1;

      final int emailLength = ByteData.view(Uint8List.fromList(dataBytes.sublist(offset, offset + 4)).buffer).getUint32(0, Endian.little); offset += 4;
      final String userEmail = utf8.decode(dataBytes.sublist(offset, offset + emailLength)); offset += emailLength;

      final bool lowBalanceNotified = dataBytes[offset] == 1; offset += 1;

      return {
        'is_initialized': isInitialized,
        'owner': owner.toBase58(),
        'authority_bump_seed': authorityBumpSeed,
        'authority_pubkey': authorityPubkey.toBase58(),
        'is_active': isActive,
        'external_authority': externalAuthority?.toBase58(),
        'usdc_token_mint': usdcTokenMint.toBase58(),
        'increment_amount': incrementAmount,
        'max_tokens_per_run': maxTokensPerRun,
        'email_notifications': emailNotifications,
        'user_email': userEmail,
        'low_balance_notified': lowBalanceNotified,
      };
    } catch (e) {
      print('Error deserializing smart wallet data: $e');
      return null;
    }
  }

  // --- GCF Call (for triggering single wallet processing) ---
  Future<Map<String, dynamic>> triggerSingleWalletProcessing({required String userWalletAddress}) async {
    try {
      final response = await http.post(
        Uri.parse(gcfTriggerUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userWalletAddress': userWalletAddress, // Send the user's wallet address
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to trigger single wallet processing: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error triggering GCF: $e');
      rethrow;
    }
  }
}