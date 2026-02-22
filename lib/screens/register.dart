import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Controllers
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // State Variables
  int _currentStep = 1; // 1: Phone, 2: OTP, 3: Details
  String _verificationId = "";
  bool _isLoading = false;
  bool _obscurePassword = true;

  static const Color yellow = Color(0xFFFFD31A);

  // ---------------------------------------------------
  // 🔹 STEP 1: SEND OTP
  // ---------------------------------------------------
  Future<void> _sendOTP() async {
    if (phoneController.text.trim().isEmpty) {
      _showError("Please enter a phone number", isInfo: true);
      return;
    }
    setState(() => _isLoading = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneController.text.trim(),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Optional: Auto-verify on some Androids
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() => _isLoading = false);
        _showError(e.message ?? "Verification Failed");
      },
      codeSent: (String verId, int? resendToken) {
        setState(() {
          _verificationId = verId;
          _currentStep = 2;
          _isLoading = false;
        });
      },
      codeAutoRetrievalTimeout: (String verId) {},
    );
  }

  // ---------------------------------------------------
  // 🔹 STEP 2: VERIFY OTP
  // ---------------------------------------------------
  Future<void> _verifyOTP() async {
    if (otpController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otpController.text.trim(),
      );

      // Verify the code by signing in temporarily
      await FirebaseAuth.instance.signInWithCredential(credential);
      
      // If success, move to details step
      setState(() {
        _currentStep = 3;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("Invalid OTP code. Please try again.");
    }
  }

  // ---------------------------------------------------
  // 🔹 STEP 3: FINAL REGISTRATION (Email/Password)
  // ---------------------------------------------------
  Future<void> _finalizeRegistration() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty || nameController.text.isEmpty) {
      _showError("Please fill in all fields", isInfo: true);
      return;
    }
    setState(() => _isLoading = true);

    try {
      // 1. Create Email/Password Account
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      // 2. Save data to Firestore (users collection)
      // 🔒 Note: Role is strictly set to 'student' here for security.
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'phone': phoneController.text.trim(), 
        'role': 'student', // 🔒 Default role
        'assignedBus': '', // 🚌 Initialized empty for future driver mapping
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString());
    }
  }

  void _showError(String msg, {bool isInfo = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg), 
        backgroundColor: isInfo ? Colors.black87 : Colors.red
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text("REGISTER", style: TextStyle(color: yellow, fontSize: 16, letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                _currentStep == 1 ? "Verify Phone" : (_currentStep == 2 ? "Enter OTP" : "Final Details"),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),

              // --- STEP 1: PHONE INPUT ---
              if (_currentStep == 1) ...[
                _buildTextField(phoneController, "Phone (e.g. +91...)", Icons.phone, keyboardType: TextInputType.phone),
                const SizedBox(height: 20),
                _buildButton("SEND OTP", _sendOTP),
              ],

              // --- STEP 2: OTP INPUT ---
              if (_currentStep == 2) ...[
                _buildTextField(otpController, "6-Digit OTP", Icons.lock_clock, keyboardType: TextInputType.number),
                const SizedBox(height: 20),
                _buildButton("VERIFY CODE", _verifyOTP),
                TextButton(
                  onPressed: () => setState(() => _currentStep = 1), 
                  child: const Text("Change Phone Number", style: TextStyle(color: yellow))
                )
              ],

              // --- STEP 3: EMAIL/PASS DETAILS ---
              if (_currentStep == 3) ...[
                _buildTextField(nameController, "Full Name", Icons.person),
                const SizedBox(height: 15),
                _buildTextField(emailController, "Email Address", Icons.email, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 15),
                _buildTextField(passwordController, "Password", Icons.lock, isPassword: true),
                const SizedBox(height: 30),
                _buildButton("FINISH REGISTRATION", _finalizeRegistration),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, 
    String hint, 
    IconData icon, 
    {bool isPassword = false, TextInputType keyboardType = TextInputType.text}
  ) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? _obscurePassword : false,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: yellow),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
        suffixIcon: isPassword ? IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: yellow, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 0,
        ),
        child: _isLoading 
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) 
          : Text(text, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}