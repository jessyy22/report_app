import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;

  const EditProfileScreen({super.key, required this.initialData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late final TextEditingController _nameController;
  late final TextEditingController _licenseController;
  late final TextEditingController _phoneController;

  bool _isSaving = false;
  File? _newAvatarFile;
  File? _newLicenseFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialData['full_name'] ?? '',
    );
    _licenseController = TextEditingController(
      text: widget.initialData['license_number'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.initialData['phone_number'] ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isAvatar) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image != null) {
      setState(() {
        if (isAvatar) {
          _newAvatarFile = File(image.path);
        } else {
          _newLicenseFile = File(image.path);
        }
      });
    }
  }

  Future<String?> _uploadFile(
    File file,
    String bucketName,
    String userId,
  ) async {
    try {
      final fileExt = file.path.split('.').last;
      final fileName =
          '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await _supabase.storage
          .from(bucketName)
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      return _supabase.storage.from(bucketName).getPublicUrl(fileName);
    } catch (e) {
      debugPrint("Error uploading to $bucketName: $e");
      return null;
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      String? avatarUrl =
          widget.initialData['profile_photo_url'] ??
          widget.initialData['avatar_url'];
      String? licenseUrl = widget.initialData['license_photo_url'];

      if (_newAvatarFile != null) {
        final uploadedAvatar = await _uploadFile(
          _newAvatarFile!,
          'driver-avatars',
          user.id,
        );
        if (uploadedAvatar != null) avatarUrl = uploadedAvatar;
      }

      if (_newLicenseFile != null) {
        final uploadedLicense = await _uploadFile(
          _newLicenseFile!,
          'license-photos',
          user.id,
        );
        if (uploadedLicense != null) licenseUrl = uploadedLicense;
      }

      await _supabase
          .from('driver_profiles')
          .update({
            'full_name': _nameController.text.trim(),
            'license_number': _licenseController.text.trim(),
            'phone_number': _phoneController.text.trim(),
            'profile_photo_url': avatarUrl,
            'license_photo_url': licenseUrl,
          })
          .eq('id', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? existingAvatar =
        widget.initialData['profile_photo_url'] ??
        widget.initialData['avatar_url'];
    final String? existingLicense = widget.initialData['license_photo_url'];

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text(
          'Edit Driver Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade700,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- AVATAR PICKER ---
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _newAvatarFile != null
                        ? FileImage(_newAvatarFile!) as ImageProvider
                        : (existingAvatar != null && existingAvatar.isNotEmpty
                              ? NetworkImage(existingAvatar) as ImageProvider
                              : const AssetImage(
                                      'assets/images/placeholder_avatar.png',
                                    )
                                    as ImageProvider),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Colors.green.shade700,
                      radius: 18,
                      child: IconButton(
                        icon: const Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: Colors.white,
                        ),
                        onPressed: () => _pickImage(true),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Full Name",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _licenseController,
              decoration: InputDecoration(
                labelText: "License Number",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: "Phone Number",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- LICENSE PHOTO UPLOAD SECTION ---
            const Text(
              "Driver's License Photo",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _pickImage(false),
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  image: _newLicenseFile != null
                      ? DecorationImage(
                          image: FileImage(_newLicenseFile!),
                          fit: BoxFit.cover,
                        )
                      : (existingLicense != null && existingLicense.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(existingLicense),
                                fit: BoxFit.cover,
                              )
                            : null),
                ),
                child:
                    (_newLicenseFile == null &&
                        (existingLicense == null || existingLicense.isEmpty))
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            "Tap to upload license photo",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      )
                    : Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          margin: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "SAVE CHANGES",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
