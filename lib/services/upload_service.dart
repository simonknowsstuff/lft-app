import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;

class UploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<void> processLoanVerification({
    required File billFile,
    required List<File> assetImages,
    required double loanAmount,
    required String borrowerName,
  }) async {
    // 1. Capture one-time data for this entire loan batch
    Position pos = await Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best
      ),
    );
    String timestamp = DateTime.now().toUtc().toIso8601String();
    String uid = FirebaseAuth.instance.currentUser!.uid;
    String loanId = "LN_${DateTime.now().millisecondsSinceEpoch}";

    // 2. Upload the Bill (Detect if PDF or Image)
    String billExt = p.extension(billFile.path).toLowerCase();
    String billMime = (billExt == '.pdf') ? 'application/pdf' : 'image/jpeg';

    final billMeta = SettableMetadata(
      contentType: billMime,
      customMetadata: {
        'lat': pos.latitude.toString(),
        'lng': pos.longitude.toString(),
        'time': timestamp,
        'userId': uid,
        'loanId': loanId,
        'loan_amount': loanAmount.toString(),
        'borrower_name': borrowerName,
        'isBill': 'true',
      },
    );

    await _storage.ref('loans/$uid/$loanId/bill_document$billExt').putFile(billFile, billMeta);

    // 3. Upload Asset Images
    for (int i = 0; i < assetImages.length; i++) {
      final assetMeta = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'lat': pos.latitude.toString(),
          'lng': pos.longitude.toString(),
          'time': timestamp,
          'userId': uid,
          'loanId': loanId,
          'loan_amount': loanAmount.toString(),
          'borrower_name': borrowerName,
        },
      );

      // We use putFile and await it to ensure order
      await _storage
          .ref('loans/$uid/$loanId/asset_$i.jpg')
          .putFile(assetImages[i], assetMeta);
    }
  }
}