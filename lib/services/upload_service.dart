import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:native_exif/native_exif.dart'; // Add this import

class UploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Helper method to extract EXIF timestamp
  Future<String> _getExifTimestamp(File file) async {
    try {
      final exif = await Exif.fromPath(file.path);
      final DateTime? date = await exif.getOriginalDate();
      await exif.close();

      if (date != null) {
        return date.toUtc().toIso8601String();
      }
    } catch (e) {
      print("Error extracting EXIF: $e");
    }
    // Fallback if no EXIF data is found
    return DateTime.now().toUtc().toIso8601String();
  }

  Future<void> processLoanVerification({
    required File billFile,
    required List<File> assetImages,
    required double loanAmount,
    required String borrowerName,
    required String selectedAssetType,
  }) async {
    Position pos = await Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(accuracy: LocationAccuracy.best),
    );

    String uid = FirebaseAuth.instance.currentUser!.uid;
    String loanId = "LN_${DateTime.now().millisecondsSinceEpoch}";

    // 2. Upload the Bill
    String billExt = p.extension(billFile.path).toLowerCase();
    String billMime = (billExt == '.pdf') ? 'application/pdf' : 'image/jpeg';

    // For bills, we usually use current time as they might not have EXIF
    String billTimestamp = DateTime.now().toUtc().toIso8601String();

    final billMeta = SettableMetadata(
      contentType: billMime,
      customMetadata: {
        'lat': pos.latitude.toString(),
        'lng': pos.longitude.toString(),
        'time': billTimestamp,
        'userId': uid,
        'loanId': loanId,
        'loanAmount': loanAmount.toString(),
        'borrowerName': borrowerName,
        'selectedAssetType': selectedAssetType,
        'isBill': 'true',
      },
    );

    await _storage.ref('loans/$uid/$loanId/bill_document$billExt').putFile(billFile, billMeta);

    // 3. Upload Asset Images with EXIF Timestamps
    for (int i = 0; i < assetImages.length; i++) {
      // EXTRACT ACTUAL PHOTO TIME HERE
      String assetTimestamp = await _getExifTimestamp(assetImages[i]);

      final assetMeta = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'lat': pos.latitude.toString(),
          'lng': pos.longitude.toString(),
          'time': assetTimestamp, // Real capture time
          'userId': uid,
          'loanId': loanId,
          'loanAmount': loanAmount.toString(),
          'selectedAssetType': selectedAssetType,
          'borrowerName': borrowerName,
        },
      );

      await _storage
          .ref('loans/$uid/$loanId/asset_$i.jpg')
          .putFile(assetImages[i], assetMeta);
    }
  }
}