import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  static const Color yellow = Color(0xFFFFD31A);

  // ---------------------------------------------------
  // 🔹 LOGIC: PROMOTE / EDIT USER
  // ---------------------------------------------------
  void _showEditUserDialog(BuildContext context, String uid, Map<String, dynamic> userData) {
    String selectedRole = userData['role'] ?? 'student';
    String? selectedBusId = userData['assignedBus'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Manage ${userData['name']}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Role Selection
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: "User Role"),
                items: ['student', 'driver', 'admin'].map((role) {
                  return DropdownMenuItem(value: role, child: Text(role.toUpperCase()));
                }).toList(),
                onChanged: (val) => setDialogState(() => selectedRole = val!),
              ),
              const SizedBox(height: 20),

              // 2. Bus Assignment (Only if Role is Driver)
              if (selectedRole == 'driver')
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('bus_schedules').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    var buses = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      value: selectedBusId != "" ? selectedBusId : null,
                      decoration: const InputDecoration(labelText: "Assign Bus"),
                      hint: const Text("Select Bus"),
                      items: buses.map((bus) {
                        var bData = bus.data() as Map<String, dynamic>;
                        return DropdownMenuItem(
                          value: bus.id,
                          child: Text("${bData['busNumber']} - ${bData['routeTitle']}"),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedBusId = val),
                    );
                  },
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                await FirebaseFirestore.instance.collection('users').doc(uid).update({
                  'role': selectedRole,
                  'assignedBus': selectedRole == 'driver' ? (selectedBusId ?? "") : "",
                });
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text("SAVE CHANGES", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // 🔹 UI BUILD (Tabbed View)
  // ---------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("User Management", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: yellow,
          iconTheme: const IconThemeData(color: Colors.black),
          bottom: const TabBar(
            labelColor: Colors.black,
            indicatorColor: Colors.black,
            tabs: [
              Tab(text: "ALL USERS"),
              Tab(text: "REQUESTS"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildUserListTab(),
            _buildRequestsTab(),
          ],
        ),
      ),
    );
  }

  // 🔹 TAB 1: List of all Users
  Widget _buildUserListTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!.docs;

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            var data = users[index].data() as Map<String, dynamic>;
            String role = data['role'] ?? "student";

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: role == 'admin' ? Colors.black : (role == 'driver' ? yellow : Colors.grey[300]),
                  child: Icon(Icons.person, color: role == 'admin' ? yellow : Colors.black),
                ),
                title: Text(data['name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${data['email']}\nRole: ${role.toUpperCase()}"),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.edit_note, size: 28),
                  onPressed: () => _showEditUserDialog(context, users[index].id, data),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 🔹 TAB 2: Pending Driver Requests
  Widget _buildRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('role_requests').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final requests = snapshot.data!.docs;

        if (requests.isEmpty) {
          return const Center(child: Text("No pending driver requests."));
        }

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            var reqData = requests[index].data() as Map<String, dynamic>;

            return Card(
              color: Colors.blueGrey[50],
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                title: Text(reqData['name'] ?? "New Applicant", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("Applied to become a Driver"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // REJECT
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () async {
                        await FirebaseFirestore.instance.collection('role_requests').doc(requests[index].id).delete();
                      },
                    ),
                    // APPROVE
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: Colors.green, size: 30),
                      onPressed: () {
                        // We open the edit dialog to choose their role AND assign a bus immediately
                        _showEditUserDialog(context, reqData['uid'], reqData);
                        // Clean up the request after clicking Save in the dialog
                        FirebaseFirestore.instance.collection('role_requests').doc(requests[index].id).delete();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}