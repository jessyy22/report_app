import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;

  const EditProfileScreen({super.key, required this.initialData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _licenseController;
  late final TextEditingController _phoneController;

  bool _isSaving = false;
  bool _hasUnsavedChanges = false;
  File? _newAvatarFile;
  File? _newLicenseFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.initialData['full_name']?.toString() ?? '',
    );
    _licenseController = TextEditingController(
      text: widget.initialData['license_number']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.initialData['phone_number']?.toString() ?? '',
    );

    _nameController.addListener(_markDirty);
    _licenseController.addListener(_markDirty);
    _phoneController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _licenseController.dispose();
    _phoneController.dispose(); // ✅ fixed
    super.dispose();
  }

  void _markDirty() {
    if (!_hasUnsavedChanges && mounted) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  // ============================================================
  // IMAGE PICKING
  // ============================================================
  Future<void> _pickImage(bool isAvatar) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
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
      ),
    );

    if (source == null) return;

    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (image == null || !mounted) return;

      setState(() {
        if (isAvatar) {
          _newAvatarFile = File(image.path);
        } else {
          _newLicenseFile = File(image.path);
        }
        _hasUnsavedChanges = true;
      });
    } catch (e) {
      debugPrint('PICK IMAGE ERROR: $e');
      _showError('Could not select image.');
    }
  }

  // ============================================================
  // UPLOAD
  // ============================================================
  Future<String> _uploadFile(
    File file,
    String bucket,
    String userId,
  ) async {
    final fileExt = file.path.split('.').last.toLowerCase();
    final fileName =
        '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';

    await _supabase.storage.from(bucket).upload(
          fileName,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _mimeFor(fileExt),
          ),
        );

    return _supabase.storage.from(bucket).getPublicUrl(fileName);
  }

  String _mimeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  // ============================================================
  // SAVE
  // ============================================================
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showError('You are not signed in.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? avatarUrl =
          widget.initialData['profile_photo_url']?.toString() ??
              widget.initialData['avatar_url']?.toString();
      String? licenseUrl =
          widget.initialData['license_photo_url']?.toString();

      if (_newAvatarFile != null) {
        avatarUrl = await _uploadFile(
          _newAvatarFile!,
          'driver-avatars',
          user.id,
        );
      }

      if (_newLicenseFile != null) {
        licenseUrl = await _uploadFile(
          _newLicenseFile!,
          'license-photos',
          user.id,
        );
      }

      final cleanedPhone = _phoneController.text
          .trim()
          .replaceAll(RegExp(r'[^\d+]'), '');

      await _supabase.from('driver_profiles').update({
        'full_name': _nameController.text.trim(),
        'license_number': _licenseController.text.trim(),
        'phone_number': cleanedPhone,
        'profile_photo_url': avatarUrl,
        'license_photo_url': licenseUrl,
      }).eq('id', user.id);

      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      debugPrint('DRIVER PROFILE UPDATE ERROR: ${e.code} ${e.message}');
      _showError(
        'Could not save your profile. Please check your permissions.',
      );
    } catch (e) {
      debugPrint('SAVE PROFILE ERROR: $e');
      _showError('Failed to save profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

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

  // ============================================================
  // PREVIEW DIALOGS
  // ============================================================
  void _previewImage({File? file, String? url, String title = 'Preview'}) {
    if (file == null && (url == null || url.isEmpty)) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: file != null
                  ? Image.file(file, fit: BoxFit.contain)
                  : Image.network(url!, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final existingAvatar =
        widget.initialData['profile_photo_url']?.toString() ??
            widget.initialData['avatar_url']?.toString() ??
            '';
    final existingLicense =
        widget.initialData['license_photo_url']?.toString() ?? '';

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
        appBar: AppBar(title: const Text('Edit Driver Profile')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Avatar ────────────────────────────────────
                  Center(
                    child: _avatarPicker(
                      existingAvatar: existingAvatar,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tap the photo to change your profile picture',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Name ─────────────────────────────────────
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 80,
                    decoration: _inputDec(
                      'Full Name',
                      Icons.person_outline,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Full name is required.';
                      }
                      if (v.trim().length < 2) {
                        return 'Enter a valid name.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── License number ───────────────────────────
                  TextFormField(
                    controller: _licenseController,
                    maxLength: 30,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9\-]'),
                      ),
                    ],
                    decoration: _inputDec(
                      'License Number',
                      Icons.badge_outlined,
                    ),
                    validator: (v) {
                      final vv = (v ?? '').trim();
                      if (vv.isEmpty) {
                        return 'License number is required.';
                      }
                      if (vv.length < 5) {
                        return 'License number looks too short.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Phone ────────────────────────────────────
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
                    validator: (v) {
                      final raw = (v ?? '').trim();
                      if (raw.isEmpty) return 'Phone number is required.';
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

                  // ── License photo ────────────────────────────
                  _licensePhotoCard(
                    existingLicense: existingLicense,
                  ),
                  const SizedBox(height: 32),

                  // ── Save ─────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveProfile,
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
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.muted,
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  // ============================================================
  // SUB-WIDGETS
  // ============================================================

  Widget _avatarPicker({required String existingAvatar}) {
    final hasExisting = existingAvatar.isNotEmpty;

    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: GestureDetector(
        onTap: _isSaving ? null : () => _pickImage(true),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.greenSoft,
              ),
              clipBehavior: Clip.antiAlias,
              child: _newAvatarFile != null
                  ? Image.file(_newAvatarFile!, fit: BoxFit.cover)
                  : hasExisting
                      ? Image.network(
                          '$existingAvatar?t=${DateTime.now().millisecondsSinceEpoch}',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            color: AppColors.green,
                            size: 48,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: AppColors.green,
                          size: 48,
                        ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _licensePhotoCard({required String existingLicense}) {
    final hasExisting = existingLicense.isNotEmpty;
    final hasNew = _newLicenseFile != null;
    final hasAny = hasExisting || hasNew;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Driver’s License Photo',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: hasAny
              ? 'Replace driver license photo'
              : 'Upload driver license photo',
          child: GestureDetector(
            onTap: _isSaving
                ? null
                : () => hasAny
                    ? _showLicenseActions(existingLicense)
                    : _pickImage(false),
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: !hasAny
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          size: 40,
                          color: AppColors.muted,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap to upload license photo',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: hasNew
                              ? Image.file(_newLicenseFile!,
                                  fit: BoxFit.cover)
                              : Image.network(
                                  existingLicense,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (_, child, progress) {
                                    if (progress == null) return child;
                                    return const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 40,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        if (hasAny) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _previewImage(
                          file: _newLicenseFile,
                          url: hasNew ? null : existingLicense,
                          title: 'License Preview',
                        ),
                icon: const Icon(Icons.zoom_in, size: 16),
                label: const Text('Preview'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.green,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _isSaving
                    ? null
                    : () {
                        setState(() {
                          _newLicenseFile = null;
                          _hasUnsavedChanges = true;
                        });
                      },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _showLicenseActions(String existingLicense) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: const Text('Preview'),
              onTap: () => Navigator.pop(context, 'preview'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Replace photo'),
              onTap: () => Navigator.pop(context, 'replace'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.danger,
              ),
              title: const Text(
                'Remove photo',
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    switch (action) {
      case 'preview':
        _previewImage(
          file: _newLicenseFile,
          url: _newLicenseFile != null ? null : existingLicense,
        );
        break;
      case 'replace':
        await _pickImage(false);
        break;
      case 'remove':
        setState(() {
          _newLicenseFile = null;
          _hasUnsavedChanges = true;
        });
        // Note: this only clears the new file; to actually delete the
        // stored license in Supabase, you'd set license_photo_url to null.
        break;
    }
  }

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