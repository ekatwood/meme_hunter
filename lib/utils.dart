import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart'; // Import for NumberFormat
import 'package:firebase_remote_config/firebase_remote_config.dart';

Future<String> getRemoteConfigValue(String parameter) async {
  final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.fetchAndActivate();
  return remoteConfig.getString(parameter);
}

// Helper function to launch URLs
void launchURL(String? url) async {
  if (url == null || url.isEmpty) return;
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    print('Could not launch ${url}');
  }
}

// Function to copy text to clipboard and show SnackBar
void copyToClipboard(String text, BuildContext context) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text(
        "Address copied to clipboard.",
        style: TextStyle(fontWeight: FontWeight.bold),
      )
    ),
  );
}

String convertTimestampToFormattedString(String timestampString) {
  try {
    DateTime dateTime = DateTime.parse(timestampString);

    DateFormat formatter = DateFormat('MMM d h:mm a');

    return formatter.format(dateTime) + ' EST';
  } catch (e) {
    // Handle any parsing errors gracefully.
    return 'Error converting timestamp: $e';
  }
}

String formatBigNumber(String? numString) {
  if (numString == null || numString.isEmpty) {
    return 'N/A';
  }

  String processedNumString = numString;

  // Step 1: Check for '.' and strip everything after it
  if (processedNumString.contains('.')) {
    processedNumString = processedNumString.split('.').first;
  }

  try {
    final BigInt value = BigInt.parse(processedNumString);

    // Define constants for magnitude checks using BigInt
    final BigInt thousand = BigInt.from(1000);
    final BigInt million = BigInt.from(1000000);
    final BigInt billion = BigInt.from(1000000000);
    final BigInt trillion = BigInt.from(1000000000000);

    if (value < thousand) {
      // Numbers less than 1,000 (e.g., 999)
      return value.toString(); // No commas needed, BigInt.toString() is fine
    } else if (value < million) {
      // Thousands (e.g., 1,234; 123,456)
      final formatter = NumberFormat('#,##0', 'en_US'); // Use #,##0 for comma formatting
      // CORRECTED: Convert BigInt to int for NumberFormat
      return formatter.format(value.toInt());
    } else if (value < billion) {
      // Millions (e.g., 1.23M; 123.45M)
      final double millions = value.toDouble() / million.toDouble();
      return '${millions.toStringAsFixed(2)}M';
    } else if (value < trillion) {
      // Billions (e.g., 1.23B; 123.45B)
      final double billions = value.toDouble() / billion.toDouble();
      return '${billions.toStringAsFixed(2)}B';
    } else {
      // Trillions (e.g., 1.23T; 123.45T)
      final double trillions = value.toDouble() / trillion.toDouble();
      return '${trillions.toStringAsFixed(2)}T';
    }
  } catch (e) {
    // Handle parsing errors (e.g., if numString is not a valid integer string after stripping)
    print('Error parsing or formatting number: $numString, Processed: $processedNumString, Error: $e');
    return 'Invalid Data';
  }
}