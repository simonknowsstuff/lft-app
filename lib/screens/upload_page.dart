import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  File? _billFile;
  final List<File> _assetImages = [];
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  // --- LOGOUT LOGIC ---
  Future<void> _logout() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("LOGOUT", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  // --- VALIDATION ---
  bool get _isValid => _billFile != null && _assetImages.length >= 3;

  // --- FILE PICKING ---
  Future<void> _pickBill() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null) {
      setState(() => _billFile = File(result.files.single.path!));
    }
  }

  Future<void> _pickAssets() async {
    final List<XFile> images = await _picker.pickMultiImage(imageQuality: 50);
    if (images.isNotEmpty) {
      setState(() => _assetImages.addAll(images.map((img) => File(img.path))));
    }
  }

  // --- UPLOAD LOGIC ---
  Future<void> _handleSubmit() async {
    setState(() => _isUploading = true);
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String userId = FirebaseAuth.instance.currentUser!.uid;

      // Upload Bill
      String billName = "bill_${DateTime.now().millisecondsSinceEpoch}.pdf";
      await FirebaseStorage.instance.ref('loans/$userId/$billName').putFile(_billFile!);

      // Upload Assets with Geotags
      for (var i = 0; i < _assetImages.length; i++) {
        String assetName = "asset_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        await FirebaseStorage.instance.ref('loans/$userId/$assetName').putFile(
          _assetImages[i],
          SettableMetadata(customMetadata: {
            'lat': pos.latitude.toString(),
            'lng': pos.longitude.toString(),
            'timestamp': DateTime.now().toIso8601String(),
            'userId': userId,
          }),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload Successful!")));
      setState(() { _billFile = null; _assetImages.clear(); });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Loan For Tomorrow", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: _logout)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildPanel(
              title: "Purchase Bill / Invoice",
              subtitle: _billFile == null ? "PDF or Image required" : "Attached: ${_billFile!.path.split('/').last}",
              icon: Icons.receipt_long,
              isDone: _billFile != null,
              onTap: _pickBill,
            ),
            const SizedBox(height: 20),
            _buildAssetPanel(),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                onPressed: (_isValid && !_isUploading) ? _handleSubmit : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
                child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text("SUBMIT EVIDENCE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel({required String title, required String subtitle, required IconData icon, required bool isDone, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isDone ? Colors.green : Colors.blueAccent.withOpacity(0.3)),
          color: isDone ? Colors.green.withOpacity(0.05) : Colors.blue.withOpacity(0.02),
        ),
        child: Row(
          children: [
            Icon(icon, color: isDone ? Colors.green : Colors.blueAccent),
            const SizedBox(width: 15),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), Text(subtitle, style: const TextStyle(fontSize: 12))])),
            Icon(isDone ? Icons.check_circle : Icons.add_circle, color: isDone ? Colors.green : Colors.blueAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetPanel() {
    bool isDone = _assetImages.length >= 3;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isDone ? Colors.green : Colors.orange.withOpacity(0.3)),
        color: isDone ? Colors.green.withOpacity(0.05) : Colors.orange.withOpacity(0.02),
      ),
      child: Column(
        children: [
          Row(children: [const Icon(Icons.camera_alt), const SizedBox(width: 10), const Text("Asset Photos (Min 3)", style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), Text("${_assetImages.length}/3")]),
          const SizedBox(height: 10),
          if (_assetImages.isNotEmpty)
            SizedBox(
              height: 70,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _assetImages.length,
                itemBuilder: (ctx, i) => Padding(padding: const EdgeInsets.only(right: 8), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(_assetImages[i], width: 70, height: 70, fit: BoxFit.cover))),
              ),
            ),
          TextButton(onPressed: _pickAssets, child: const Text("Add Images")),
        ],
      ),
    );
  }
}