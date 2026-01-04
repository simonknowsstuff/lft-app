import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;

class UploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<void> processLoanVerification({
    required File billFile,
    required List<File> assetImages,
  }) async {
    // 1. Prepare shared metadata
    Position pos = await Geolocator.getCurrentPosition();
    String timestamp = DateTime.now().toIso8601String();
    String uid = FirebaseAuth.instance.currentUser!.uid;
    // TODO: Loan ID seems to not be uploading properly
    String loanId = "LOAN_${DateTime.now().millisecondsSinceEpoch}";

    final metadata = SettableMetadata(
      customMetadata: {
        'lat': pos.latitude.toString(),
        'lng': pos.longitude.toString(),
        'time': timestamp,
        'userId': uid,
        'loanId': loanId,
      },
    );

    String extension = p.extension(billFile.path).toLowerCase();
    String billMimeType = (extension == '.pdf') ? 'application/pdf' : 'image/jpeg';

    final billMeta = SettableMetadata(
      contentType: billMimeType,
      customMetadata: {
        'lat': pos.latitude.toString(),
        'lng': pos.longitude.toString(),
        'time': timestamp,
        'userId': uid,
        'loanId': loanId,
      },
    );

    UploadTask billTask = _storage.ref('loans/$loanId/bill.pdf').putFile(billFile, billMeta);
    await billTask;

    // 3. Upload Assets
    for (int i = 0; i < assetImages.length; i++) {
      Reference ref = _storage.ref('loans/$loanId/assets_$i.jpg');
      UploadTask assetTask = ref.putFile(assetImages[i], metadata);
      assetTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (kDebugMode) {
          print('Progress: ${snapshot.bytesTransferred / snapshot.totalBytes}');
        }
      });
      await assetTask;
      if (kDebugMode) {
        print("Uploaded asset $i with loanId: $loanId");
      }
    }
  }
}
