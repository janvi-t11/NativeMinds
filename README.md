# 🌍 NativeMinds — AI Tutor for Every Indian Child

> **"Every child deserves a teacher who speaks their language."**

NativeMinds is a multilingual AI-powered tutoring app built for Indian school students in Grades 1–8. It runs entirely on-device using **Gemma 4 via Ollama** — no cloud, no subscriptions, no data privacy concerns. Just learning, in the child's mother tongue.

Built for the **Gemma 4 Good Hackathon** 🏆

---

## ✨ What It Does

| Feature | Description |
|---|---|
| 🗣️ AI Tutor Chat | Ask any school question, get culturally relevant answers in your language |
| 📝 Quiz Generator | Auto-generates 3 MCQs with hints, explanations & scoring |
| 🃏 Flashcards | Flip-card study tool generated on demand |
| 📷 Image Scanner | Scan textbook pages or diagrams — AI explains them |
| 🎙️ Voice Input | Speak your question in your mother tongue |
| 🔊 Text to Speech | Tutor reads answers aloud |
| 📚 Lesson of the Day | A fun daily lesson when you open the app |
| 🔥 Streaks | Daily learning streaks to keep kids motivated |
| 📊 Progress Tracking | Subject-wise question history & quiz scores |
| 👨‍👩‍👧 Parent Dashboard | Parents can monitor their child's learning activity |
| 👤 Multi-Profile | Multiple student profiles on one device |

---

## 🌐 Supported Languages

| Language | Locale |
|---|---|
| Marathi | mr-IN |
| Hindi | hi-IN |
| Tamil | ta-IN |
| Telugu | te-IN |
| Bengali | bn-IN |
| Kannada | kn-IN |
| Gujarati | gu-IN |
| Punjabi | pa-IN |

---

## 🧠 How It Works

```
📱 Flutter App (Android)
        ↓  HTTP
🐍 FastAPI Backend (Python)
        ↓  Ollama API
🤖 Gemma 4 (gemma4:e4b) — running locally
```

- The Flutter app sends questions with language, subject, grade, and conversation history
- FastAPI builds culturally-aware prompts with grade-appropriate language
- Gemma 4 generates responses entirely on-device via Ollama
- No data ever leaves your machine

---

## 🏗️ Project Structure

```
NativeMinds/
├── app/nativeminds/        # Flutter mobile app
│   └── lib/main.dart       # Full app code
├── backend/
│   └── main.py             # FastAPI backend
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter](https://flutter.dev/docs/get-started/install) (3.x+)
- [Python](https://python.org) 3.10+
- [Ollama](https://ollama.com/download)
- Android device or emulator

### 1. Pull the Gemma 4 Model

```bash
ollama pull gemma4:e4b
ollama serve
```

### 2. Start the Backend

```bash
cd backend
pip install fastapi uvicorn ollama python-multipart
uvicorn main:app --host 0.0.0.0 --port 8000
```

### 3. Configure the App

In `app/nativeminds/lib/main.dart`, update the backend URL:

```dart
// For local network (phone + PC on same WiFi)
const String backendUrl = 'http://YOUR_PC_IP:8000';

// For remote access via ngrok
const String backendUrl = 'https://your-ngrok-url.ngrok-free.app';
```

Find your PC IP:
```bash
# Windows
ipconfig | findstr "IPv4"
```

### 4. Run the App

```bash
cd app/nativeminds
flutter pub get
flutter run
```

---

## 📡 API Endpoints

| Endpoint | Description |
|---|---|
| `POST /ask` | Main tutor chat with conversation history |
| `POST /ask-image` | Explain an image (diagram/textbook) |
| `POST /quiz` | Generate 3 MCQs on a topic |
| `POST /flashcards` | Generate 5 flip flashcards |
| `POST /lesson-of-day` | Daily lesson for a subject |
| `POST /hint` | Get a hint for a quiz question |
| `POST /explain` | Explain a wrong quiz answer |
| `GET /health` | Health check |

---

## 🎯 Hackathon Track Alignment

| Track | Why NativeMinds Qualifies |
|---|---|
| 🦙 **Ollama Prize** | Entire AI runs locally via Ollama with Gemma 4 |
| 📱 **Cactus Prize** | Local-first Flutter mobile app |
| 🎓 **Future of Education** | Multi-feature adaptive learning agent |
| 🌏 **Digital Equity & Inclusivity** | 8 Indian languages, offline-capable, zero cost |

---

## 🛠️ Tech Stack

- **Frontend:** Flutter (Dart) — Android
- **Backend:** Python, FastAPI
- **AI Model:** Gemma 4 (`gemma4:e4b`) via Ollama
- **Database:** SQLite (sqflite)
- **Speech:** flutter_tts, speech_to_text
- **OCR:** Google ML Kit Text Recognition
- **Tunnel:** ngrok (optional, for remote access)

---

## 🔒 Privacy

All AI processing happens **100% on your local machine**. No student data, questions, or answers are sent to any external server. This makes NativeMinds safe for children and compliant with school data privacy requirements.

---

## 📋 Requirements

- Android 6.0+ device
- PC with minimum 16 GB RAM (for Gemma 4)
- Both device and PC on the same WiFi network (or ngrok for remote)

---

## 📄 License

This project is licensed under **CC-BY 4.0** in accordance with the Gemma 4 Good Hackathon rules.

---

## 🙏 Acknowledgements

- [Google Gemma 4](https://ai.google.dev/gemma) — the AI brain
- [Ollama](https://ollama.com) — local model serving
- [Flutter](https://flutter.dev) — beautiful cross-platform UI
- Every Indian child who deserves better access to education 💙
