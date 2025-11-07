import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _busController = TextEditingController();

  bool _isLoading = false;
  User? _currentUser; // Store the current user object
  String _profileImageUrl = 'assets/images/profile.png'; // Default or fetched image

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser; // Get current user once
    if (_currentUser != null) {
      _fetchUserData();
    } else {
      // Handle case where no user is logged in (shouldn't happen if routed correctly)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No user logged in to view profile.')),
        );
        Navigator.pop(context); // Go back if no user
      });
    }
  }

  Future<void> _fetchUserData() async {
    if (!mounted) return; // Prevent setState if widget is disposed
    setState(() => _isLoading = true);

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      if (userDoc.exists) {
        if (!mounted) return; // Prevent setState if widget is disposed
        setState(() {
          _nameController.text = userDoc['name'] ?? '';
          // Email is read-only, so we'll just display it directly
          _phoneController.text = userDoc['phone'] ?? '';
          _busController.text = userDoc['assignedBus'] ?? '';
          _profileImageUrl = userDoc['profileImageUrl'] ?? 'assets/images/profile.png';
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

  Future<void> _saveChanges() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user logged in.')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'assignedBus': _busController.text.trim(),
        // 'profileImageUrl': _profileImageUrl, // Uncomment if you add image upload logic
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
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
      appBar: AppBar(
        title: const Text("Edit Profile"),
        // Using theme-defined background color from main.dart
        // backgroundColor: const Color(0xFF010429), // Ensure consistency
      ),
      body: Container( // Wrap with Container for gradient background
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF010429), Color(0xFF010429)], // dark navy solid
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFCC203))) // Themed loading indicator
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      // Display fetched profile image or default
                      backgroundImage: _profileImageUrl.startsWith('http')
                          ? NetworkImage(_profileImageUrl) as ImageProvider
                          : AssetImage(_profileImageUrl),
                      backgroundColor: Colors.grey.shade200, // Background if image fails
                    ),
                    const SizedBox(height: 10),

                    // Display User Email (read-only, from Firebase Auth)
                    Text(
                      _currentUser?.email ?? 'N/A',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Name
                    _buildProfileTextField(
                      controller: _nameController,
                      labelText: "Name",
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 20),

                    // Phone
                    _buildProfileTextField(
                      controller: _phoneController,
                      labelText: "Phone Number",
                      icon: Icons.phone_android,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),

                    // Bus No / Route
                    _buildProfileTextField(
                      controller: _busController,
                      labelText: "Assigned Bus ID/Route",
                      icon: Icons.directions_bus,
                      // keyboardType: TextInputType.text, // Default
                      // You might make this readOnly if the bus assignment is admin-controlled
                    ),
                    const SizedBox(height: 40),

                    // Save Changes Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFCC203), // Your accent color
                        foregroundColor: const Color(0xFF010429), // Text color for the button
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Color(0xFF010429))
                          : const Text(
                              "Save Changes",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),
            ),
      );
  }

  // Helper method for consistent text field styling
  Widget _buildProfileTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF1B1E36), // Your dark input field color
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none, // No border for a cleaner look with filled color
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Color(0xFFFCC203), width: 2), // Accent border on focus
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      ),
    );
  }
}