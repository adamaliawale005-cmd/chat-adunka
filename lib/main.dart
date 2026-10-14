import 'package:flutter/material.dart';

void main() {
  runApp(const ChatAdunka());
}

class ChatAdunka extends StatelessWidget {
  const ChatAdunka({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat Aduunka',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Chat Aduunka'),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble,
                size: 90,
                color: Colors.teal,
              ),
              SizedBox(height: 20),
              Text(
                'Welcome to Chat Aduunka',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text('Connect with people around the world'),
            ],
          ),
        ),
      ),
    );
  }
}
