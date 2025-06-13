// lib/smart_escrow_wallet.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solana/solana.dart'; // For Pubkey.findProgramAddress
import 'auth_provider.dart'; // Import AuthProvider

class SmartEscrowWallet extends StatefulWidget {
  const SmartEscrowWallet({super.key});

  @override
  State<SmartEscrowWallet> createState() => _SmartEscrowWalletState();
}

class _SmartEscrowWalletState extends State<SmartEscrowWallet> {
  final TextEditingController _incrementAmountController = TextEditingController();
  final TextEditingController _maxTokensPerRunController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _enableNotifications = true;

  final _formKey = GlobalKey<FormState>();

  String? _smartWalletPdaAddress; // The PDA address of the user's smart wallet
  bool _isLoading = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    // Listen to AuthProvider for wallet connection changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.addListener(_onAuthProviderChange);
      // Attempt to load data if wallet is already connected
      if (authProvider.isLoggedIn) {
        _loadSmartWalletData();
      }
    });
  }

  void _onAuthProviderChange() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isLoggedIn) {
      _loadSmartWalletData();
    } else {
      setState(() {
        _smartWalletPdaAddress = null;
        _incrementAmountController.clear();
        _maxTokensPerRunController.clear();
        _emailController.clear();
        _enableNotifications = true;
        _statusMessage = 'Wallet disconnected. Please connect to manage smart wallet.';
      });
    }
  }

  @override
  void dispose() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.removeListener(_onAuthProviderChange);
    _incrementAmountController.dispose();
    _maxTokensPerRunController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadSmartWalletData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn || authProvider.walletAddress == null) {
      _statusMessage = "Connect wallet to load smart wallet data.";
      return;
    }
    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading smart wallet data...';
    });

    try {
      final ownerPubkey = Pubkey.fromBase58(authProvider.walletAddress!);
      final List<int> walletSeed = 'wallet'.codeUnits;
      final (derivedPda, _) = await Pubkey.findProgramAddress(
        seeds: [walletSeed, ownerPubkey.bytes],
        programId: authProvider.smartWalletService.programId,
      );
      _smartWalletPdaAddress = derivedPda.toBase58();

      final walletData = await authProvider.smartWalletService.getSmartWalletData(_smartWalletPdaAddress!);

      if (walletData != null && walletData['is_initialized'] == true) {
        setState(() {
          _incrementAmountController.text = (walletData['increment_amount'] ~/ 1_000_000).toString();
          _maxTokensPerRunController.text = walletData['max_tokens_per_run'].toString();
          _emailController.text = walletData['user_email'];
          _enableNotifications = walletData['email_notifications'];
          _statusMessage = 'Smart wallet data loaded from $_smartWalletPdaAddress';
        });
      } else {
        setState(() {
          _statusMessage = 'No smart wallet found for ${authProvider.walletAddress!}. Ready to create.';
          _incrementAmountController.clear();
          _maxTokensPerRunController.clear();
          _emailController.clear();
          _enableNotifications = true;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error loading smart wallet data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Form Actions ---

  Future<void> _createOrUpdateSmartWallet() async {
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _statusMessage = "Please fix form errors.";
      });
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn || authProvider.walletAddress == null) {
      setState(() {
        _statusMessage = "Please connect your wallet first.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = _smartWalletPdaAddress == null
          ? 'Creating smart wallet... Please confirm in Solflare.'
          : 'Updating smart wallet settings... Please confirm in Solflare.';
    });

    try {
      final incrementAmount = int.parse(_incrementAmountController.text) * 1_000_000; // Convert to lamports
      final maxTokensPerRun = int.parse(_maxTokensPerRunController.text);
      final email = _emailController.text;

      if (_smartWalletPdaAddress == null) {
        // Create new smart wallet
        final pda = await authProvider.smartWalletService.createSmartWallet(
          incrementAmount: incrementAmount,
          maxTokensPerRun: maxTokensPerRun,
          email: email,
          enableNotifications: _enableNotifications,
        );
        setState(() {
          _smartWalletPdaAddress = pda;
          _statusMessage = 'Smart wallet created successfully at $pda!';
        });
      } else {
        // Update existing smart wallet
        await authProvider.smartWalletService.updateSmartWalletSettings(
          walletPdaAddress: _smartWalletPdaAddress!,
          incrementAmount: incrementAmount,
          maxTokensPerRun: maxTokensPerRun,
          email: email,
          enableNotifications: _enableNotifications,
        );
        setState(() {
          _statusMessage = 'Smart wallet settings updated successfully!';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Transaction failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelSmartWallet() async {
    if (_smartWalletPdaAddress == null) {
      setState(() {
        _statusMessage = "No smart wallet to cancel.";
      });
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn || authProvider.walletAddress == null) {
      setState(() {
        _statusMessage = "Please connect your wallet first.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Cancelling smart wallet... Please confirm in Solflare.';
    });

    try {
      await authProvider.smartWalletService.cancelSmartWallet(walletPdaAddress: _smartWalletPdaAddress!);
      setState(() {
        _smartWalletPdaAddress = null; // Clear PDA as it's now closed
        _incrementAmountController.clear();
        _maxTokensPerRunController.clear();
        _emailController.clear();
        _enableNotifications = true;
        _statusMessage = 'Smart wallet cancelled successfully. Funds reclaimed!';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Cancellation failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerSingleWalletProcessing() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn || authProvider.walletAddress == null) {
      setState(() {
        _statusMessage = "Please connect your wallet first.";
      });
      return;
    }
    if (_smartWalletPdaAddress == null) {
      setState(() {
        _statusMessage = "No smart wallet found to trigger processing for.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Triggering instant purchase run via GCF...';
    });

    try {
      final result = await authProvider.smartWalletService.triggerSingleWalletProcessing(
        userWalletAddress: authProvider.walletAddress!,
      );
      setState(() {
        _statusMessage = 'GCF triggered: ${result['message'] ?? result}';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error triggering GCF: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Consumer to react to connection state for button enablement
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final isWalletConnected = authProvider.isLoggedIn;

        return Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Form(
                  key: _formKey,
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Smart Wallet Configuration',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          // Display connected wallet and PDA (if any)
                          if (isWalletConnected) ...[
                            Text('Connected Wallet: ${authProvider.walletAddress}',
                                style: const TextStyle(fontSize: 14, color: Colors.green)),
                            const SizedBox(height: 8),
                            if (_smartWalletPdaAddress != null)
                              Text('Smart Wallet PDA: $_smartWalletPdaAddress',
                                  style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
                            const SizedBox(height: 16),
                          ] else
                            Text(
                              'Please connect your wallet to manage your Smart Wallet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: Colors.orange[800]),
                            ),
                          const SizedBox(height: 24),

                          // Configuration Fields
                          TextFormField(
                            controller: _incrementAmountController,
                            keyboardType: TextInputType.number,
                            enabled: isWalletConnected && !_isLoading,
                            decoration: InputDecoration(
                              labelText: 'USDC per Purchase (e.g., 20)',
                              hintText: 'Enter amount in USDC units',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.attach_money),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter an amount';
                              }
                              if (int.tryParse(value) == null || int.parse(value) <= 0) {
                                return 'Please enter a valid positive number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _maxTokensPerRunController,
                            keyboardType: TextInputType.number,
                            enabled: isWalletConnected && !_isLoading,
                            decoration: InputDecoration(
                              labelText: 'Max Tokens per Purchase Run (e.g., 5)',
                              hintText: 'Enter max number of tokens',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.numbers),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a number';
                              }
                              if (int.tryParse(value) == null || int.parse(value) <= 0) {
                                return 'Please enter a valid positive number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            enabled: isWalletConnected && !_isLoading,
                            decoration: InputDecoration(
                              labelText: 'Notification Email',
                              hintText: 'e.g., your@example.com',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.email),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter an email for notifications';
                              }
                              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            title: const Text('Enable Email Notifications'),
                            value: _enableNotifications,
                            onChanged: isWalletConnected && !_isLoading
                                ? (bool value) {
                              setState(() {
                                _enableNotifications = value;
                              });
                            }
                                : null, // Disable if not connected or loading
                            activeColor: Colors.teal,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          const SizedBox(height: 24),

                          // Action Buttons
                          ElevatedButton(
                            onPressed: (isWalletConnected && !_isLoading) ? _createOrUpdateSmartWallet : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _smartWalletPdaAddress == null ? Colors.green : Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading && (_statusMessage.contains('Creating') || _statusMessage.contains('Updating'))
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text(
                              _smartWalletPdaAddress == null
                                  ? 'Create Smart Wallet'
                                  : 'Update Settings',
                              style: const TextStyle(color: Colors.white, fontSize: 18),
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (_smartWalletPdaAddress != null) ...[
                            ElevatedButton(
                              onPressed: (_isLoading || !isWalletConnected) ? null : _cancelSmartWallet,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading && _statusMessage.contains('Cancelling')
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Cancel Smart Wallet & Reclaim Funds',
                                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: (_isLoading || !isWalletConnected) ? null : _triggerSingleWalletProcessing,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading && _statusMessage.contains('Triggering')
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('Trigger Instant Purchase Run (GCF)',
                                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Status Message
                          _statusMessage.isNotEmpty
                              ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            ),
                            child: Text(
                              _statusMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
                            ),
                          )
                              : const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}