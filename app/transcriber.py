import os
import sys
import time
import logging
import asyncio
import numpy as np
from typing import Optional, Dict, Tuple, List
from faster_whisper import WhisperModel

logger = logging.getLogger("transcriber")

SAMPLE_RATE = 16000

class Transcriber:
    def __init__(self, default_model: str = "base"):
        self.current_model_name = default_model
        self.models: Dict[str, WhisperModel] = {}
        self._load_model(default_model)

    def _load_model(self, model_name: str):
        """Load Faster-Whisper model using int8 quantization on CPU/Apple Silicon."""
        if model_name in self.models:
            self.current_model_name = model_name
            return

        logger.info(f"Loading Whisper model: {model_name}...")
        start = time.time()
        try:
            # Try offline local files first
            model = WhisperModel(
                model_name,
                device="cpu",
                compute_type="int8",
                local_files_only=True
            )
        except Exception:
            # Fallback to downloading if not cached locally
            model = WhisperModel(
                model_name,
                device="cpu",
                compute_type="int8",
                local_files_only=False
            )
        self.models[model_name] = model
        self.current_model_name = model_name
        logger.info(f"Loaded Whisper model '{model_name}' in {time.time() - start:.2f}s")

    def change_model(self, model_name: str):
        if model_name not in ["tiny", "base", "small", "medium"]:
            raise ValueError(f"Invalid model size: {model_name}")
        self._load_model(model_name)

    def transcribe_audio_chunk(
        self,
        audio_data: np.ndarray,
        language: Optional[str] = None,
        task: str = "transcribe"
    ) -> Tuple[str, str, float]:
        """
        Ultra-low latency inference with greedy search (beam_size=1) and VAD filtering.
        """
        if len(audio_data) < SAMPLE_RATE * 0.25:  # Too short (< 0.25s)
            return "", language or "", 0.0

        model = self.models.get(self.current_model_name)
        if not model:
            self._load_model(self.current_model_name)
            model = self.models[self.current_model_name]

        lang_param = None if (not language or language == "auto") else language

        segments, info = model.transcribe(
            audio_data,
            beam_size=1,
            temperature=0.0,
            language=lang_param,
            task=task,
            vad_filter=True,
            vad_parameters=dict(
                min_silence_duration_ms=300,
                speech_pad_ms=100
            ),
            without_timestamps=True,
            condition_on_previous_text=False
        )

        texts = []
        for segment in segments:
            text = segment.text.strip()
            if text:
                texts.append(text)

        full_text = " ".join(texts)
        detected_lang = info.language if info else (lang_param or "unknown")
        prob = info.language_probability if info else 1.0

        return full_text, detected_lang, prob


SENTENCE_TERMINATORS = ('.', '?', '!', '。', '？', '！')

