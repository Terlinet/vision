import asyncio
import base64
import json
import os
import re
import io
import logging
from typing import Optional, List

import edge_tts
import httpx
import uvicorn
import numpy as np
import cv2
from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI
from pydantic import BaseModel
from ultralytics import YOLO
from transformers import BlipProcessor, BlipForConditionalGeneration
from PIL import Image

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- CONFIGURAÇÕES DE IA (GROQ) ---
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "GROQ_API_KEY")
MODEL_NAME = "llama-3.3-70b-versatile"

client_groq = OpenAI(
    base_url="https://api.groq.com/openai/v1",
    api_key=GROQ_API_KEY,
)

# --- CARREGAMENTO DE MODELOS ---
logging.basicConfig(level=logging.INFO)
try:
    yolo_model = YOLO('yolov8n.pt')
    blip_processor = BlipProcessor.from_pretrained("Salesforce/blip-image-captioning-base")
    blip_model = BlipForConditionalGeneration.from_pretrained("Salesforce/blip-image-captioning-base")
    logging.info("Sistemas Neurais de Visão carregados com sucesso!")
except Exception as e:
    logging.error(f"Erro ao carregar modelos: {e}")

# MEMÓRIA DE CURTO PRAZO
memory = {"last_detections": [], "last_caption": ""}

async def generate_voice_base64(text: str):
    try:
        if not text.strip(): return None
        clean_text = re.sub(r'[^a-zA-Z0-9\s,.?!:;$%áàâãéèêíïóôõöúçÁÀÂÃÉÈÊÍÏÓÔÕÖÚÇ\-]', '', text)
        # Voz masculina Antonio para o Bee
        communicate = edge_tts.Communicate(clean_text, "pt-BR-AntonioNeural")
        audio_data = b""
        async for chunk in communicate.stream():
            if chunk["type"] == "audio": audio_data += chunk["data"]
        return base64.b64encode(audio_data).decode('utf-8')
    except Exception as e:
        logging.error(f"Erro no TTS: {e}")
        return None

# --- ROTA DE VISÃO INTERATIVA (O CÉREBRO DO TERLINET VISION) ---
@app.post('/predict')
async def predict(
    image: UploadFile = File(...),
    user_query: Optional[str] = Form(None)
):
    try:
        raw_bytes = await image.read()

        # 1. BLIP - Entendimento Visual Narrativo
        img_pil = Image.open(io.BytesIO(raw_bytes)).convert('RGB')
        inputs = blip_processor(img_pil, return_tensors="pt")
        out = blip_model.generate(**inputs)
        desc_en = blip_processor.decode(out[0], skip_special_tokens=True)

        # 2. YOLO - Identificação Técnica de Objetos
        npimg = np.frombuffer(raw_bytes, np.uint8)
        img_cv2 = cv2.imdecode(npimg, cv2.IMREAD_COLOR)
        results = yolo_model(img_cv2)
        detections = list(set([yolo_model.names[int(box.cls)] for r in results for box in r.boxes]))

        # Atualiza Memória Contextual
        memory["last_detections"] = detections
        memory["last_caption"] = desc_en

        # 3. Lógica de Interação Groq (Decide se responde pergunta ou narra tudo)
        # Se não houver query, o Bee narra o ambiente por padrão.
        instruction = user_query if user_query and user_query.strip() else "Descreva o ambiente de forma fluida."

        prompt = f"""
        Você é o Bee, o assistente inteligente de visão da TerlineT.
        CONTEXTO VISUAL:
        - Objetos detectados (YOLO): {', '.join(detections) if detections else 'Nenhum objeto óbvio'}
        - Descrição base (BLIP): {desc_en}
        PERGUNTA/COMANDO DO USUÁRIO: "{instruction}"
        SUA MISSÃO:
        1. Se o usuário perguntou sobre algo específico, responda com precisão baseado nos dados visuais.
        2. Se ele pediu para descrever tudo, faça uma narração elegante em português.
        3. Após responder uma pergunta pontual, você PODE sugerir: "Deseja que eu descreva o resto do ambiente?".
        REGRAS:
        - Idioma: Português do Brasil.
        - Tom: Profissional, tecnológico e empático.
        - Curto: Máximo 3 frases.
        """

        loop = asyncio.get_event_loop()
        completion = await loop.run_in_executor(None, lambda: client_groq.chat.completions.create(
            model=MODEL_NAME,
            messages=[{"role": "system", "content": "Você é o assistente Bee. Você traduz dados visuais em inteligência narrativa."},
                      {"role": "user", "content": prompt}],
            max_tokens=250
        ))

        narration = completion.choices[0].message.content.strip()
        audio_base64 = await generate_voice_base64(narration)

        return {
            "description": narration,
            "audio": audio_base64,
            "detections": [{"label": yolo_model.names[int(box.cls)], "conf": float(box.conf)} for r in results for box in r.boxes]
        }
    except Exception as e:
        logging.error(f"Erro no Sistema Neural: {e}")
        return {"description": "Sinal neural interrompido. Reiniciando protocolos.", "audio": None, "detections": []}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=7860)