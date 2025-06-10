import 'package:flutter/material.dart';

/// A Flutter web form for configuring a Smart Escrow Wallet.
///
/// This widget provides the UI for users to input parameters for their
/// automated token purchase smart wallet. It is designed to be integrated
/// into a larger Flutter application that handles wallet connection and
/// interaction with the Solana program.
class SmartEscrowWallet extends StatefulWidget {
  const SmartEscrowWallet({super.key});

  @override
  State<SmartEscrowWallet> createState() => _SmartEscrowWalletState();
}

class _SmartEscrowWalletState extends State<SmartEscrowWallet> {
  // Controllers for the text input fields
  final TextEditingController _incrementAmountController = TextEditingController();
  final TextEditingController _maxTokensPerRunController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // State for the notification switch
  bool _enableNotifications = true;

  // A global key to hold the state of the form for validation
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    // Dispose controllers to prevent memory leaks
    _incrementAmountController.dispose();
    _maxTokensPerRunController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Placeholder for the form submission logic.
  /// This method will be expanded in the next steps to interact with Solana.
  void _submitForm() {
    // Validate all form fields
    if (_formKey.currentState!.validate()) {
      // If the form is valid, collect the data
      final int? incrementAmount = int.tryParse(_incrementAmountController.text);
      final int? maxTokensPerRun = int.tryParse(_maxTokensPerRunController.text);
      final String email = _emailController.text;
      final bool enableNotifications = _enableNotifications;

      // TODO: Implement the logic to create or update the smart wallet
      // This will involve calling your SmartWalletService
      // For now, let's just print the collected data to the console.
      print('--- Form Submitted ---');
      print('Increment Amount: ${incrementAmount ?? 'Not set'}');
      print('Max Tokens per Run: ${maxTokensPerRun ?? 'Not set'}');
      print('Notification Email: $email');
      print('Enable Notifications: $enableNotifications');

      // Example: Show a simple confirmation or status message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form submitted (Logic TBD)!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar needed here, as it's assumed to be provided by parent widget
      // that handles wallet connection.
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form( // Wrap with Form for validation
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

                      // Increment Amount Field
                      TextFormField(
                        controller: _incrementAmountController,
                        keyboardType: TextInputType.number,
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

                      // Max Tokens Per Run Field
                      TextFormField(
                        controller: _maxTokensPerRunController,
                        keyboardType: TextInputType.number,
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

                      // Notification Email Field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
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
                          // Basic email regex for demonstration
                          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Enable Notifications Switch
                      SwitchListTile(
                        title: const Text('Enable Email Notifications'),
                        value: _enableNotifications,
                        onChanged: (bool value) {
                          setState(() {
                            _enableNotifications = value;
                          });
                        },
                        activeColor: Colors.teal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      ElevatedButton(
                        onPressed: _submitForm, // Calls the stubbed method
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save Smart Wallet Settings',
                            style: TextStyle(color: Colors.white, fontSize: 18)),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
