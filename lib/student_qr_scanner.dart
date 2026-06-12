import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class StudentQRScanner extends StatefulWidget {
  const StudentQRScanner({super.key});

  @override
  State<StudentQRScanner> createState() => _StudentQRScannerState();
}

class _StudentQRScannerState extends State<StudentQRScanner> {
  bool scanned = false;

  Future<void> markAttendance(String tripId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String studentId = user.uid;

    await FirebaseDatabase.instance.ref("attendance").push().set({
      "studentId": studentId,
      "tripId": tripId,
      "time": DateTime.now().toIso8601String(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("✅ Attendance Marked")));

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Bus QR")),
      body: MobileScanner(
        onDetect: (BarcodeCapture capture) {
          if (scanned) return;

          final List<Barcode> barcodes = capture.barcodes;

          for (final barcode in barcodes) {
            final String? code = barcode.rawValue;

            if (code != null) {
              scanned = true;
              markAttendance(code);
              break;
            }
          }
        },
      ),
    );
  }
}
