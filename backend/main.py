import html
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import ollama
import base64

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

from typing import List, Optional

class ChatMessage(BaseModel):
    role: str
    content: str

class QuestionRequest(BaseModel):
    question: str
    language: str
    subject: str
    grade: int
    difficulty: str = "medium"
    history: Optional[List[ChatMessage]] = []

CULTURAL_CONTEXTS = {
    "marathi": {
        "math": "Use examples from Maharashtra like shetkari (farmer), bazar, poli making, sugarcane farming",
        "science": "Use examples from Western Ghats, monsoon, local plants like tulsi, neem, mango",
        "history": "Reference Chhatrapati Shivaji Maharaj, Maratha empire, local forts",
    },
    "hindi": {
        "math": "Use examples from local bazaar, chai shop, cricket scoring",
        "science": "Use examples from Ganga river, local crops like wheat and rice",
        "history": "Reference freedom struggle, local heroes",
    },
    "tamil": {
        "math": "Use examples from local market, rice farming, temple architecture",
        "science": "Use examples from coastal fishing, monsoon, local plants",
        "history": "Reference Chola empire, local traditions",
    },
    "telugu": {
        "math": "Use examples from local farming, market trading",
        "science": "Use examples from Krishna river, local crops",
        "history": "Reference local kingdoms and traditions",
    },
}

def sanitize(text: str) -> str:
    return html.escape(str(text).strip())[:1000]

def build_prompt(question, language, subject, grade, is_image=False):
    cultural_context = CULTURAL_CONTEXTS.get(language.lower(), {}).get(subject.lower(), "Use locally relevant examples")
    image_instruction = "Look at this image carefully and explain what you see in it." if is_image else ""

    grade_approach = {
        1: "Use very simple one-line sentences. Use toys, animals, and home examples. No complex words.",
        2: "Use simple sentences. Use stories with familiar characters like farmers, shopkeepers.",
        3: "Use short paragraphs. Relate to school, family, and village life.",
        4: "Use 2-3 paragraphs. Include simple real-world problems like buying vegetables or measuring fields.",
        5: "Explain with cause and effect. Use examples from local news, sports, and nature.",
        6: "Use logical reasoning. Connect concepts to real-life situations like cooking, travel, construction.",
        7: "Introduce abstract thinking with concrete anchors. Use examples from local industry, farming, rivers.",
        8: "Use analytical explanation. Connect to real-world applications like engineering, medicine, history.",
    }.get(grade, "Use age-appropriate examples relevant to their daily life.")

    return f"""You are a friendly school teacher for grade {grade}. Respond ONLY in {language}. Only answer school subjects (math, science, history, geography, english). If off-topic, say: "I can only help with school subjects."

{grade_approach}
Cultural context: {cultural_context}
{image_instruction}

Explain clearly and completely. Use a real-life example. End with one fun question. Use emojis. Max 10 lines. ALWAYS finish your answer completely — never stop mid-sentence.

Question: {question}"""

@app.post("/ask")
async def ask_tutor(request: QuestionRequest):
    import traceback
    cultural_context = CULTURAL_CONTEXTS.get(request.language.lower(), {}).get(request.subject.lower(), "Use locally relevant examples")
    grade_approach = {
        1: "Use very simple one-line sentences. Use toys, animals, and home examples. No complex words.",
        2: "Use simple sentences. Use stories with familiar characters like farmers, shopkeepers.",
        3: "Use short paragraphs. Relate to school, family, and village life.",
        4: "Use 2-3 paragraphs. Include simple real-world problems like buying vegetables or measuring fields.",
        5: "Explain with cause and effect. Use examples from local news, sports, and nature.",
        6: "Use logical reasoning. Connect concepts to real-life situations like cooking, travel, construction.",
        7: "Introduce abstract thinking with concrete anchors. Use examples from local industry, farming, rivers.",
        8: "Use analytical explanation. Connect to real-world applications like engineering, medicine, history.",
    }.get(request.grade, "Use age-appropriate examples relevant to their daily life.")

    # Build conversation history as plain text injected into the prompt
    history_text = ""
    if request.history:
        parts = ["\n\nConversation so far:\n"]
        for msg in request.history:
            role_label = "Tutor" if msg.role == "assistant" else "Student"
            parts.append(f"{role_label}: {sanitize(msg.content)}\n")
        parts.append("\n")
        history_text = "".join(parts)

    prompt = f"""You are a friendly school tutor for grade {request.grade} students. Respond ONLY in {request.language}. Only help with school subjects (math, science, history, geography, english).

{grade_approach}
Cultural context: {cultural_context}
{history_text}
IMPORTANT: Read the conversation above carefully. The student may be replying to a question you (the Tutor) asked. If so, acknowledge their answer, say if it is correct or not, explain briefly, then continue teaching. Do NOT ignore the conversation history.

Student's latest message: {sanitize(request.question)}

Tutor:"""

    try:
        response = ollama.chat(
            model="gemma4:e4b",
            messages=[{"role": "user", "content": prompt}],
            options={"num_predict": 1200}
        )
        return {"answer": response.message.content, "language": request.language, "subject": request.subject}
    except Exception as e:
        traceback.print_exc()
        from fastapi import HTTPException
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/ask-image")
async def ask_with_image(
    image: UploadFile = File(...),
    language: str = Form(...),
    subject: str = Form(...),
    grade: int = Form(...),
    question: str = Form(default="Explain this image")
):
    image_bytes = await image.read()
    image_base64 = base64.b64encode(image_bytes).decode("utf-8")
    prompt = build_prompt(sanitize(question), sanitize(language), sanitize(subject), grade, is_image=True)
    response = ollama.chat(
        model="gemma4:e4b",
        messages=[{"role": "user", "content": prompt, "images": [image_base64]}],
        options={"num_predict": 800}
    )
    return {"answer": response.message.content, "language": language, "subject": subject}

