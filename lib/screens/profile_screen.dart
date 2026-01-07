// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(
        children: const [
          ListTile(leading: Icon(Icons.person), title: Text('User Profile')),
          Divider(),
          ListTile(
            title: Text('Dark Mode'),
            trailing: Icon(Icons.chevron_right),
          ),
          ListTile(
            title: Text('Privacy Policy'),
            trailing: Icon(Icons.chevron_right),
          ),
          ListTile(
            title: Text('Terms & Conditions'),
            trailing: Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
