import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  @override
  void dispose() {
    _amountController.dispose();
    _borrowerNameController.dispose();
    super.dispose();
  }

  // --- LOGOUT ---
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
    if (confirm == true) await FirebaseAuth.instance.signOut();
  }

  // --- VALIDATION ---
  bool get _isValid =>
      _billFile != null &&
          _assetImages.length >= 3 &&
          _selectedAssetType != null &&
          _borrowerNameController.text.isNotEmpty &&
          _amountController.text.isNotEmpty;

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
    bool isReady = await PermissionService.checkLocationRequirements(context);
    if (!isReady) return;

    setState(() => _isUploading = true);

    try {
      await _uploadService.processLoanVerification(
        billFile: _billFile!,
        assetImages: _assetImages,
        loanAmount: double.tryParse(_amountController.text) ?? 0.0,
        borrowerName: _borrowerNameController.text,
        selectedAssetType: _selectedAssetType!,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Audit Submitted! Check 'My Loans' for results.")),
      );

      setState(() {
        _billFile = null;
        _assetImages.clear();
        _amountController.clear();
        _borrowerNameController.clear();
        _selectedAssetType = null;
      });

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
        actions: [
          IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              onPressed: _isUploading ? null : _logout
          )
        ],
      ),
      // AbsorbPointer completely blocks interaction during upload
      body: AbsorbPointer(
        absorbing: _isUploading,
        child: Opacity(
          opacity: _isUploading ? 0.6 : 1.0,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildTextField(_borrowerNameController, "Borrower's Full Name", Icons.person),
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
                const SizedBox(height: 20),

                _buildTextField(_amountController, "Loan Amount", Icons.attach_money, isNumber: true),
                const SizedBox(height: 20),

                DropdownButtonFormField<String>(
                  value: _selectedAssetType,
                  decoration: const InputDecoration(
                    labelText: "Select Asset Type",
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(15))),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: _assetTypes.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.toUpperCase())
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedAssetType = val),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: (_isValid && !_isUploading) ? _handleSubmit : null,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                    child: _isUploading
                        ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 15),
                        Text("AI FORENSIC AUDIT...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    )
                        : const Text("SUBMIT FOR VERIFICATION", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 20),
                TextButton(
                  onPressed: _isUploading ? null : () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoansPage())),
                  child: const Text("VIEW MY LOAN STATUS", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNumber = false}) {
    return TextFormField(
      controller: controller,
      enabled: !_isUploading,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  Widget _buildPanel({required String title, required String subtitle, required IconData icon, required bool isDone, required VoidCallback onTap}) {
    return InkWell(
      onTap: _isUploading ? null : onTap,
      borderRadius: BorderRadius.circular(15),
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
          Row(children: [const Icon(Icons.camera_alt, color: Colors.orange), const SizedBox(width: 10), const Text("Asset Photos (Min 3)", style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), Text("${_assetImages.length}/3")]),
          const SizedBox(height: 10),
          if (_assetImages.isNotEmpty)
            SizedBox(
              height: 70,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _assetImages.length,
                itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(_assetImages[i], width: 70, height: 70, fit: BoxFit.cover))
                ),
              ),
            ),
          TextButton(
              onPressed: _isUploading ? null : _pickAssets,
              child: Text(_assetImages.isEmpty ? "Add Images" : "Add More Images")
          ),
        ],
      ),
    );
  }
}