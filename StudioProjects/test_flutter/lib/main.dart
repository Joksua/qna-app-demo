import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';      // firebase
import 'package:cloud_firestore/cloud_firestore.dart';  // firestore database
import 'package:firebase_auth/firebase_auth.dart';      // firebase authentication
import 'dart:convert';
import 'package:http/http.dart' as http;


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('Before Firebase init');  //debugging purposes
  await Firebase.initializeApp();
  print('After Firebase init');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI QnA Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Still checking auth state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // User is logged in
          if (snapshot.hasData) {
            return const QnAScreen();
          }

          // User is NOT logged in
          return const LoginScreen();
        },
      ),
    );
  }
}

class QnAScreen extends StatefulWidget {
  const QnAScreen({super.key});

  @override
  State<QnAScreen> createState() => _QnAScreenState();
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String error = '';

  Future<void> _login() async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _register() async {
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _login, child: const Text('Login')),
            TextButton(onPressed: _register, child: const Text('Register')),
            if (error.isNotEmpty)
              Text(error, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}


class _QnAScreenState extends State<QnAScreen> {
  static const String cloudRunUrl =
      'https://testsummary-16407516645.asia-southeast1.run.app'; // cloud function link

  final TextEditingController _controller = TextEditingController();
  List<String> _notes = []; // list text from firestore
  String _answerText = '';

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  void _generateAnswer() async {
    final user = FirebaseAuth.instance.currentUser;
    final inputText = _controller.text.trim();

    if (inputText.isEmpty) return;

    setState(() {
      _answerText = 'Generating answer...';
    });

    try {
      // Call Cloud Run (Gemini)
      final response = await http.post(
        Uri.parse(cloudRunUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': inputText,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Cloud Run error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final answer = data['answer'] as String;

      // Save to Firestore
      await FirebaseFirestore.instance.collection('test_qna').add({
        'question': inputText,
        'answer': answer,
        'userId': user?.uid,
        'createdAt': Timestamp.now(),
      });

      _controller.clear();
      await _loadNotes();

      setState(() {
        _answerText = answer;
      });
    } catch (e) {
      setState(() {
        _answerText = 'Error generating answer: $e';
      });
    }
  }

  Future<void> _loadNotes() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('test_qna')
        .orderBy('createdAt', descending: true)
        .get();

    setState(() {
      _notes = snapshot.docs
          .map((doc) => (doc.data()['answer'] ?? '') as String)
          .where((answer) => answer.isNotEmpty)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI QnA Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter question:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Input question here...',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _generateAnswer,
              child: const Text('Generate Answer'),
            ),
            const SizedBox(height: 24),
            if (_answerText.isNotEmpty) ...[
              const Text(
                'Generated Answer:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _answerText,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Saved Answers:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _notes.length,
                itemBuilder: (context, index) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.note),
                      title: Text(_notes[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
