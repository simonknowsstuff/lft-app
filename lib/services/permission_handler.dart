import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

class PermissionService {
  /// Checks all location requirements for "Loan For Tomorrow"
  /// Returns 'true' if everything (GPS, Permission, Accuracy) is perfect.
  static Future<bool> checkLocationRequirements(BuildContext context) async {
    // 1. Check if GPS is actually turned on
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar(context, "Please enable GPS/Location services.");
      return false;
    }

    // 2. Check current permission status
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar(context, "Location permission is required for verification.");
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar(context, "Location permissions are permanently denied. Enable in settings.");
      return false;
    }

    // 3. Check for Precise Accuracy (Android 12+ / iOS 14+)
    // This is the "Fraud Prevention" check
    final accuracy = await Geolocator.getLocationAccuracy();
    if (accuracy == LocationAccuracyStatus.reduced) {
      _showPreciseRequiredDialog(context);
      return false;
    }

    return true;
  }

  static void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  static void _showPreciseRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Precise Location Needed"),
        content: const Text(
            "Our AI verification requires high-precision GPS to confirm your asset's location. "
                "Please enable 'Precise Location' in your app settings."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () {
              Geolocator.openAppSettings();
              Navigator.pop(context);
            },
            child: const Text("OPEN SETTINGS"),
          ),
        ],
      ),
    );
  }
}