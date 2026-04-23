import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

// ─── Color Palette ───────────────────────────────────────────────────────────
const Color kRegalBlue    = Color(0xFF1A3A5C);
const Color kCerulean     = Color(0xFF0A7EA4);
const Color kMalibu       = Color(0xFF6EC6F5);
const Color kCeriseRed    = Color(0xFFDA2C6B);
const Color kSilverChalice = Color(0xFFAAAAAA);
const Color kDoveGray     = Color(0xFF6D6D6D);
const Color kWoodsmoke    = Color(0xFF1A1A1A);
const Color kWhite        = Color(0xFFFFFFFF);
const Color kBackground   = Color(0xFFF4F7FA);

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const NativeMindsApp());
}

const String backendUrl = 'http://192.168.194.116:8000';




// ─── Database Helper ───────────────────────────────────────────────────────────
class DBHelper {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'nativeminds_v6.db'),
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
            parent_phone TEXT,
            avatar TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE streaks(
            id INTEGER PRIMARY KEY,
            profile TEXT,
            last_date TEXT,
            current_streak INTEGER,
            max_streak INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE quiz_scores(
            id INTEGER PRIMARY KEY,
            profile TEXT,
            subject TEXT,
            difficulty TEXT,
            score INTEGER,
            total INTEGER,
            timestamp TEXT
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
      'question': question, 'subject': subject, 'language': language,
      'grade': grade, 'profile': profile, 'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getSessions(String profile) async {
    final database = await db;
    return database.query('sessions', where: 'profile = ?', whereArgs: [profile], orderBy: 'id DESC', limit: 50);
  }

  static Future<Map<String, int>> getSubjectCounts(String profile) async {
    final database = await db;
    final results = await database.rawQuery(
      'SELECT subject, COUNT(*) as count FROM sessions WHERE profile = ? GROUP BY subject', [profile],
    );
    return {for (var r in results) r['subject'] as String: r['count'] as int};
  }

  static Future<List<Map<String, dynamic>>> getProfiles() async {
    final database = await db;
    return database.query('profiles');
  }

  static Future<void> saveProfile(String name, String language, int grade, String parentName, String parentPhone, String avatar) async {
    final database = await db;
    await database.insert('profiles', {
      'name': name, 'language': language, 'grade': grade,
      'parent_name': parentName, 'parent_phone': parentPhone, 'avatar': avatar,
    });
  }

  static Future<void> deleteProfile(int id, String name) async {
    final database = await db;
    await database.delete('profiles', where: 'id = ?', whereArgs: [id]);
    await database.delete('sessions', where: 'profile = ?', whereArgs: [name]);
    await database.delete('streaks', where: 'profile = ?', whereArgs: [name]);
    await database.delete('quiz_scores', where: 'profile = ?', whereArgs: [name]);
  }

  static Future<int> getTodayCount(String profile) async {
    final database = await db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await database.rawQuery(
      'SELECT COUNT(*) as count FROM sessions WHERE profile = ? AND timestamp LIKE ?', [profile, '$today%'],
    );
    return result.first['count'] as int;
  }

  static Future<Map<String, int>> getStreak(String profile) async {
    final database = await db;
    final rows = await database.query('streaks', where: 'profile = ?', whereArgs: [profile]);
    if (rows.isEmpty) return {'current': 0, 'max': 0};
    return {'current': rows.first['current_streak'] as int, 'max': rows.first['max_streak'] as int};
  }

  static Future<void> saveQuizScore(String profile, String subject, String difficulty, int score, int total) async {
    final database = await db;
    await database.insert('quiz_scores', {
      'profile': profile, 'subject': subject, 'difficulty': difficulty,
      'score': score, 'total': total, 'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getQuizScores(String profile) async {
    final database = await db;
    return database.query('quiz_scores', where: 'profile = ?', whereArgs: [profile], orderBy: 'id DESC', limit: 20);
  }

  static Future<Map<String, double>> getAvgScoreBySubject(String profile) async {
    final database = await db;
    final results = await database.rawQuery(
      'SELECT subject, AVG(CAST(score AS FLOAT)/total)*100 as avg FROM quiz_scores WHERE profile = ? GROUP BY subject', [profile],
    );
    return {for (var r in results) r['subject'] as String: (r['avg'] as num).toDouble()};
  }

  static Future<void> updateStreak(String profile) async {
    final database = await db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    final rows = await database.query('streaks', where: 'profile = ?', whereArgs: [profile]);

    if (rows.isEmpty) {
      await database.insert('streaks', {'profile': profile, 'last_date': today, 'current_streak': 1, 'max_streak': 1});
    } else {
      final lastDate = rows.first['last_date'] as String;
      int current = rows.first['current_streak'] as int;
      int max = rows.first['max_streak'] as int;
      if (lastDate == today) return;
      if (lastDate == yesterday) { current++; }
      else { current = 1; }
      if (current > max) { max = current; }
      await database.update('streaks', {'last_date': today, 'current_streak': current, 'max_streak': max}, where: 'profile = ?', whereArgs: [profile]);
    }
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
        colorScheme: ColorScheme.fromSeed(seedColor: kRegalBlue),
        useMaterial3: true,
        scaffoldBackgroundColor: kBackground,
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
    'marathi': 'mr-IN', 'hindi': 'hi-IN', 'tamil': 'ta-IN', 'telugu': 'te-IN',
    'bengali': 'bn-IN', 'kannada': 'kn-IN', 'gujarati': 'gu-IN', 'punjabi': 'pa-IN',
  };

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
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
    String selectedAvatar = '🧒';

    final avatars = ['🧒','👦','👧','🧑','👩','👨','🧑‍🎓','👩‍🎓','👨‍🎓','🦁','🐯','🐻','🦊','🐸','🐧','🦋','🌟','🚀'];

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
                const SizedBox(height: 16),
                const Text('Pick Avatar', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: avatars.map((e) => GestureDetector(
                    onTap: () => setModalState(() => selectedAvatar = e),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selectedAvatar == e ? kCerulean : kMalibu.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selectedAvatar == e ? kCerulean : Colors.transparent),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 12),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Student Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(initialValue: selectedLanguage,
                  decoration: const InputDecoration(labelText: 'Mother Tongue', border: OutlineInputBorder(), prefixIcon: Icon(Icons.language)),
                  items: _languages.keys.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (v) => setModalState(() => selectedLanguage = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(initialValue: selectedGrade,
                  decoration: const InputDecoration(labelText: 'Grade', border: OutlineInputBorder(), prefixIcon: Icon(Icons.school)),
                  items: List.generate(8, (i) => i + 1).map((g) => DropdownMenuItem(value: g, child: Text('Grade $g'))).toList(),
                  onChanged: (v) => setModalState(() => selectedGrade = v!),
                ),
                const SizedBox(height: 12),
                TextField(controller: parentNameController, decoration: const InputDecoration(labelText: 'Parent Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.family_restroom))),
                const SizedBox(height: 12),
                TextField(
                  controller: parentPhoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: const InputDecoration(
                    labelText: 'Parent Phone',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                    prefixText: '+91 ',
                    counterText: '',
                    hintText: '10-digit mobile number',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) return;
                      final phone = parentPhoneController.text.trim();
                      if (phone.isNotEmpty && phone.length != 10) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid 10-digit phone number')),
                        );
                        return;
                      }
                      await DBHelper.saveProfile(nameController.text.trim(), selectedLanguage, selectedGrade, parentNameController.text.trim(), parentPhoneController.text.trim(), selectedAvatar);
                      if (context.mounted) {
                        Navigator.pop(context);
                        _loadProfiles();
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: kCerulean, foregroundColor: kWhite, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [kRegalBlue, kCerulean], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28))
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.school, color: Colors.white, size: 28)),
                      const SizedBox(width: 12),
                      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('NativeMinds', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('Powered by Gemma 4', style: TextStyle(fontSize: 12, color: Colors.white70)),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    _statCard('${_profiles.length}', 'Students'),
                    const SizedBox(width: 12),
                    _statCard('8+', 'Languages'),
                    const SizedBox(width: 12),
                    _statCard('5', 'Subjects'),
                  ]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                _tabButton('Students', 0),
                const SizedBox(width: 8),
                _tabButton('Parents', 1),
              ]),
            ),
            Expanded(child: _selectedTab == 0 ? _studentsTab() : _parentsTab()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProfile,
        backgroundColor: kCeriseRed,
        foregroundColor: kWhite,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Student'),
      ),
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
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
            color: selected ? kRegalBlue : kWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kRegalBlue),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? kWhite : kRegalBlue, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _studentsTab() {
    if (_profiles.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.person_add, size: 80, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text('No students yet', style: TextStyle(fontSize: 18, color: Colors.grey[500])),
        const SizedBox(height: 8),
        Text('Tap + to add a student', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
      ]));
    }

    final colors = [kRegalBlue, kCerulean, kCeriseRed, Color(0xFF0A5C6B)];
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.95),
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
              await DBHelper.deleteProfile(profile['id'], profile['name']);
              if (mounted) _loadProfiles();
            }
          },
          child: Container(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircleAvatar(radius: 32, backgroundColor: Colors.white.withValues(alpha: 0.25), child: Text(profile['avatar'] ?? profile['name'][0].toUpperCase(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white))),
              const SizedBox(height: 10),
              Text(profile['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              Text('${profile['language']} • Grade ${profile['grade']}', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)), child: const Text('Tap to learn', style: TextStyle(fontSize: 11, color: Colors.white))),
            ]),
          ),
        );
      },
    );
  }

  Widget _parentsTab() {
    if (_profiles.isEmpty) return Center(child: Text('No students added yet', style: TextStyle(color: Colors.grey[500])));
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
              child: Row(children: [
                CircleAvatar(radius: 28, backgroundColor: kCerulean, child: Text(profile['avatar'] ?? profile['name'][0].toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white))),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Grade ${profile['grade']} • ${profile['language']}', style: const TextStyle(color: Colors.grey)),
                  if (profile['parent_name'] != null && profile['parent_name'].toString().isNotEmpty)
                    Text('Parent: ${profile['parent_name']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ])),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ─── Typing Animation ────────────────────────────────────────────────────────
class TypingAnimation extends StatefulWidget {
  const TypingAnimation({super.key});

  @override
  State<TypingAnimation> createState() => _TypingAnimationState();
}

class _TypingAnimationState extends State<TypingAnimation> {
  int _dotCount = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() => _dotCount = (_dotCount + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 10, height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: i < _dotCount ? kCerulean : kMalibu.withValues(alpha: 0.3),
        ),
      )),
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
  final List<Map<String, String>> _messages = [];
  final ScrollController _chatScrollController = ScrollController();
  String _answer = '';
  bool _loading = false;
  bool _listening = false;
  bool _speaking = false;
  bool _showQuiz = false;
  String _quizContent = '';
  bool _loadingQuiz = false;
  List<Map<String, dynamic>> _parsedQuiz = [];
  List<int?> _selectedAnswers = [];
  List<bool> _revealed = [];
  List<String?> _explanations = [];
  List<bool> _loadingExplanation = [];
  List<String?> _hints = [];
  List<bool> _loadingHint = [];
  late String _selectedLanguage;
  String _selectedSubject = 'math';
  late int _selectedGrade;
  int _currentStreak = 0;
  String _selectedDifficulty = 'medium';

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
    _fetchLessonOfDay();
    _loadStreak();
  }

  Future<void> _loadStreak() async {
    final streak = await DBHelper.getStreak(widget.profile['name']);
    setState(() { _currentStreak = streak['current']!; });
  }

  Future<void> _fetchLessonOfDay() async {
    await Future.delayed(const Duration(seconds: 1));
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/lesson-of-day'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': 'lesson of the day', 'language': _selectedLanguage, 'subject': _selectedSubject, 'grade': _selectedGrade}),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(children: [
                Text('📚 ', style: TextStyle(fontSize: 20)),
                Text('Lesson of the Day', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
              ]),
              content: Text(data['lesson'], style: const TextStyle(fontSize: 14, height: 1.5)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Start Learning! 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _askWithImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 85);
    if (image == null) return;

    final question = _questionController.text.isEmpty ? 'Explain this image in detail' : _questionController.text;
    setState(() {
      _messages.add({'role': 'user', 'content': '📷 $question'});
      _loading = true;
      _showQuiz = false;
      _questionController.clear();
    });
    _scrollToBottom();

    try {
      final request = http.MultipartRequest('POST', Uri.parse('$backendUrl/ask-image'));
      request.fields['language'] = _selectedLanguage;
      request.fields['subject'] = _selectedSubject;
      request.fields['grade'] = _selectedGrade.toString();
      request.fields['question'] = question;
      request.files.add(await http.MultipartFile.fromPath('image', image.path));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final aiReply = data['answer'] as String;
        setState(() {
          _answer = aiReply;
          _messages.add({'role': 'ai', 'content': aiReply});
        });
        _scrollToBottom();
        await DBHelper.saveSession('📷 Image question', _selectedSubject, _selectedLanguage, _selectedGrade, widget.profile['name']);
      } else {
        setState(() => _messages.add({'role': 'ai', 'content': 'Error: Could not process image.'}));
      }
    } catch (e) {
      setState(() => _messages.add({'role': 'ai', 'content': 'Error: Could not connect to server.'}));
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  Future<void> _scanTextFromImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    setState(() { _loading = true; _answer = 'Reading text from image...'; });

    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizer = TextRecognizer();
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      if (recognized.text.isNotEmpty) {
        setState(() => _questionController.text = recognized.text.trim());
        await _askQuestion();
      } else {
        await _askWithImage(source);
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
            const Text('What do you want to scan?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _imageOptionBtn(Icons.text_fields, 'Scan Text', 'Textbook pages', () { Navigator.pop(context); _scanTextFromImage(ImageSource.camera); })),
              const SizedBox(width: 12),
              Expanded(child: _imageOptionBtn(Icons.image_search, 'Explain Image', 'Diagrams & pictures', () { Navigator.pop(context); _askWithImage(ImageSource.camera); })),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _imageOptionBtn(Icons.photo_library, 'Gallery Text', 'From gallery', () { Navigator.pop(context); _scanTextFromImage(ImageSource.gallery); })),
              const SizedBox(width: 12),
              Expanded(child: _imageOptionBtn(Icons.collections, 'Gallery Image', 'From gallery', () { Navigator.pop(context); _askWithImage(ImageSource.gallery); })),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _imageOptionBtn(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kMalibu.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: kCerulean)),
        child: Column(children: [
          Icon(icon, size: 28, color: kCerulean),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kCerulean)),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      ),
    );
  }

  Future<void> _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _listening = true);
      _speech.listen(onResult: (result) => setState(() => _questionController.text = result.recognizedWords), localeId: _languageLocales[_selectedLanguage]);
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _listening = false);
  }

  String _cleanForSpeech(String text) {
    return text
        .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27FF}\u{2300}-\u{23FF}\u{2B00}-\u{2BFF}\u{FE00}-\u{FEFF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA9F}]', unicode: true), '')
        .replaceAll(RegExp(r'\*\*|\*|__|_|~~|`|#{1,6}\s?'), '')
        .replaceAll(RegExp(r'^[-•>]\s?', multiLine: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _scoreSaved = false;

  @override
  void dispose() {
    _questionController.dispose();
    _chatScrollController.dispose();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    if (_speaking) { await _tts.stop(); setState(() => _speaking = false); return; }
    setState(() => _speaking = true);
    await _tts.setLanguage(_languageLocales[_selectedLanguage] ?? 'hi-IN');
    await _tts.speak(_cleanForSpeech(text));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _askQuestion() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'content': question});
      _loading = true;
      _showQuiz = false;
      _questionController.clear();
    });
    _scrollToBottom();

    try {
      // history = all messages except the one we just added, with correct roles
      final history = _messages.length > 1
          ? _messages
              .sublist(0, _messages.length - 1)
              .map((m) => {
                    'role': m['role'] == 'ai' ? 'assistant' : 'user',
                    'content': m['content']!,
                  })
              .toList()
          : <Map<String, String>>[];

      final response = await http.post(
        Uri.parse('$backendUrl/ask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': question,
          'language': _selectedLanguage,
          'subject': _selectedSubject,
          'grade': _selectedGrade,
          'history': history,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final aiReply = data['answer'] as String;
        setState(() {
          _answer = aiReply;
          _messages.add({'role': 'ai', 'content': aiReply});
        });
        _scrollToBottom();
        await DBHelper.saveSession(question, _selectedSubject, _selectedLanguage, _selectedGrade, widget.profile['name']);
        await DBHelper.updateStreak(widget.profile['name']);
        await _loadStreak();
      } else {
        setState(() => _messages.add({'role': 'ai', 'content': 'Error: Server returned ${response.statusCode}.'}));
      }
    } catch (e) {
      setState(() => _messages.add({'role': 'ai', 'content': 'Error: Could not connect to server.'}));
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  List<Map<String, dynamic>> _parseQuiz(String raw) {
    final List<Map<String, dynamic>> questions = [];
    final blocks = RegExp(r'Q\d+:.*?(?=Q\d+:|$)', dotAll: true).allMatches(raw);
    for (final block in blocks) {
      final text = block.group(0)!;
      final qMatch = RegExp(r'Q\d+:\s*(.+?)\n').firstMatch(text);
      final options = RegExp(r'([A-D])\)\s*(.+?)\n').allMatches(text).map((m) => {'letter': m.group(1)!, 'text': m.group(2)!.trim()}).toList();
      final answerMatch = RegExp(r'Answer:\s*([A-D])').firstMatch(text);
      if (qMatch != null && options.length == 4 && answerMatch != null) {
        questions.add({'question': qMatch.group(1)!.trim(), 'options': options, 'answer': answerMatch.group(1)!});
      }
    }
    return questions;
  }

  Future<void> _fetchExplanation(int qi, String question) async {
    setState(() => _loadingExplanation[qi] = true);
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/explain'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': question, 'language': _selectedLanguage, 'subject': _selectedSubject, 'grade': _selectedGrade}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() => _explanations[qi] = data['explanation']);
      }
    } catch (_) {
      setState(() => _explanations[qi] = null);
    } finally {
      setState(() => _loadingExplanation[qi] = false);
    }
  }

  Future<void> _fetchHint(int qi, String question) async {
    setState(() => _loadingHint[qi] = true);
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/hint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': question, 'language': _selectedLanguage, 'subject': _selectedSubject, 'grade': _selectedGrade}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() => _hints[qi] = data['hint']);
      }
    } catch (_) {
    } finally {
      setState(() => _loadingHint[qi] = false);
    }
  }

  Widget _buildScoreCard() {
    final score = _revealed.isEmpty ? 0 : List.generate(_parsedQuiz.length, (i) {
      final selected = _selectedAnswers[i];
      if (selected == null) return 0;
      final opts = _parsedQuiz[i]['options'] as List;
      return opts[selected]['letter'] == _parsedQuiz[i]['answer'] ? 1 : 0;
    }).fold(0, (a, b) => a + b);
    final total = _parsedQuiz.length;
    final emoji = score == total ? '🎉🌟' : score >= total / 2 ? '👏😊' : '💪😊';
    final message = score == total ? 'Perfect Score!' : score >= total / 2 ? 'Good Job!' : 'Keep Practicing!';
    final color = score == total ? Colors.green : score >= total / 2 ? Colors.orange : Colors.red;
    if (!_scoreSaved) {
      _scoreSaved = true;
      DBHelper.saveQuizScore(widget.profile['name'], _selectedSubject, _selectedDifficulty, score, total);
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text('$score / $total correct', style: TextStyle(fontSize: 16, color: color)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _generateQuiz,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ]),
    );
  }

  Future<void> _generateQuiz() async {
    setState(() { _loadingQuiz = true; _showQuiz = false; });

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/quiz'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': _answer.isNotEmpty ? _answer : _questionController.text, 'language': _selectedLanguage, 'subject': _selectedSubject, 'grade': _selectedGrade, 'difficulty': _selectedDifficulty}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final parsed = _parseQuiz(data['quiz']);
        setState(() {
          _quizContent = data['quiz'];
          _parsedQuiz = parsed;
          _selectedAnswers = List.filled(parsed.length, null);
          _revealed = List.filled(parsed.length, false);
          _explanations = List.filled(parsed.length, null);
          _loadingExplanation = List.filled(parsed.length, false);
          _hints = List.filled(parsed.length, null);
          _loadingHint = List.filled(parsed.length, false);
          _showQuiz = true;
          _scoreSaved = false;
        });
      }
    } catch (e) {
      setState(() => _quizContent = 'Error generating quiz.');
    } finally {
      setState(() => _loadingQuiz = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          const SizedBox(width: 16),
          CircleAvatar(radius: 14, backgroundColor: kMalibu.withValues(alpha: 0.4), child: Text(widget.profile['avatar'] ?? widget.profile['name'][0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12))),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.profile['name'], style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
        ]),
        backgroundColor: kRegalBlue,
        foregroundColor: kWhite,
        actions: [
          if (_currentStreak > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🔥', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text('$_currentStreak', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ]),
              ),
            ),
          IconButton(icon: const Icon(Icons.style), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FlashcardsScreen(profile: widget.profile)))),
          IconButton(icon: const Icon(Icons.bar_chart), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgressScreen(profileName: widget.profile['name'])))),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () => setState(() { _messages.clear(); _answer = ''; _showQuiz = false; }),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // ── controls panel ──
            Container(
              color: kWhite,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // row 1: language dropdown (full width)
                DropdownButtonFormField<String>(
                  initialValue: _selectedLanguage,
                  decoration: const InputDecoration(labelText: 'Language', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  items: _languageLocales.keys.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (v) => setState(() => _selectedLanguage = v!),
                ),
                const SizedBox(height: 8),

                // row 2: subject + grade side by side
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedSubject,
                      decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                      items: _subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setState(() => _selectedSubject = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _selectedGrade,
                      decoration: const InputDecoration(labelText: 'Grade', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                      items: List.generate(8, (i) => i + 1).map((g) => DropdownMenuItem(value: g, child: Text('Grade $g'))).toList(),
                      onChanged: (v) => setState(() => _selectedGrade = v!),
                    ),
                  ),
                ]),

                const SizedBox(height: 8),

                // row 3: question input + mic + camera
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _questionController,
                      decoration: InputDecoration(
                        hintText: 'Ask your question...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true, fillColor: kBackground, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTapDown: (_) => _startListening(),
                    onTapUp: (_) => _stopListening(),
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: _listening ? kCeriseRed : kCerulean, shape: BoxShape.circle),
                      child: Icon(_listening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showImageOptions,
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: kRegalBlue, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 22),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),

                // row 4: Ask + Quiz buttons
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _askQuestion,
                      icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send, size: 16),
                      label: Text(_loading ? 'Thinking...' : 'Ask Tutor'),
                      style: ElevatedButton.styleFrom(backgroundColor: kCerulean, foregroundColor: kWhite, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loadingQuiz ? null : _generateQuiz,
                      icon: _loadingQuiz ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.quiz, size: 16),
                      label: const Text('Generate Quiz'),
                      style: ElevatedButton.styleFrom(backgroundColor: kCeriseRed, foregroundColor: kWhite, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),

                // row 5: difficulty chips
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Difficulty:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kDoveGray)),
                  const SizedBox(width: 10),
                  ...['easy', 'medium', 'hard'].map((d) {
                    final selected = _selectedDifficulty == d;
                    final color = d == 'easy' ? Colors.green : d == 'medium' ? Colors.orange : kCeriseRed;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedDifficulty = d),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected ? color : color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color),
                        ),
                        child: Text(d[0].toUpperCase() + d.substring(1), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: selected ? kWhite : color)),
                      ),
                    );
                  }),
                ]),

              ]),
            ),
            const Divider(height: 1),
            // ── chat area ──
            Expanded(
              child: _messages.isEmpty && !_loading
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('Ask a question to start learning!', style: TextStyle(fontSize: 15, color: Colors.grey[400])),
                      ]),
                    )
                  : ListView.builder(
                      controller: _chatScrollController,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: _messages.length + (_loading ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (_loading && i == _messages.length) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10, right: 60),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: kMalibu.withValues(alpha: 0.2),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(4),
                                  topRight: Radius.circular(16),
                                  bottomLeft: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                              ),
                              child: const TypingAnimation(),
                            ),
                          );
                        }
                        final msg = _messages[i];
                        final isUser = msg['role'] == 'user';
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: EdgeInsets.only(
                              bottom: 10,
                              left: isUser ? 60 : 0,
                              right: isUser ? 0 : 60,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isUser ? kCerulean : kWhite,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isUser ? 16 : 4),
                                bottomRight: Radius.circular(isUser ? 4 : 16),
                              ),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 4, offset: const Offset(0, 2))],
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (!isUser)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.auto_awesome, size: 13, color: kCerulean),
                                    const SizedBox(width: 4),
                                    const Text('Tutor', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kCerulean)),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () => _speak(msg['content']!),
                                      child: Icon(_speaking ? Icons.stop_circle : Icons.volume_up, size: 16, color: kCerulean),
                                    ),
                                  ]),
                                ),
                              Text(
                                msg['content']!,
                                style: TextStyle(fontSize: 15, height: 1.5, color: isUser ? kWhite : kWoodsmoke),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
            if (_showQuiz)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.45,
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  color: kCeriseRed.withValues(alpha: 0.07),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Row(children: [
                          Icon(Icons.quiz, color: kCeriseRed, size: 20),
                          SizedBox(width: 6),
                          Text('Quiz Time!', style: TextStyle(fontWeight: FontWeight.bold, color: kCeriseRed)),
                          SizedBox(width: 8),
                        ]),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _selectedDifficulty == 'easy' ? Colors.green : _selectedDifficulty == 'hard' ? kCeriseRed : Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(_selectedDifficulty.toUpperCase(), style: const TextStyle(fontSize: 10, color: kWhite, fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _showQuiz = false),
                            icon: const Icon(Icons.close, color: kCeriseRed),
                          ),
                        ]),
                      ]),
                      const Divider(),
                      Expanded(
                        child: _parsedQuiz.isEmpty
                            ? SingleChildScrollView(child: Text(_quizContent, style: const TextStyle(fontSize: 15, height: 1.6)))
                            : ListView.builder(
                                itemCount: _parsedQuiz.length,
                                itemBuilder: (_, qi) {
                                  final q = _parsedQuiz[qi];
                                  final selected = _selectedAnswers[qi];
                                  final revealed = _revealed[qi];
                                  final correctLetter = q['answer'] as String;
                                  final options = q['options'] as List;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('Q${qi + 1}: ${q['question']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 6),
                                      if (!revealed)
                                        GestureDetector(
                                          onTap: _loadingHint[qi] ? null : () => _fetchHint(qi, q['question'] as String),
                                          child: Row(children: [
                                            _loadingHint[qi]
                                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kCerulean))
                                                : const Text('💡', style: TextStyle(fontSize: 14)),
                                            const SizedBox(width: 4),
                                            Text(_loadingHint[qi] ? 'Getting hint...' : 'Get a hint', style: const TextStyle(fontSize: 12, color: kCerulean, fontWeight: FontWeight.bold)),
                                          ]),
                                        ),
                                      if (_hints[qi] != null)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4, bottom: 6),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                                          child: Text('💡 ${_hints[qi]!}', style: const TextStyle(fontSize: 12, height: 1.4)),
                                        ),
                                      const SizedBox(height: 6),
                                      ...List.generate(options.length, (oi) {
                                        final opt = options[oi];
                                        final letter = opt['letter'] as String;
                                        final isCorrect = letter == correctLetter;
                                        final isSelected = selected == oi;
                                        Color btnColor = Colors.white;
                                        if (revealed) {
                                          if (isCorrect) { btnColor = Colors.green.shade100; }
                                          else if (isSelected) { btnColor = Colors.red.shade100; }
                                        }
                                        return GestureDetector(
                                          onTap: revealed ? null : () {
                                            setState(() {
                                              _selectedAnswers[qi] = oi;
                                              _revealed[qi] = true;
                                            });
                                            if (!isCorrect) { _fetchExplanation(qi, q['question'] as String); }
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.only(bottom: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: btnColor,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: revealed && isCorrect ? Colors.green : revealed && isSelected ? Colors.red : Colors.grey.shade300),
                                            ),
                                            child: Row(children: [
                                              Text('$letter) ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                              Expanded(child: Text(opt['text'] as String)),
                                              if (revealed && isCorrect) const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                              if (revealed && isSelected && !isCorrect) const Icon(Icons.cancel, color: Colors.red, size: 18),
                                            ]),
                                          ),
                                        );
                                      }),
                                      if (revealed && _loadingExplanation[qi])
                                        const Padding(
                                          padding: EdgeInsets.only(top: 8),
                                          child: Row(children: [
                                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kCeriseRed)),
                                            SizedBox(width: 8),
                                            Text('Getting explanation...', style: TextStyle(fontSize: 12, color: kCeriseRed)),
                                          ]),
                                        ),
                                      if (revealed && _explanations[qi] != null)
                                        Container(
                                          margin: const EdgeInsets.only(top: 8),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade50,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.orange.shade200),
                                          ),
                                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            const Text('💡 ', style: TextStyle(fontSize: 14)),
                                            Expanded(child: Text(_explanations[qi]!, style: const TextStyle(fontSize: 13, height: 1.4))),
                                          ]),
                                        ),
                                    ]),
                                  );
                                },
                              ),
                      ),
                      if (_revealed.isNotEmpty && !_revealed.contains(false)) _buildScoreCard(),
                    ]),
                  ),
                ),
              ),
        ]),
      ),
    );
  }
}

