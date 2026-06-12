import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class DriverQRScreen extends StatelessWidget {
  final String tripId;
  const DriverQRScreen({super.key, required this.tripId});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bus QR Code")),
      body: Center(child: QrImageView(data: tripId, size: 250)),
    );
  }
}
