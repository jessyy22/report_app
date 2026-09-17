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
  String? _licenseUrl;
  bool _loading = true;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await _supabase.from('driver_profiles').select().eq('id', user.id).maybeSingle();
      String? signed;
      final stored = data?['license_photo_url']?.toString();
      if (stored != null && stored.isNotEmpty) signed = await _signedUrl(stored);
      if (mounted) setState(() { _data = data; _licenseUrl = signed; _loading = false; });
    } catch (e) {
      debugPrint('Error fetching driver profile: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _signedUrl(String stored) async {
    try {
      var path = stored;
      if (path.contains('/id-verifications/')) path = path.split('/id-verifications/').last.split('?').first;
      return await _supabase.storage.from('id-verifications').createSignedUrl(path, 60);
    } catch (e) {
      debugPrint('Error creating signed URL: $e');
      return null;
    }
  }

  Future<void> _edit() async {
    if (_data == null) return;
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(initialData: _data!)));
    if (result == true) _fetch();
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to sign out: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final data = _data ?? {};
    final name = (data['full_name'] ?? user?.email?.split('@').first ?? 'Driver').toString();
    final photo = (data['profile_photo_url'] ?? data['avatar_url'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Profile'), actions: [IconButton(onPressed: _edit, icon: const Icon(Icons.edit_rounded))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 28), children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [CircleAvatar(radius: 45, backgroundColor: AppColors.greenSoft, backgroundImage: photo.isNotEmpty ? NetworkImage('$photo?t=${DateTime.now().millisecondsSinceEpoch}') : null, child: photo.isEmpty ? const Icon(Icons.person_rounded, color: AppColors.green, size: 42) : null), const SizedBox(height: 12), Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5), decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(30)), child: Text('BODY NO. ${data['body_number'] ?? 'N/A'}', style: const TextStyle(color: AppColors.greenDark, fontSize: 11, fontWeight: FontWeight.w800)))]))),
        const SizedBox(height: 18),
        const RTODASectionTitle(title: 'Driver information'),
        const SizedBox(height: 10),
        _item(Icons.badge_outlined, 'License Number', data['license_number'] ?? 'Not provided'),
        _item(Icons.email_outlined, 'Registered Email', user?.email ?? 'Not available'),
        _item(Icons.phone_outlined, 'Phone Number', data['phone_number'] ?? 'Not provided'),
        _item(Icons.groups_outlined, 'Association', data['association'] ?? 'Not provided'),
        _item(Icons.star_outline_rounded, 'Rating', '${data['rating'] ?? '5.0'} / 5.0'),
        const SizedBox(height: 8),
        if (_licenseUrl != null) ...[const RTODASectionTitle(title: 'Submitted license'), const SizedBox(height: 10), ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(_licenseUrl!, height: 200, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 160, color: AppColors.background, alignment: Alignment.center, child: const Text('License image unavailable.')))), const SizedBox(height: 18)],
        OutlinedButton.icon(onPressed: _edit, icon: const Icon(Icons.edit_rounded), label: const Text('Edit Profile')),
        const SizedBox(height: 10),
        TextButton.icon(onPressed: _signOut, style: TextButton.styleFrom(foregroundColor: AppColors.danger), icon: const Icon(Icons.logout_rounded), label: const Text('Sign out of account')),
      ]),
    );
  }

  Widget _item(IconData icon, String label, dynamic value) => Card(margin: const EdgeInsets.only(bottom: 9), child: ListTile(leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: AppColors.green, size: 20)), title: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700)), subtitle: Text(value?.toString() ?? 'Not provided', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text))));
}
