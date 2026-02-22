import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color yellow = Color(0xFFFCB001);
  static const Color darkCardBg = Color(0xFF1A1A1A);
  static const Color whiteBg = Colors.white;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _busController = TextEditingController();

  bool _isLoading = false;
  User? _currentUser;
  String _profileImageUrl = 'assets/images/profile.png';
  
  // 🔹 New State Variables
  String _role = 'student';
  bool _isRequestPending = false;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    if (_currentUser != null) {
      _fetchUserData();
    }
  }

  Future<void> _fetchUserData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. Fetch User Profile
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      // 2. Check for Pending Driver Requests
      QuerySnapshot requestQuery = await FirebaseFirestore.instance
          .collection('role_requests')
          .where('uid', isEqualTo: _currentUser!.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;

        if (!mounted) return;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _busController.text = data['assignedBus'] ?? '';
          _role = data['role'] ?? 'student';
          _isRequestPending = requestQuery.docs.isNotEmpty;
          
          if (data.containsKey('profileImageUrl') && data['profileImageUrl'] != null) {
             _profileImageUrl = data['profileImageUrl'];
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error fetching data: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // 🔹 Function to submit a Driver Request
  Future<void> _requestDriverRole() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('role_requests').add({
        'uid': _currentUser!.uid,
        'name': _nameController.text.trim(),
        'email': _currentUser!.email,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      setState(() => _isRequestPending = true);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Request Sent"),
            content: const Text("Your request to become a driver has been sent to management for approval."),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    if (_currentUser == null) return;
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .set({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'assignedBus': _busController.text.trim(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _busController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: whiteBg,
      appBar: AppBar(
        backgroundColor: whiteBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Edit Profile", style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: yellow,
                  child: CircleAvatar(
                    radius: 46,
                    backgroundImage: _profileImageUrl.startsWith('http')
                        ? NetworkImage(_profileImageUrl) as ImageProvider
                        : AssetImage(_profileImageUrl),
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
                const SizedBox(height: 10),
                Text(_currentUser?.email ?? 'N/A', style: const TextStyle(color: Colors.black54, fontSize: 16, fontWeight: FontWeight.w500)),
                
                // 🔹 Role Badge
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(15)),
                  child: Text(_role.toUpperCase(), style: const TextStyle(color: yellow, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: yellow,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.black))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          _buildProfileTextField(controller: _nameController, labelText: "Name", icon: Icons.person_outline),
                          const SizedBox(height: 20),
                          _buildProfileTextField(controller: _phoneController, labelText: "Phone Number", icon: Icons.phone_android, keyboardType: TextInputType.phone),
                          const SizedBox(height: 20),
                          
                          // Only show Assigned Bus for Drivers/Admins
                          if (_role != 'student')
                            _buildProfileTextField(controller: _busController, labelText: "Assigned Bus ID/Route", icon: Icons.directions_bus),
                          
                          const SizedBox(height: 30),

                          /// 🔹 REQUEST DRIVER ROLE BUTTON (Only for Students)
                          if (_role == 'student')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: OutlinedButton.icon(
                                onPressed: _isRequestPending ? null : _requestDriverRole,
                                icon: Icon(_isRequestPending ? Icons.hourglass_empty : Icons.drive_eta),
                                label: Text(_isRequestPending ? "REQUEST PENDING" : "BECOME A DRIVER"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black,
                                  side: const BorderSide(color: Colors.black, width: 2),
                                  minimumSize: const Size(double.infinity, 50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                              ),
                            ),

                          ElevatedButton(
                            onPressed: _isLoading ? null : _saveChanges,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 55),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              elevation: 5,
                            ),
                            child: const Text("Save Changes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTextField({required TextEditingController controller, required String labelText, required IconData icon, TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 5),
          child: Text(labelText, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        Container(
          decoration: BoxDecoration(color: darkCardBg, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))]),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: yellow),
              hintText: "Enter $labelText",
              hintStyle: const TextStyle(color: Colors.white38),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}