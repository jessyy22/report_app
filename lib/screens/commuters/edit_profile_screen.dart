import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ⚠️ Adjust this import path to match your project structure
import '../../theme/app_theme.dart';

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
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();

    _nameController.text =
        widget.initialData['full_name']?.toString() ?? '';

    // Support both column names in case older records used "phone".
    final phoneNumber = widget.initialData['phone_number']?.toString() ??
        widget.initialData['phone']?.toString() ??
        '';
    _phoneController.text = phoneNumber;

    _nameController.addListener(_markDirty);
    _phoneController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_hasUnsavedChanges && mounted) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  // ------------------------------------------------------------
  // PICK PROFILE PHOTO
  // ------------------------------------------------------------
  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
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
        _hasUnsavedChanges = true;
      });
    } catch (e) {
      debugPrint('IMAGE PICKER ERROR: $e');
      _showError('Unable to select the image.');
    }
  }

  void _removeNewPhoto() {
    setState(() {
      _imageFile = null;
      _hasUnsavedChanges = true;
    });
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

    setState(() => _isSaving = true);

    try {
      String? photoUrl =
          widget.initialData['profile_photo_url']?.toString();

      // --------------------------------------------------------
      // UPLOAD NEW PROFILE PHOTO
      // --------------------------------------------------------
      if (_imageFile != null) {
        const bucket = 'user_profiles';
        final path = 'commuters/${user.id}.jpg';

        await supabase.storage.from(bucket).upload(
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
      final cleanedPhone = _phoneController.text
          .trim()
          .replaceAll(RegExp(r'[^\d+]'), '');

      await supabase.from('commuter_profiles').update({
        'full_name': _nameController.text.trim(),
        'phone_number': cleanedPhone,
        'profile_photo_url': photoUrl,
      }).eq('id', user.id);

      if (!mounted) return;

      // Pop FIRST — the parent shows the success snackbar so it doesn't
      // get dismissed by the route pop.
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ------------------------------------------------------------
  // ERROR MESSAGE
  // ------------------------------------------------------------
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
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

    return PopScope(
      canPop: !_hasUnsavedChanges && !_isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_isSaving) {
          _showError('Please wait for the save to complete.');
          return;
        }
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('Your edits will not be saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('KEEP EDITING'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('DISCARD'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // =====================================================
                  // PROFILE PHOTO
                  // =====================================================
                  Semantics(
                    button: true,
                    label: 'Change profile photo',
                    child: GestureDetector(
                      onTap: _isSaving ? null : _pickImage,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 62,
                            backgroundColor: AppColors.greenSoft,
                            backgroundImage: _imageFile != null
                                ? FileImage(_imageFile!)
                                : photoUrl.isNotEmpty
                                    ? NetworkImage(photoUrl)
                                    : null,
                            child:
                                _imageFile == null && photoUrl.isEmpty
                                    ? const Icon(
                                        Icons.person_outline,
                                        size: 48,
                                        color: AppColors.green,
                                      )
                                    : null,
                          ),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
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
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Tap the photo to change your profile picture',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),

                  if (_imageFile != null) ...[
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _isSaving ? null : _removeNewPhoto,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Remove new photo'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // =====================================================
                  // FULL NAME
                  // =====================================================
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 80,
                    decoration: _inputDec(
                      'Full Name',
                      Icons.person_outline,
                    ),
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

                  // =====================================================
                  // PHONE NUMBER
                  // =====================================================
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9+\s\-()]'),
                      ),
                    ],
                    decoration: _inputDec(
                      'Phone Number',
                      Icons.phone_outlined,
                    ),
                    validator: (value) {
                      final raw = value?.trim() ?? '';
                      if (raw.isEmpty) {
                        return 'Phone number is required.';
                      }
                      final digits =
                          raw.replaceAll(RegExp(r'[^\d+]'), '');
                      final ok = RegExp(r'^(09\d{9}|\+?639\d{9})$')
                          .hasMatch(digits);
                      if (!ok) {
                        return 'Enter a valid PH number '
                            '(e.g., 0917 123 4567).';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 32),

                  // =====================================================
                  // ID INFORMATION
                  // =====================================================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.greenSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          color: AppColors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Verification ID',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Your submitted ID is kept securely '
                                'for account verification. It cannot '
                                'be changed from the Edit Profile '
                                'screen.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // =====================================================
                  // SAVE BUTTON
                  // =====================================================
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: Semantics(
                      button: true,
                      label: _isSaving
                          ? 'Saving profile'
                          : 'Save profile changes',
                      child: FilledButton(
                        onPressed: _isSaving ? null : _updateProfile,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSaving
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'SAVING…',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'SAVE CHANGES',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // =====================================================
                  // CANCEL
                  // =====================================================
                  TextButton(
                    onPressed:
                        _isSaving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.muted,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
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
      prefixIcon: Icon(icon, color: AppColors.green),
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.green, width: 1.5),
      ),
    );
  }
}