// ─── Flashcards Screen ────────────────────────────────────────────────────────
class FlashcardsScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const FlashcardsScreen({super.key, required this.profile});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  List<Map<String, String>> _cards = [];
  int _current = 0;
  bool _flipped = false;
  bool _loading = false;
  String _selectedSubject = 'math';
  final List<String> _subjects = ['math', 'science', 'history', 'english', 'geography'];

  List<Map<String, String>> _parseFlashcards(String raw) {
    final cards = <Map<String, String>>[];
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    String? front;
    final backLines = <String>[];
    for (final line in lines) {
      if (line.startsWith('FRONT:')) {
        if (front != null && backLines.isNotEmpty) {
          cards.add({'front': front, 'back': backLines.join(' ').trim()});
          backLines.clear();
        }
        front = line.replaceFirst('FRONT:', '').trim();
      } else if (line.startsWith('BACK:')) {
        backLines.add(line.replaceFirst('BACK:', '').trim());
      } else if (front != null && line.trim().isNotEmpty && !line.startsWith('FRONT:')) {
        backLines.add(line.trim());
      }
    }
    if (front != null && backLines.isNotEmpty) {
      cards.add({'front': front, 'back': backLines.join(' ').trim()});
    }
    return cards;
  }

  Future<void> _fetchFlashcards() async {
    setState(() { _loading = true; _cards = []; _current = 0; _flipped = false; });
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/flashcards'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': _selectedSubject,
          'language': widget.profile['language'],
          'subject': _selectedSubject,
          'grade': widget.profile['grade'],
          'history': [],
        }),
      ).timeout(const Duration(seconds: 120));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final parsed = _parseFlashcards(data['flashcards']);
        setState(() => _cards = parsed.isNotEmpty ? parsed : [{'front': 'No flashcards generated', 'back': 'Please try again'}]);
      } else {
        setState(() => _cards = [{'front': 'Server error ${response.statusCode}', 'back': response.body}]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cards = [{'front': 'Error', 'back': e.toString()}]);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text('Flashcards', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kRegalBlue,
        foregroundColor: kWhite,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(initialValue: _selectedSubject,
                  decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white),
                  items: _subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _selectedSubject = v!),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _loading ? null : _fetchFlashcards,
                style: ElevatedButton.styleFrom(backgroundColor: kCerulean, foregroundColor: kWhite, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20)),
                child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Generate'),
              ),
            ]),
            const SizedBox(height: 24),
            if (_loading)
              const Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                TypingAnimation(),
                SizedBox(height: 12),
                Text('Generating flashcards...', style: TextStyle(color: kCerulean, fontWeight: FontWeight.bold)),
              ])))
            else if (_cards.isEmpty)
              const Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('🃏', style: TextStyle(fontSize: 60)),
                SizedBox(height: 12),
                Text('Pick a subject and tap Generate', style: TextStyle(color: Colors.grey, fontSize: 15)),
              ])))
            else ...[
              Text('${_current + 1} / ${_cards.length}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _flipped = !_flipped),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: Container(
                      key: ValueKey('$_current-$_flipped'),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _flipped ? kRegalBlue : kWhite,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 6))],
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(_flipped ? '✅ Answer' : '❓ Question', style: TextStyle(fontSize: 13, color: _flipped ? Colors.white70 : Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _flipped ? _cards[_current]['back']! : _cards[_current]['front']!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _flipped ? kWhite : kCerulean, height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(_flipped ? 'Tap to see question' : 'Tap to reveal answer', style: TextStyle(fontSize: 12, color: _flipped ? Colors.white54 : Colors.grey)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton(
                  onPressed: _current > 0 ? () => setState(() { _current--; _flipped = false; }) : null,
                  icon: const Icon(Icons.arrow_back_ios),
                  color: kCerulean,
                  iconSize: 32,
                ),
                TextButton(
                  onPressed: _fetchFlashcards,
                  child: const Text('🔄 New Set', style: TextStyle(color: kCerulean, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: _current < _cards.length - 1 ? () => setState(() { _current++; _flipped = false; }) : null,
                  icon: const Icon(Icons.arrow_forward_ios),
                  color: kCerulean,
                  iconSize: 32,
                ),
              ]),
            ],
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
  List<Map<String, dynamic>> _quizScores = [];
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final sessions = await DBHelper.getSessions(widget.profileName);
    final counts = await DBHelper.getSubjectCounts(widget.profileName);
    final today = await DBHelper.getTodayCount(widget.profileName);
    final scores = await DBHelper.getQuizScores(widget.profileName);
    setState(() { _sessions = sessions; _subjectCounts = counts; _todayCount = today; _quizScores = scores; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.profileName}\'s Progress'),
        backgroundColor: kRegalBlue,
        foregroundColor: kWhite,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _summaryCard('${_sessions.length}', 'Total', Icons.quiz)),
            const SizedBox(width: 12),
            Expanded(child: _summaryCard('$_todayCount', 'Today', Icons.today)),
            const SizedBox(width: 12),
            Expanded(child: _summaryCard('${_subjectCounts.length}', 'Subjects', Icons.book)),
          ]),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('By Subject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_subjectCounts.isEmpty)
                  const Text('No questions yet!', style: TextStyle(color: Colors.grey))
                else
                  ..._subjectCounts.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      SizedBox(width: 70, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                      const SizedBox(width: 8),
                      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: e.value / (_sessions.isEmpty ? 1 : _sessions.length), backgroundColor: kSilverChalice.withValues(alpha: 0.2), color: kCerulean, minHeight: 14))),
                      const SizedBox(width: 8),
                      Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  )),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _tabButton('Questions', 0),
            const SizedBox(width: 8),
            _tabButton('Quiz Scores', 1),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: _selectedTab == 0
                ? (_sessions.isEmpty
                    ? Center(child: Text('No questions yet!', style: TextStyle(color: Colors.grey[500])))
                    : ListView.builder(
                        itemCount: _sessions.length,
                        itemBuilder: (_, i) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: const CircleAvatar(backgroundColor: kCerulean, child: Icon(Icons.question_answer, color: kWhite, size: 18)),
                            title: Text(_sessions[i]['question'], maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${_sessions[i]['subject']} • ${_sessions[i]['language']} • Grade ${_sessions[i]['grade']}'),
                          ),
                        ),
                      ))
                : (_quizScores.isEmpty
                    ? Center(child: Text('No quiz scores yet!', style: TextStyle(color: Colors.grey[500])))
                    : ListView.builder(
                        itemCount: _quizScores.length,
                        itemBuilder: (_, i) {
                          final s = _quizScores[i];
                          final pct = ((s['score'] as int) / (s['total'] as int) * 100).round();
                          final color = pct == 100 ? Colors.green : pct >= 50 ? Colors.orange : kCeriseRed;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: CircleAvatar(backgroundColor: color, child: Text('$pct%', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                              title: Text('${s['subject']} • ${s['difficulty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${s['score']}/${s['total']} correct • ${s['timestamp'].toString().substring(0, 10)}'),
                            ),
                          );
                        },
                      )),
          ),
        ]),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? kRegalBlue : kWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kRegalBlue),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? kWhite : kRegalBlue, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _summaryCard(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kMalibu.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: kCerulean.withValues(alpha: 0.3))),
      child: Column(children: [
        Icon(icon, color: kCerulean, size: 24),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kRegalBlue)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
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
      backgroundColor: kBackground,
      appBar: AppBar(
        title: Text('${widget.profile['name']}\'s Report'),
        backgroundColor: kRegalBlue,
        foregroundColor: kWhite,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(radius: 32, backgroundColor: kCerulean, child: Text(widget.profile['avatar'] ?? widget.profile['name'][0].toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kWhite))),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.profile['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Grade ${widget.profile['grade']} • ${widget.profile['language']}', style: const TextStyle(color: Colors.grey)),
                  if (widget.profile['parent_name'] != null && widget.profile['parent_name'].toString().isNotEmpty)
                    Text('Parent: ${widget.profile['parent_name']}', style: const TextStyle(fontSize: 13)),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _statCard('${_sessions.length}', 'Total\nQuestions', Icons.quiz, kCerulean)),
            const SizedBox(width: 12),
            Expanded(child: _statCard('$_todayCount', 'Questions\nToday', Icons.today, kRegalBlue)),
            const SizedBox(width: 12),
            Expanded(child: _statCard('${_subjectCounts.length}', 'Subjects\nStudied', Icons.book, kCeriseRed)),
          ]),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Subject Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_subjectCounts.isEmpty)
                  const Text('No activity yet', style: TextStyle(color: Colors.grey))
                else
                  ..._subjectCounts.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      SizedBox(width: 80, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: e.value / (_sessions.isEmpty ? 1 : _sessions.length), backgroundColor: kSilverChalice.withValues(alpha: 0.2), color: kCerulean, minHeight: 14))),
                      const SizedBox(width: 8),
                      Text('${e.value}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  )),
              ]),
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
                leading: const CircleAvatar(backgroundColor: kCerulean, child: Icon(Icons.question_answer, color: kWhite, size: 18)),
                title: Text(s['question'], maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${s['subject']} • ${s['language']} • ${s['timestamp'].toString().substring(0, 10)}'),
              ),
            )),
        ]),
      ),
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }
}








