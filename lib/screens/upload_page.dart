import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lftapp/screens/loans_page.dart';
import 'package:lftapp/services/permission_handler.dart';
import 'package:lftapp/services/upload_service.dart';

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
  final UploadService _uploadService = UploadService();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _borrowerNameController = TextEditingController();
  final List<String> _assetTypes = ["general", "vehicle", "real_estate", "agricultural"];
  String? _selectedAssetType;

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
    final List<XFile> images = await _picker.pickMultiImage(
      imageQuality: 50,
      maxWidth: 1000,
    );
    if (images.isNotEmpty) {
      setState(() => _assetImages.addAll(images.map((img) => File(img.path))));
    }
  }

  // --- UPLOAD LOGIC ---
  Future<void> _handleSubmit() async {
    bool isReady = await PermissionService.checkLocationRequirements(context);
    if (!isReady) return;

    setState(() => _isUploading = true);

    try {
      // 2. Call the dedicated UploadService
      await _uploadService.processLoanVerification(
        billFile: _billFile!,
        assetImages: _assetImages,
        loanAmount: double.tryParse(_amountController.text) ?? 0.0,
        borrowerName: _borrowerNameController.text,
        selectedAssetType: _selectedAssetType!,
      );

      // 3. Success UI
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Upload Successful! Verification pending.")),
      );

      setState(() {
        _billFile = null;
        _assetImages.clear();
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _isUploading = false);
      _amountController.text = "";
      _borrowerNameController.text = "";
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
            TextFormField(
              controller: _borrowerNameController,
              decoration: const InputDecoration(
                labelText: "Borrower's name",
                border: OutlineInputBorder(),
                hintText: "Borrower's name",
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter the borrower's name";
                }
                if (value.length < 5) {
                  return "Names cannot be lesser than 5 letters";
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
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
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Loan Amount',
                prefixText: '\Rs ', // Or your local currency symbol
                border: OutlineInputBorder(),
                hintText: '0.00',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter the loan amount';
                }
                if (double.tryParse(value) == null) {
                  return 'Please enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _selectedAssetType,
              decoration: const InputDecoration(
                labelText: "Select Asset Type",
                border: OutlineInputBorder(),
              ),
              items: _assetTypes.map((String type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.toUpperCase()),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedAssetType = value),
              validator: (value) => value == null ? "Please select an asset type" : null,
            ),
            const SizedBox(height: 15),
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
            const SizedBox(height: 15),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoansPage()),
                );
              },
              child: const Text("VIEW MY LOANS", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
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
          border: Border.all(color: isDone ? Colors.green : Colors.blueAccent.withValues(alpha: 0.3)),
          color: isDone ? Colors.green.withValues(alpha: 0.05) : Colors.blue.withValues(alpha: 0.02),
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
        border: Border.all(color: isDone ? Colors.green : Colors.orange.withValues(alpha: 0.3)),
        color: isDone ? Colors.green.withValues(alpha: 0.05) : Colors.orange.withValues(alpha: 0.02),
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
