import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({super.key});

  // Theme Colors
  static const Color yellow = Color(0xFFFFD31A);
  static const Color darkBg = Color(0xFF121212);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Registered Users", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: yellow,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          // 1. Loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 2. Error
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          // 3. No Data
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No users registered yet."));
          }

          final users = snapshot.data!.docs;

          // 4. List Data
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              var data = users[index].data() as Map<String, dynamic>;
              String name = data['name'] ?? "Unknown";
              String email = data['email'] ?? "No Email";
              String role = data['role'] ?? "student";

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: role == 'admin' ? Colors.black : Colors.grey[300],
                    child: Icon(
                      Icons.person,
                      color: role == 'admin' ? yellow : Colors.black,
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email),
                      Text("Role: ${role.toUpperCase()}", style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    ],
                  ),
                  // Optional: Add Delete Button logic here if needed later
                ),
              );
            },
          );
        },
      ),
    );
  }
}