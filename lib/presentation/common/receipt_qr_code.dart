import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Encodes the existing server-issued reference, without personal or cash data.
/// Scanning reads the reference; it does not itself authenticate a receipt.
class ReceiptQrCode extends StatelessWidget {
  final String verificationCode;

  const ReceiptQrCode({required this.verificationCode, super.key});

  @override
  Widget build(BuildContext context) {
    if (verificationCode.trim().isEmpty) {
      return const Text('Scannable reference unavailable.');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Center(
          child: QrImageView(
            data: verificationCode,
            size: 200,
            // At least four modules of white quiet zone, even for version 1.
            // Keep black modules on white in either app theme.
            padding: const EdgeInsets.all(32),
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
            semanticsLabel: 'Receipt reference QR code: $verificationCode',
            errorStateBuilder: (_, _) =>
                const Center(child: Text('Use the written receipt reference.')),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Scan to read the receipt reference',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
