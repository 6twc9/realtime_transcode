import os
import json
import logging
import asyncio
import numpy as np
import time
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

from app.transcriber import Transcriber, AudioStreamSession
from app.translator import TranslatorService

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("server")

app = FastAPI(title="Real-Time Meeting Speech Translator")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "static")

# Initialize models
transcriber = Transcriber(default_model="base")
translator = TranslatorService()

# Serve static assets
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/")
async def get_index():
    return FileResponse(os.path.join(STATIC_DIR, "index.html"))


@app.get("/api/status")
async def get_status():
    ollama_ok = await translator._check_ollama()
    return {
        "current_model": transcriber.current_model_name,
        "available_models": ["tiny", "base", "small", "medium"],
        "ollama_connected": ollama_ok,
        "ollama_model": translator.ollama_model if ollama_ok else None,
        "languages": [
            {"code": "auto", "name": "自動偵測 (Auto Detect)"},
            {"code": "en", "name": "英語 (English)"},
            {"code": "zh", "name": "中文 (Chinese)"},
            {"code": "ja", "name": "日語 (Japanese)"},
            {"code": "ko", "name": "韓語 (Korean)"},
            {"code": "fr", "name": "法語 (French)"},
            {"code": "de", "name": "德語 (German)"},
            {"code": "es", "name": "西班牙語 (Spanish)"}
        ],
        "target_languages": [
            {"code": "zh-TW", "name": "繁體中文 (Traditional Chinese)"},
            {"code": "zh-CN", "name": "簡體中文 (Simplified Chinese)"},
            {"code": "en", "name": "英語 (English)"},
            {"code": "ja", "name": "日語 (Japanese)"},
            {"code": "ko", "name": "韓語 (Korean)"}
        ]
    }


class ModelSwitchRequest(BaseModel):
    model: str


@app.post("/api/model")
async def switch_model(req: ModelSwitchRequest):
    try:
        def _switch():
            transcriber.change_model(req.model)
        await asyncio.to_thread(_switch)
        return {"status": "ok", "current_model": transcriber.current_model_name}
    except Exception as e:
        logger.error(f"Failed to change model: {e}")
        return JSONResponse(status_code=400, content={"error": str(e)})


@app.websocket("/ws/live")
async def websocket_live_endpoint(websocket: WebSocket):
    await websocket.accept()
    logger.info("Client connected to real-time audio WebSocket.")

    source_lang = "auto"
    target_lang = "zh-TW"
    session = AudioStreamSession(transcriber=transcriber, source_lang=source_lang)
    stop_event = asyncio.Event()

    # Debounce tracking for partial translations
    last_partial_trans_time = 0.0
    pending_translation_tasks = set()

    async def translate_and_send(seg_id: int, text: str, s_lang: str, t_lang: str, status: str):
        """Asynchronous background translation worker task."""
        try:
            trans_text = await translator.translate(text, source_lang=s_lang, target_lang=t_lang)
            if websocket.client_state.name == "CONNECTED":
                await websocket.send_json({
                    "type": "translation_update",
                    "segment_id": seg_id,
                    "status": status,
                    "translated_text": trans_text
                })
        except Exception as ex:
            logger.debug(f"Translation push error for segment {seg_id}: {ex}")

    async def audio_processor_loop():
        """Ultra-fast decoupled loop emitting transcripts immediately."""
        nonlocal last_partial_trans_time

        while not stop_event.is_set():
            try:
                res = await session.process_buffer()
                if res and websocket.client_state.name == "CONNECTED":
                    original_text = res["text"]
                    seg_id = res["segment_id"]
                    status = res["type"]
                    detected_lang = res.get("language", source_lang)
                    timestamp = res["timestamp"]

                    # 1. PUSH ORIGINAL TRANSCRIPT IMMEDIATELY TO CLIENT (Zero blocking!)
                    await websocket.send_json({
                        "type": "transcript",
                        "segment_id": seg_id,
                        "status": status,
                        "source_lang": detected_lang,
                        "target_lang": target_lang,
                        "original_text": original_text,
                        "timestamp": timestamp
                    })

                    # 2. DISPATCH BACKGROUND ASYNC TRANSLATION
                    now = time.time()
                    if status == "final":
                        # Final sentences are always translated with high priority
                        t_task = asyncio.create_task(
                            translate_and_send(seg_id, original_text, detected_lang, target_lang, "final")
                        )
                        pending_translation_tasks.add(t_task)
                        t_task.add_done_callback(pending_translation_tasks.discard)
                    elif status == "partial":
                        # Partial sentences are translated with 400ms debounce
                        if now - last_partial_trans_time >= 0.40 and len(original_text.split()) >= 2:
                            last_partial_trans_time = now
                            t_task = asyncio.create_task(
                                translate_and_send(seg_id, original_text, detected_lang, target_lang, "partial")
                            )
                            pending_translation_tasks.add(t_task)
                            t_task.add_done_callback(pending_translation_tasks.discard)

            except Exception as e:
                logger.error(f"Error in audio processing loop: {e}")

            # 40ms loop tick rate for high responsiveness
            await asyncio.sleep(0.04)

    process_task = asyncio.create_task(audio_processor_loop())

    try:
        while True:
            message = await websocket.receive()
            if "bytes" in message and message["bytes"]:
                # Binary audio chunk (Float32 PCM, 16kHz mono)
                session.add_pcm_data(message["bytes"])
            elif "text" in message and message["text"]:
                try:
                    data = json.loads(message["text"])
                    if data.get("type") == "config":
                        source_lang = data.get("source_lang", source_lang)
                        target_lang = data.get("target_lang", target_lang)
                        session.source_lang = source_lang
                        logger.info(f"Updated config: src={source_lang}, tgt={target_lang}")
                    elif data.get("type") == "reset":
                        session.buffer = np.array([], dtype=np.float32)
                except Exception as ex:
                    logger.warning(f"Control message parse error: {ex}")
    except WebSocketDisconnect:
        logger.info("Client disconnected from WebSocket.")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    finally:
        stop_event.set()
        process_task.cancel()
        for task in pending_translation_tasks:
            task.cancel()
