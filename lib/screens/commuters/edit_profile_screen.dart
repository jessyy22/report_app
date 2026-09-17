import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;

  const EditProfileScreen({super.key, required this.initialData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final supabase = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  File? _imageFile;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _nameController.text = widget.initialData['full_name']?.toString() ?? '';

    // Support both column names in case older records used "phone".
    final phoneNumber =
        widget.initialData['phone_number']?.toString() ??
        widget.initialData['phone']?.toString() ??
        '';

    _phoneController.text = phoneNumber;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // PICK PROFILE PHOTO
  // ------------------------------------------------------------

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(context, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context, ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (picked == null || !mounted) return;

      setState(() {
        _imageFile = File(picked.path);
      });
    } catch (e) {
      debugPrint('IMAGE PICKER ERROR: $e');
      _showError('Unable to select the image.');
    }
  }

  // ------------------------------------------------------------
  // UPDATE PROFILE
  // ------------------------------------------------------------

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = supabase.auth.currentUser;

    if (user == null) {
      _showError('You are not logged in.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      String? photoUrl = widget.initialData['profile_photo_url']?.toString();

      // --------------------------------------------------------
      // UPLOAD NEW PROFILE PHOTO
      // --------------------------------------------------------

      if (_imageFile != null) {
        const bucket = 'user_profiles';

        // Keep profile photos separate from ID verification files.
        final path = 'commuters/${user.id}.jpg';

        await supabase.storage
            .from(bucket)
            .upload(
              path,
              _imageFile!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );

        photoUrl = supabase.storage.from(bucket).getPublicUrl(path);
      }

      // --------------------------------------------------------
      // UPDATE COMMUTER PROFILE
      // --------------------------------------------------------

      await supabase
          .from('commuter_profiles')
          .update({
            'full_name': _nameController.text.trim(),
            'phone_number': _phoneController.text.trim(),
            'profile_photo_url': photoUrl,
          })
          .eq('id', user.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully.'),
          backgroundColor: Color(0xFF00B14F),
        ),
      );

      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      debugPrint('SUPABASE PROFILE ERROR:');
      debugPrint('Code: ${e.code}');
      debugPrint('Message: ${e.message}');
      debugPrint('Details: ${e.details}');
      debugPrint('Hint: ${e.hint}');

      _showError(
        'Unable to update your profile. Please check your account permissions.',
      );
    } catch (e) {
      debugPrint('UPDATE COMMUTER PROFILE ERROR: $e');

      _showError('Failed to update profile. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ------------------------------------------------------------
  // ERROR MESSAGE
  // ------------------------------------------------------------

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final currentPhoto =
        widget.initialData['profile_photo_url']?.toString().trim() ?? '';

    final photoUrl = currentPhoto.isNotEmpty
        ? '$currentPhoto?t=${DateTime.now().millisecondsSinceEpoch}'
        : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: const Color(0xFF00B14F),
        foregroundColor: Colors.white,
      ),

      body: Form(
        key: _formKey,

        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: Column(
            children: [
              // ------------------------------------------------
              // PROFILE PHOTO
              // ------------------------------------------------
              GestureDetector(
                onTap: _isSaving ? null : _pickImage,

                child: Stack(
                  alignment: Alignment.bottomRight,

                  children: [
                    CircleAvatar(
                      radius: 62,
                      backgroundColor: Colors.grey.shade200,

                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!)
                          : photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : null,

                      child: _imageFile == null && photoUrl.isEmpty
                          ? const Icon(
                              Icons.person_outline,
                              size: 48,
                              color: Colors.grey,
                            )
                          : null,
                    ),

                    Container(
                      width: 38,
                      height: 38,

                      decoration: BoxDecoration(
                        color: const Color(0xFF00B14F),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),

                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Tap the photo to change your profile picture',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),

              const SizedBox(height: 30),

              // ------------------------------------------------
              // FULL NAME
              // ------------------------------------------------
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,

                decoration: _inputDec('Full Name', Icons.person_outline),

                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Full name is required.';
                  }

                  if (value.trim().length < 2) {
                    return 'Please enter a valid name.';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 16),

              // ------------------------------------------------
              // PHONE NUMBER
              // ------------------------------------------------
              TextFormField(
                controller: _phoneController,

                keyboardType: TextInputType.phone,

                decoration: _inputDec('Phone Number', Icons.phone_outlined),

                validator: (value) {
                  final phone = value?.trim() ?? '';

                  if (phone.isEmpty) {
                    return 'Phone number is required.';
                  }

                  if (!RegExp(r'^(09|\+639)\d{9}$').hasMatch(phone)) {
                    return 'Enter a valid Philippine phone number.';
                  }

                  return null;
                },
              ),

              const SizedBox(height: 30),

              // ------------------------------------------------
              // ID INFORMATION
              // ------------------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(.08),

                  borderRadius: BorderRadius.circular(14),

                  border: Border.all(color: Colors.orange.withOpacity(.25)),
                ),

                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Icon(Icons.verified_user_outlined, color: Colors.orange),

                    SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            'Verification ID',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),

                          SizedBox(height: 5),

                          Text(
                            'Your submitted ID is kept securely for account verification. It cannot be changed from the Edit Profile screen.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // ------------------------------------------------
              // SAVE BUTTON
              // ------------------------------------------------
              SizedBox(
                width: double.infinity,
                height: 52,

                child: ElevatedButton(
                  onPressed: _isSaving ? null : _updateProfile,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B14F),

                    foregroundColor: Colors.white,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),

                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,

                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'SAVE CHANGES',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: _isSaving ? null : () => Navigator.pop(context),

                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // INPUT DECORATION
  // ------------------------------------------------------------

  InputDecoration _inputDec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,

      prefixIcon: Icon(icon, color: const Color(0xFF00B14F)),

      filled: true,
      fillColor: Colors.white,

      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),

        borderSide: BorderSide(color: Colors.grey.shade300),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),

        borderSide: const BorderSide(color: Color(0xFF00B14F), width: 2),
      ),
    );
  }
}