@app.post("/quiz")
async def generate_quiz(request: QuestionRequest):
    difficulty_instruction = {
        "easy": "Use very simple, straightforward questions. Single concept per question. Suitable for beginners.",
        "medium": "Use moderate questions that require some thinking. Mix of recall and application.",
        "hard": "Use challenging questions that require deep understanding and application of concepts."
    }.get(request.difficulty, "Use moderate questions.")

    topic = sanitize(request.question)[:300] if request.question.strip() else sanitize(request.subject)

    prompt = f"""You are a teacher creating a quiz for a grade {request.grade} student.

The student just learned about this specific topic: "{topic}"
Subject: {sanitize(request.subject)}
Difficulty: {request.difficulty.upper()} - {difficulty_instruction}

IMPORTANT: All 3 questions MUST be directly about "{topic}". Do NOT ask about unrelated topics.

Generate exactly 3 multiple choice questions in {sanitize(request.language)} language.

Format EXACTLY like this:
Q1: [question]
A) [option]
B) [option]
C) [option]
D) [option]
Answer: [correct letter]

Q2: [question]
A) [option]
B) [option]
C) [option]
D) [option]
Answer: [correct letter]

Q3: [question]
A) [option]
B) [option]
C) [option]
D) [option]
Answer: [correct letter]

Use cultural examples from {sanitize(request.language)} speaking regions."""

    response = ollama.chat(
        model="gemma4:e4b",
        messages=[{"role": "user", "content": prompt}],
        options={"num_predict": 700}
    )
    return {"quiz": response.message.content, "language": request.language}

@app.post("/lesson-of-day")
async def lesson_of_day(request: QuestionRequest):
    prompt = f"""You are a fun teacher for a grade {request.grade} student.

Generate a short 'Lesson of the Day' for the subject: {sanitize(request.subject)} in {sanitize(request.language)} language.

Rules:
- Pick an interesting topic from {sanitize(request.subject)} suitable for grade {request.grade}
- Explain it in 3-4 fun short sentences max
- Use a real life example from {sanitize(request.language)} speaking region
- Use 1-2 emojis to make it fun
- End with one curious question to make the child think
- NEVER exceed 6 lines"""

    response = ollama.chat(
        model="gemma4:e4b",
        messages=[{"role": "user", "content": prompt}],
        options={"num_predict": 200}
    )
    return {"lesson": response.message.content, "subject": request.subject}

@app.post("/flashcards")
async def generate_flashcards(request: QuestionRequest):
    prompt = f"""Generate exactly 5 flashcards for a grade {request.grade} student on subject: {sanitize(request.subject)} in {sanitize(request.language)} language.

Format EXACTLY like this (no extra text):
FRONT: [term or question]
BACK: [answer, 1 line only]

FRONT: [term or question]
BACK: [answer, 1 line only]

FRONT: [term or question]
BACK: [answer, 1 line only]

FRONT: [term or question]
BACK: [answer, 1 line only]

FRONT: [term or question]
BACK: [answer, 1 line only]"""

    response = ollama.chat(
        model="gemma4:e4b",
        messages=[{"role": "user", "content": prompt}],
        options={"num_predict": 350}
    )
    return {"flashcards": response.message.content}

@app.post("/hint")
async def get_hint(request: QuestionRequest):
    prompt = f"""A grade {request.grade} student is stuck on this quiz question: {sanitize(request.question)}

Give a very short hint (1 sentence only) in {sanitize(request.language)} language.
Do NOT give the answer. Just nudge them in the right direction.
Use simple words a child understands."""

    response = ollama.chat(
        model="gemma4:e4b",
        messages=[{"role": "user", "content": prompt}],
        options={"num_predict": 60}
    )
    return {"hint": response.message.content}

@app.post("/explain")
async def explain_answer(request: QuestionRequest):
    prompt = f"""A grade {request.grade} student answered a quiz question wrong.

Question/Topic: {sanitize(request.question)}

Give a very short and simple explanation (2-3 lines max) in {sanitize(request.language)} language to help them understand the correct answer.
Use simple words a child can understand. Be encouraging, not discouraging."""

    response = ollama.chat(
        model="gemma4:e4b",
        messages=[{"role": "user", "content": prompt}],
        options={"num_predict": 128}
    )
    return {"explanation": response.message.content}

@app.get("/health")
async def health():
    return {"status": "NativeMinds AI is running!", "model": "gemma4:e4b"}
