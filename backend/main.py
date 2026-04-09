from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import ollama

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class QuestionRequest(BaseModel):
    question: str
    language: str
    subject: str
    grade: int

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

@app.post("/ask")
async def ask_tutor(request: QuestionRequest):
    language = request.language.lower()
    subject = request.subject.lower()
    
    cultural_context = CULTURAL_CONTEXTS.get(language, {}).get(subject, "Use locally relevant examples")
    
    prompt = f"""You are a friendly and warm teacher teaching a grade {request.grade} student.

IMPORTANT RULES:
1. Respond ONLY in {request.language} language
2. Use simple words a child can understand
3. {cultural_context}
4. Explain like a caring elder from their village
5. Use examples from their daily life
6. Keep explanation short and clear
7. End with one simple question to check understanding
8. If the question looks like scanned text with numbers and symbols, understand it as a math or science problem and explain it

Student's question: {request.question}"""

    response = ollama.chat(
        model="gemma4:e4b",
        messages=[{"role": "user", "content": prompt}]
    )
    
    return {
        "answer": response["message"]["content"],
        "language": request.language,
        "subject": request.subject
    }

@app.get("/health")
async def health():
    return {"status": "NativeMinds AI is running!"}
