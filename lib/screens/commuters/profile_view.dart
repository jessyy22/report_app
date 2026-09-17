import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rtoda_widgets.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _data;
  String? _idUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    try {
      final data = await _supabase
          .from('commuter_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      String? signedId;

      final storedId = data?['id_photo_url']?.toString();

      if (storedId != null && storedId.isNotEmpty) {
        signedId = await _signedUrl(storedId);
      }

      debugPrint('COMMUTER PROFILE: $data');
      debugPrint('PROFILE PHOTO: ${data?['profile_photo_url']}');
      debugPrint('PHONE: ${data?['phone_number']}');
      debugPrint('ID PHOTO: $storedId');
      debugPrint('SIGNED ID URL: $signedId');

      if (!mounted) return;

      setState(() {
        _data = data;
        _idUrl = signedId;
        _loading = false;
      });
    } catch (e) {
      debugPrint('ERROR FETCHING COMMUTER PROFILE: $e');

      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // Creates a temporary URL for the private ID-verifications bucket.
  Future<String?> _signedUrl(String stored) async {
    try {
      var path = stored.trim();

      // If database contains the complete Supabase URL,
      // extract only the storage path.
      if (path.contains('/id-verifications/')) {
        path = path.split('/id-verifications/').last.split('?').first;
      }

      // Safety check if the stored value already starts with the bucket name.
      if (path.startsWith('id-verifications/')) {
        path = path.substring('id-verifications/'.length);
      }

      debugPrint('ID STORAGE PATH: $path');

      return await _supabase.storage
          .from('id-verifications')
          .createSignedUrl(path, 60);
    } catch (e) {
      debugPrint('ERROR CREATING ID SIGNED URL: $e');
      return null;
    }
  }

  Future<void> _edit() async {
    if (_data == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditProfileScreen(initialData: _data!)),
    );

    if (result == true) {
      await _fetch();
    }
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to sign out: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final data = _data ?? {};

    final name =
        (data['full_name'] ?? user?.email?.split('@').first ?? 'Commuter')
            .toString();

    final phone = data['phone_number']?.toString().trim() ?? '';

    final photo = data['profile_photo_url']?.toString().trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(onPressed: _edit, icon: const Icon(Icons.edit_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
              children: [
                // PROFILE HEADER
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _profileImage(photo),

                        const SizedBox(height: 12),

                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.greenSoft,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Text(
                            'COMMUTER',
                            style: TextStyle(
                              color: AppColors.greenDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                const RTODASectionTitle(title: 'Account information'),

                const SizedBox(height: 10),

                _item(
                  Icons.email_outlined,
                  'Registered Email',
                  user?.email ?? 'Not available',
                ),

                _item(
                  Icons.phone_outlined,
                  'Phone Number',
                  phone.isEmpty ? 'Not provided' : phone,
                ),

                if (data['address'] != null &&
                    data['address'].toString().trim().isNotEmpty)
                  _item(Icons.location_on_outlined, 'Address', data['address']),

                const SizedBox(height: 18),

                const RTODASectionTitle(title: 'Uploaded ID'),

                const SizedBox(height: 10),

                _idCard(),

                const SizedBox(height: 20),

                OutlinedButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit Profile'),
                ),

                const SizedBox(height: 10),

                TextButton.icon(
                  onPressed: _signOut,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out of account'),
                ),
              ],
            ),
    );
  }

  Widget _profileImage(String photo) {
    if (photo.isEmpty) {
      return const CircleAvatar(
        radius: 45,
        backgroundColor: AppColors.greenSoft,
        child: Icon(Icons.person_rounded, color: AppColors.green, size: 42),
      );
    }

    final url = '$photo?t=${DateTime.now().millisecondsSinceEpoch}';

    return CircleAvatar(
      radius: 45,
      backgroundColor: AppColors.greenSoft,
      child: ClipOval(
        child: Image.network(
          url,
          width: 90,
          height: 90,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;

            return const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          },
          errorBuilder: (_, error, __) {
            debugPrint('PROFILE IMAGE ERROR: $error');

            return const Icon(
              Icons.person_rounded,
              color: AppColors.green,
              size: 42,
            );
          },
        ),
      ),
    );
  }

  Widget _idCard() {
    if (_idUrl == null || _idUrl!.isEmpty) {
      return Card(
        child: Container(
          height: 170,
          alignment: Alignment.center,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.badge_outlined, size: 45, color: AppColors.muted),
              SizedBox(height: 8),
              Text(
                'ID image unavailable',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showFullId,
        child: Column(
          children: [
            Image.network(
              _idUrl!,
              height: 210,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;

                return const SizedBox(
                  height: 210,
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (_, error, __) {
                debugPrint('ID IMAGE ERROR: $error');

                return Container(
                  height: 160,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(20),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        size: 40,
                        color: AppColors.muted,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Unable to display ID',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.zoom_in, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Tap to view ID',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullId() {
    if (_idUrl == null || _idUrl!.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(_idUrl!, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, dynamic value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.greenSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.green, size: 20),
        ),
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          value?.toString() ?? 'Not provided',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
    );
  }
}
