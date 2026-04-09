import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() => runApp(const NativeMindsApp());

const String backendUrl = 'http://10.150.73.33:8000';

// ─── Database Helper ───────────────────────────────────────────────────────────
class DBHelper {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'nativeminds_v3.db'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions(
            id INTEGER PRIMARY KEY, 
            question TEXT, 
            subject TEXT, 
            language TEXT, 
            grade INTEGER, 
            profile TEXT, 
            timestamp TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE profiles(
            id INTEGER PRIMARY KEY, 
            name TEXT, 
            language TEXT, 
            grade INTEGER,
            parent_name TEXT,
            parent_phone TEXT
          )
        ''');
      },
      version: 1,
    );
    return _db!;
  }

  static Future<void> saveSession(String question, String subject, String language, int grade, String profile) async {
    final database = await db;
    await database.insert('sessions', {
      'question': question,
      'subject': subject,
      'language': language,
      'grade': grade,
      'profile': profile,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getSessions(String profile) async {
    final database = await db;
    return database.query('sessions', where: 'profile = ?', whereArgs: [profile], orderBy: 'id DESC', limit: 50);
  }

  static Future<Map<String, int>> getSubjectCounts(String profile) async {
    final database = await db;
    final results = await database.rawQuery(
      'SELECT subject, COUNT(*) as count FROM sessions WHERE profile = ? GROUP BY subject',
      [profile],
    );
    return {for (var r in results) r['subject'] as String: r['count'] as int};
  }

  static Future<List<Map<String, dynamic>>> getProfiles() async {
    final database = await db;
    return database.query('profiles');
  }

  static Future<void> saveProfile(String name, String language, int grade, String parentName, String parentPhone) async {
    final database = await db;
    await database.insert('profiles', {
      'name': name,
      'language': language,
      'grade': grade,
      'parent_name': parentName,
      'parent_phone': parentPhone,
    });
  }

  static Future<void> deleteProfile(int id) async {
    final database = await db;
    await database.delete('profiles', where: 'id = ?', whereArgs: [id]);
    await database.delete('sessions', where: 'profile = ?', whereArgs: [id]);
  }

  static Future<int> getTodayCount(String profile) async {
    final database = await db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await database.rawQuery(
      'SELECT COUNT(*) as count FROM sessions WHERE profile = ? AND timestamp LIKE ?',
      [profile, '$today%'],
    );
    return result.first['count'] as int;
  }
}

// ─── App ───────────────────────────────────────────────────────────────────────
class NativeMindsApp extends StatelessWidget {
  const NativeMindsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NativeMinds',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ─── Home Screen ──────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _profiles = [];
  int _selectedTab = 0;

  final Map<String, String> _languages = {
    'marathi': 'mr-IN',
    'hindi': 'hi-IN',
    'tamil': 'ta-IN',
    'telugu': 'te-IN',
    'bengali': 'bn-IN',
    'kannada': 'kn-IN',
    'gujarati': 'gu-IN',
    'punjabi': 'pa-IN',
  };

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final profiles = await DBHelper.getProfiles();
    setState(() => _profiles = profiles);
  }

  void _showAddProfile() {
    final nameController = TextEditingController();
    final parentNameController = TextEditingController();
    final parentPhoneController = TextEditingController();
    String selectedLanguage = 'marathi';
    int selectedGrade = 3;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Student', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Student Information', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Student Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedLanguage,
                  decoration: const InputDecoration(labelText: 'Mother Tongue', border: OutlineInputBorder(), prefixIcon: Icon(Icons.language)),
                  items: _languages.keys.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (v) => setModalState(() => selectedLanguage = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedGrade,
                  decoration: const InputDecoration(labelText: 'Grade', border: OutlineInputBorder(), prefixIcon: Icon(Icons.school)),
                  items: List.generate(8, (i) => i + 1).map((g) => DropdownMenuItem(value: g, child: Text('Grade $g'))).toList(),
                  onChanged: (v) => setModalState(() => selectedGrade = v!),
                ),
                const SizedBox(height: 16),
                const Text('Parent Information', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(
                  controller: parentNameController,
                  decoration: const InputDecoration(labelText: 'Parent Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.family_restroom)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: parentPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Parent Phone', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) return;
                      await DBHelper.saveProfile(
                        nameController.text.trim(),
                        selectedLanguage,
                        selectedGrade,
                        parentNameController.text.trim(),
                        parentPhoneController.text.trim(),
                      );
                      Navigator.pop(context);
                      _loadProfiles();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Add Student', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFF2E7D32),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.school, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('NativeMinds', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text('Learn in your mother tongue', style: TextStyle(fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _statCard('${_profiles.length}', 'Students'),
                      const SizedBox(width: 12),
                      _statCard('8+', 'Languages'),
                      const SizedBox(width: 12),
                      _statCard('3', 'Subjects'),
                    ],
                  ),
                ],
              ),
            ),
            // Tab bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _tabButton('Students', 0),
                  const SizedBox(width: 8),
                  _tabButton('Parents', 1),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _selectedTab == 0 ? _studentsTab() : _parentsTab(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProfile,
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Student'),
      ),
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2E7D32) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2E7D32)),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? Colors.white : const Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _studentsTab() {
    if (_profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No students yet', style: TextStyle(fontSize: 18, color: Colors.grey[500])),
            const SizedBox(height: 8),
            Text('Tap + to add a student', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
          ],
        ),
      );
    }

    final colors = [const Color(0xFF2E7D32), const Color(0xFF1565C0), const Color(0xFF6A1B9A), const Color(0xFFE65100)];

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.95,
      ),
      itemCount: _profiles.length,
      itemBuilder: (_, i) {
        final profile = _profiles[i];
        final color = colors[i % colors.length];
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TutorScreen(profile: profile))).then((_) => _loadProfiles()),
          onLongPress: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Delete Student?'),
                content: Text('Remove ${profile['name']}?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                ],
              ),
            );
            if (confirm == true) {
              await DBHelper.deleteProfile(profile['id']);
              _loadProfiles();
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  child: Text(profile['name'][0].toUpperCase(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(height: 10),
                Text(profile['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('${profile['language']} • Grade ${profile['grade']}', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: const Text('Tap to learn', style: TextStyle(fontSize: 11, color: Colors.white)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _parentsTab() {
    if (_profiles.isEmpty) {
      return Center(child: Text('No students added yet', style: TextStyle(color: Colors.grey[500])));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: _profiles.length,
      itemBuilder: (_, i) {
        final profile = _profiles[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ParentDashboard(profile: profile))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF2E7D32),
                    child: Text(profile['name'][0].toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('Grade ${profile['grade']} • ${profile['language']}', style: const TextStyle(color: Colors.grey)),
                        if (profile['parent_name'] != null && profile['parent_name'].toString().isNotEmpty)
                          Text('Parent: ${profile['parent_name']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Tutor Screen ──────────────────────────────────────────────────────────────
class TutorScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const TutorScreen({super.key, required this.profile});

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  final TextEditingController _questionController = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ImagePicker _picker = ImagePicker();
  String _answer = '';
  bool _loading = false;
  bool _listening = false;
  bool _speaking = false;
  late String _selectedLanguage;
  String _selectedSubject = 'math';
  late int _selectedGrade;

  final Map<String, String> _languageLocales = {
    'marathi': 'mr-IN', 'hindi': 'hi-IN', 'tamil': 'ta-IN', 'telugu': 'te-IN',
    'bengali': 'bn-IN', 'kannada': 'kn-IN', 'gujarati': 'gu-IN', 'punjabi': 'pa-IN',
  };

  final List<String> _subjects = ['math', 'science', 'history', 'english', 'geography'];

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.profile['language'];
    _selectedGrade = widget.profile['grade'];
    _tts.setSpeechRate(0.5);
    _tts.setCompletionHandler(() => setState(() => _speaking = false));
  }

  Future<void> _scanImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    setState(() { _loading = true; _answer = 'Reading image...'; });

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizer = TextRecognizer();
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      if (recognized.text.isNotEmpty) {
        setState(() => _questionController.text = recognized.text.trim());
        await _askQuestion();
      } else {
        setState(() { _answer = 'Could not read text from image. Try again with clearer image.'; _loading = false; });
      }
    } catch (e) {
      setState(() { _answer = 'Error reading image.'; _loading = false; });
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Scan Question', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _imageOptionButton(Icons.camera_alt, 'Camera', () {
                    Navigator.pop(context);
                    _scanImage(ImageSource.camera);
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _imageOptionButton(Icons.photo_library, 'Gallery', () {
                    Navigator.pop(context);
                    _scanImage(ImageSource.gallery);
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageOptionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E7D32)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: const Color(0xFF2E7D32)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
          ],
        ),
      ),
    );
  }

  Future<void> _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _listening = true);
      _speech.listen(
        onResult: (result) => setState(() => _questionController.text = result.recognizedWords),
        localeId: _languageLocales[_selectedLanguage],
      );
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _listening = false);
  }

  Future<void> _speak(String text) async {
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
      return;
    }
    setState(() => _speaking = true);
    await _tts.setLanguage(_languageLocales[_selectedLanguage] ?? 'hi-IN');
    await _tts.speak(text);
  }

  Future<void> _askQuestion() async {
    if (_questionController.text.trim().isEmpty) return;
    setState(() { _loading = true; _answer = ''; });

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/ask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': _questionController.text,
          'language': _selectedLanguage,
          'subject': _selectedSubject,
          'grade': _selectedGrade,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() => _answer = data['answer']);
        await DBHelper.saveSession(_questionController.text, _selectedSubject, _selectedLanguage, _selectedGrade, widget.profile['name']);
      }
    } catch (e) {
      setState(() => _answer = 'Error: Could not connect to server.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white30,
              child: Text(widget.profile['name'][0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Text(widget.profile['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgressScreen(profileName: widget.profile['name']))),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedLanguage,
                      decoration: const InputDecoration(labelText: 'Language', border: OutlineInputBorder(), isDense: true),
                      items: _languageLocales.keys.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                      onChanged: (v) => setState(() => _selectedLanguage = v!),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedSubject,
                            decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder(), isDense: true),
                            items: _subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (v) => setState(() => _selectedSubject = v!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedGrade,
                            decoration: const InputDecoration(labelText: 'Grade', border: OutlineInputBorder(), isDense: true),
                            items: List.generate(8, (i) => i + 1).map((g) => DropdownMenuItem(value: g, child: Text('Grade $g'))).toList(),
                            onChanged: (v) => setState(() => _selectedGrade = v!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    decoration: InputDecoration(
                      labelText: 'Ask your question...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'Type, speak or scan',
                    ),
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    GestureDetector(
                      onTapDown: (_) => _startListening(),
                      onTapUp: (_) => _stopListening(),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _listening ? Colors.red : const Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)],
                        ),
                        child: Icon(_listening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 24),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _showImageOptions,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)],
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _askQuestion,
                icon: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_loading ? 'Thinking...' : 'Ask Tutor', style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_answer.isNotEmpty)
              Expanded(
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  color: const Color(0xFFE8F5E9),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.auto_awesome, color: Color(0xFF2E7D32), size: 20),
                                SizedBox(width: 6),
                                Text('Tutor says:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                              ],
                            ),
                            IconButton(
                              onPressed: () => _speak(_answer),
                              icon: Icon(_speaking ? Icons.stop_circle : Icons.volume_up, color: const Color(0xFF2E7D32)),
                            ),
                          ],
                        ),
                        const Divider(),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(_answer, style: const TextStyle(fontSize: 16, height: 1.6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Progress Screen ───────────────────────────────────────────────────────────
class ProgressScreen extends StatefulWidget {
  final String profileName;
  const ProgressScreen({super.key, required this.profileName});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<Map<String, dynamic>> _sessions = [];
  Map<String, int> _subjectCounts = {};
  int _todayCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final sessions = await DBHelper.getSessions(widget.profileName);
    final counts = await DBHelper.getSubjectCounts(widget.profileName);
    final today = await DBHelper.getTodayCount(widget.profileName);
    setState(() { _sessions = sessions; _subjectCounts = counts; _todayCount = today; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.profileName}\'s Progress'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _summaryCard('${_sessions.length}', 'Total Questions', Icons.quiz)),
                const SizedBox(width: 12),
                Expanded(child: _summaryCard('$_todayCount', 'Today', Icons.today)),
                const SizedBox(width: 12),
                Expanded(child: _summaryCard('${_subjectCounts.length}', 'Subjects', Icons.book)),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Questions by Subject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_subjectCounts.isEmpty)
                      const Text('No questions yet!', style: TextStyle(color: Colors.grey))
                    else
                      ..._subjectCounts.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            SizedBox(width: 70, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: e.value / (_sessions.isEmpty ? 1 : _sessions.length),
                                  backgroundColor: Colors.grey[200],
                                  color: const Color(0xFF2E7D32),
                                  minHeight: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Recent Questions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _sessions.isEmpty
                  ? Center(child: Text('No questions yet!', style: TextStyle(color: Colors.grey[500])))
                  : ListView.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (_, i) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF2E7D32),
                            child: const Icon(Icons.question_answer, color: Colors.white, size: 18),
                          ),
                          title: Text(_sessions[i]['question'], maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${_sessions[i]['subject']} • ${_sessions[i]['language']} • Grade ${_sessions[i]['grade']}'),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF2E7D32), size: 24),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ─── Parent Dashboard ──────────────────────────────────────────────────────────
class ParentDashboard extends StatefulWidget {
  final Map<String, dynamic> profile;
  const ParentDashboard({super.key, required this.profile});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  List<Map<String, dynamic>> _sessions = [];
  Map<String, int> _subjectCounts = {};
  int _todayCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final sessions = await DBHelper.getSessions(widget.profile['name']);
    final counts = await DBHelper.getSubjectCounts(widget.profile['name']);
    final today = await DBHelper.getTodayCount(widget.profile['name']);
    setState(() { _sessions = sessions; _subjectCounts = counts; _todayCount = today; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: Text('${widget.profile['name']}\'s Report'),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: const Color(0xFF2E7D32),
                      child: Text(widget.profile['name'][0].toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.profile['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Grade ${widget.profile['grade']} • ${widget.profile['language']}', style: const TextStyle(color: Colors.grey)),
                        if (widget.profile['parent_name'] != null && widget.profile['parent_name'].toString().isNotEmpty)
                          Text('Parent: ${widget.profile['parent_name']}', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Learning Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _statCard('${_sessions.length}', 'Total\nQuestions', Icons.quiz, const Color(0xFF2E7D32))),
                const SizedBox(width: 12),
                Expanded(child: _statCard('$_todayCount', 'Questions\nToday', Icons.today, const Color(0xFF1565C0))),
                const SizedBox(width: 12),
                Expanded(child: _statCard('${_subjectCounts.length}', 'Subjects\nStudied', Icons.book, const Color(0xFF6A1B9A))),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Subject Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_subjectCounts.isEmpty)
                      const Text('No activity yet', style: TextStyle(color: Colors.grey))
                    else
                      ..._subjectCounts.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            SizedBox(width: 80, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: e.value / (_sessions.isEmpty ? 1 : _sessions.length),
                                  backgroundColor: Colors.grey[200],
                                  color: const Color(0xFF2E7D32),
                                  minHeight: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${e.value}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Recent Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_sessions.isEmpty)
              Center(child: Text('No activity yet', style: TextStyle(color: Colors.grey[500])))
            else
              ..._sessions.take(10).map((s) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF2E7D32),
                    child: Icon(Icons.question_answer, color: Colors.white, size: 18),
                  ),
                  title: Text(s['question'], maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${s['subject']} • ${s['language']} • ${s['timestamp'].toString().substring(0, 10)}'),
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}