class AudioStreamSession:
    """
    Two-Tier Audio Streaming Session:
    1. Tier 1 (Live Caption Buffer): Keeps ongoing speech accumulating in real-time,
       surviving small breathing pauses (< 1.6s).
    2. Tier 2 (Transcript Commitment): Only commits complete, polished sentences to
       the permanent transcript history upon long pause (>= 1.6s) or punctuation end + pause (>= 0.85s).
    """
    def __init__(self, transcriber: Transcriber, source_lang: str = "auto"):
        self.transcriber = transcriber
        self.source_lang = source_lang
        self.buffer = np.array([], dtype=np.float32)
        
        # Adaptive VAD state
        self.noise_floor = 0.008
        self.recent_energies = []
        self.last_speech_time = time.time()
        self.last_partial_time = 0.0
        self.is_speaking = False
        
        # Two-Tier Timing parameters
        self.sentence_silence_duration = 1.80  # 1.8s silence: speaker done -> finalize sentence
        self.punct_silence_duration = 1.05     # 1.05s silence after . ? ! -> finalize complete sentence
        self.max_utterance_duration = 12.0     # 12s max utterance cap before finalizing sentence
        
        # Segment tracking
        self.segment_counter = 1
        self.current_partial_text = ""
        self.last_emitted_text = ""

    def add_pcm_data(self, chunk: bytes, dtype=np.float32):
        """Append raw PCM chunk from WebSocket to buffer."""
        audio_np = np.frombuffer(chunk, dtype=dtype)
        if dtype == np.int16:
            audio_np = audio_np.astype(np.float32) / 32768.0

        self.buffer = np.append(self.buffer, audio_np)

    def compute_energy(self, samples: np.ndarray) -> float:
        if len(samples) == 0:
            return 0.0
        return float(np.sqrt(np.mean(samples ** 2)))

    async def process_buffer(self) -> Optional[Dict]:
        """
        Non-blocking audio buffer analysis.
        Emits continuous partials for active speech, and finalizes complete sentences.
        """
        now = time.time()
        total_samples = len(self.buffer)
        duration_sec = total_samples / SAMPLE_RATE

        if duration_sec < 0.25:
            return None

        # Adaptive noise floor calculation
        window_size = int(SAMPLE_RATE * 0.15)
        recent_samples = self.buffer[-window_size:] if total_samples >= window_size else self.buffer
        current_energy = self.compute_energy(recent_samples)

        self.recent_energies.append(current_energy)
        if len(self.recent_energies) > 20:  # ~2 seconds of history
            self.recent_energies.pop(0)

        # Dynamic speech threshold
        self.noise_floor = max(0.004, float(np.percentile(self.recent_energies, 20)))
        speech_threshold = max(0.012, self.noise_floor * 2.2)

        # Update speech activity
        if current_energy > speech_threshold:
            self.is_speaking = True
            self.last_speech_time = now

        silence_time = now - self.last_speech_time

        # Check conditions for committing a complete sentence into transcript history:
        # 1. Punctuation ending + moderate pause (>= 0.85s)
        stripped_text = self.current_partial_text.strip()
        ends_with_punct = any(stripped_text.endswith(p) for p in SENTENCE_TERMINATORS)
        is_punct_final = ends_with_punct and (silence_time >= self.punct_silence_duration) and (duration_sec >= 0.8)

        # 2. Long silence (>= 1.60s): Speaker finished thought/sentence
        is_long_silence_final = self.is_speaking and (silence_time >= self.sentence_silence_duration) and (duration_sec >= 0.8)

        # 3. Maximum paragraph duration reached (>= 11.0s) and brief breathing pause (>= 0.5s)
        is_max_cap_final = (duration_sec >= self.max_utterance_duration) and (silence_time >= 0.5)

        should_finalize = is_punct_final or is_long_silence_final or is_max_cap_final

        if should_finalize:
            audio_to_transcribe = self.buffer.copy()
            # Retain trailing 120ms for smooth audio boundary
            overlap_samples = int(SAMPLE_RATE * 0.12)
            self.buffer = self.buffer[-overlap_samples:] if len(self.buffer) > overlap_samples else np.array([], dtype=np.float32)
            self.is_speaking = False
            self.last_speech_time = now

            def _run():
                return self.transcriber.transcribe_audio_chunk(
                    audio_to_transcribe,
                    language=self.source_lang
                )

            text, lang, prob = await asyncio.to_thread(_run)
            text = text.strip()
            if text:
                seg_id = self.segment_counter
                self.segment_counter += 1
                self.current_partial_text = ""
                self.last_emitted_text = ""
                return {
                    "type": "final",
                    "segment_id": seg_id,
                    "text": text,
                    "language": lang,
                    "timestamp": now
                }
            return None

        # Real-time partial transcript while user is speaking (throttle every 250ms)
        # Keeps speech accumulating in the live caption window!
        if self.is_speaking and (now - self.last_partial_time >= 0.25) and duration_sec >= 0.35:
            self.last_partial_time = now
            audio_to_transcribe = self.buffer.copy()

            def _run_partial():
                return self.transcriber.transcribe_audio_chunk(
                    audio_to_transcribe,
                    language=self.source_lang
                )

            text, lang, prob = await asyncio.to_thread(_run_partial)
            text = text.strip()
            if text and text != self.last_emitted_text:
                self.last_emitted_text = text
                self.current_partial_text = text
                return {
                    "type": "partial",
                    "segment_id": self.segment_counter,
                    "text": text,
                    "language": lang,
                    "timestamp": now
                }

        # Trim buffer if silence persists and nobody is speaking
        if not self.is_speaking and duration_sec > 1.6:
            keep_samples = int(SAMPLE_RATE * 0.3)
            self.buffer = self.buffer[-keep_samples:]

        return None
