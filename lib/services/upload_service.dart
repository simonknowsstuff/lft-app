import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';

class UploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<void> processLoanVerification({
    required File billFile,
    required List<File> assetImages,
  }) async {
    // 1. Get Geostamp
    Position pos = await Geolocator.getCurrentPosition();
    String timestamp = DateTime.now().toIso8601String();

    // 2. Upload Bill
    String billPath = 'bills/${DateTime.now().millisecondsSinceEpoch}.pdf';
    await _storage.ref(billPath).putFile(billFile);

    // 3. Upload Assets with Metadata
    List<String> assetPaths = [];
    for (int i = 0; i < assetImages.length; i++) {
      String path = 'assets/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      await _storage.ref(path).putFile(
        assetImages[i],
        SettableMetadata(customMetadata: {
          'lat': pos.latitude.toString(),
          'lng': pos.longitude.toString(),
          'time': timestamp,
        }),
      );
      assetPaths.add(path);
    }

    // 4. Trigger Cloud Function (Callable)
    final callable = _functions.httpsCallable('pushContent');
    await callable.call({
      'billPath': billPath,
      'assetPaths': assetPaths,
      'location': {'lat': pos.latitude, 'lng': pos.longitude},
    });
  }
}