import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddBusScreen extends StatefulWidget {
  const AddBusScreen({super.key});

  @override
  State<AddBusScreen> createState() => _AddBusScreenState();
}

class _AddBusScreenState extends State<AddBusScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController busNumberController = TextEditingController();
  final TextEditingController routeNameController = TextEditingController();
  final TextEditingController startPointController = TextEditingController();
  final TextEditingController endPointController = TextEditingController();
  
  // 🔹 NEW: Controller for linking the ESP32
  final TextEditingController deviceIdController = TextEditingController(); 

  bool isLoading = false;

  /// 🔹 SAVE BUS TO FIREBASE
  Future<void> saveBus() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance.collection('bus_schedules').add({
        "busNumber": busNumberController.text.trim(),
        "routeTitle": routeNameController.text.trim(),
        "startPoint": startPointController.text.trim(),
        "endPoint": endPointController.text.trim(),
        
        // 🔹 SAVE THE DEVICE LINK
        // This must match what is in your ESP32 code (e.g. "device_01")
        "deviceId": deviceIdController.text.trim(), 
        
        "stops": [], 
        "createdAt": FieldValue.serverTimestamp(),
        "createdBy": user?.uid,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Bus added successfully!")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Bus"),
        backgroundColor: const Color(0xFFFFD31A),
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _inputField(
                controller: busNumberController,
                label: "Bus Number",
                hint: "KL-07-1234",
              ),
              const SizedBox(height: 16),
              _inputField(
                controller: routeNameController,
                label: "Route Name",
                hint: "Kazakuttam - College",
              ),
              const SizedBox(height: 16),
              _inputField(
                controller: startPointController,
                label: "Start Point",
                hint: "Kazakuttam",
              ),
              const SizedBox(height: 16),
              _inputField(
                controller: endPointController,
                label: "End Point",
                hint: "College",
              ),
              const SizedBox(height: 16),

              // 🔹 NEW DEVICE ID FIELD
              _inputField(
                controller: deviceIdController,
                label: "GPS Device ID",
                hint: "e.g. device_01", // Should match ESP32 code
              ),
              
              const SizedBox(height: 30),

              /// 🔹 SAVE BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : saveBus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Save Bus",
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔹 INPUT FIELD WIDGET
  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextFormField(
      controller: controller,
      validator: (value) =>
          value == null || value.isEmpty ? "Required" : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white, 
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}