import logging
import asyncio
from typing import Optional
import urllib.request
import urllib.parse
import json
import time

logger = logging.getLogger("translator")

try:
    import opencc
    _cc_s2t = opencc.OpenCC('s2twp')  # Taiwan Traditional Chinese with idioms
except Exception as e:
    logger.warning(f"OpenCC initialization failed: {e}")
    _cc_s2t = None

try:
    from deep_translator import MyMemoryTranslator
    _has_mymemory = True
except ImportError:
    _has_mymemory = False


class TranslatorService:
    def __init__(self):
        self._cache = {}
        self.ollama_available = False
        self.ollama_model = "qwen2.5:0.5b"
        self._last_ollama_check = 0.0

    def to_traditional_chinese(self, text: str) -> str:
        """Convert simplified Chinese or phrases to Taiwan Traditional Chinese."""
        if _cc_s2t and text:
            try:
                return _cc_s2t.convert(text)
            except Exception as e:
                logger.warning(f"OpenCC conversion error: {e}")
        return text

    async def _check_ollama(self) -> bool:
        """Check if local Ollama server is active (cached for 30s)."""
        now = time.time()
        if now - self._last_ollama_check < 30.0:
            return self.ollama_available

        self._last_ollama_check = now
        def _check():
            try:
                req = urllib.request.Request("http://127.0.0.1:11434/api/tags", method="GET")
                with urllib.request.urlopen(req, timeout=0.3) as resp:
                    if resp.status == 200:
                        data = json.loads(resp.read().decode())
                        models = [m.get("name", "") for m in data.get("models", [])]
                        if models:
                            self.ollama_model = models[0]
                            return True
            except Exception:
                pass
            return False

        self.ollama_available = await asyncio.to_thread(_check)
        return self.ollama_available

    async def _translate_with_ollama(self, text: str, target_lang: str) -> Optional[str]:
        if not self.ollama_available:
            return None

        target_name = "Traditional Chinese (繁體中文)" if "zh" in target_lang.lower() else target_lang
        prompt = f"Translate the following into {target_name}. Output ONLY the translated text:\n{text}"
        payload = json.dumps({
            "model": self.ollama_model,
            "prompt": prompt,
            "stream": False
        }).encode("utf-8")

        def _call_ollama():
            try:
                req = urllib.request.Request(
                    "http://127.0.0.1:11434/api/generate",
                    data=payload,
                    headers={"Content-Type": "application/json"},
                    method="POST"
                )
                with urllib.request.urlopen(req, timeout=1.5) as resp:
                    if resp.status == 200:
                        res = json.loads(resp.read().decode())
                        return res.get("response", "").strip()
            except Exception:
                pass
            return None

        return await asyncio.to_thread(_call_ollama)

    def _translate_google_direct(self, text: str, src: str, tgt: str) -> Optional[str]:
        """
        Direct high-speed Google translation via Chrome extension / mobile clients
        which avoid 429 rate-limiting.
        """
        sl = "auto" if src == "auto" else src
        tl = "zh-TW" if "zh" in tgt.lower() else tgt

        for client in ["dict-chrome-ex", "at"]:
            try:
                url = f"https://translate.googleapis.com/translate_a/single?client={client}&sl={sl}&tl={tl}&dt=t&q=" + urllib.parse.quote(text)
                req = urllib.request.Request(
                    url,
                    headers={
                        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
                    }
                )
                with urllib.request.urlopen(req, timeout=3.0) as resp:
                    if resp.status == 200:
                        data = json.loads(resp.read().decode())
                        translated = "".join([item[0] for item in data[0] if item and item[0]])
                        if translated and translated.strip():
                            return translated.strip()
            except Exception as e:
                logger.debug(f"Google translate client '{client}' error: {e}")
                continue
        return None

    def _translate_mymemory_fallback(self, text: str, src: str, tgt: str) -> Optional[str]:
        """MyMemory backup translation provider."""
        if not _has_mymemory:
            return None
        try:
            def _get_mm_code(code: str, is_target: bool) -> str:
                c = code.lower().split("-")[0]
                if "zh" in c:
                    return "zh-TW"
                mapping = {
                    "en": "en-US", "ja": "ja-JP", "ko": "ko-KR",
                    "fr": "fr-FR", "de": "de-DE", "es": "es-ES"
                }
                return mapping.get(c, "en-US" if not is_target else "zh-TW")

            mm_src = _get_mm_code(src, is_target=False)
            mm_tgt = _get_mm_code(tgt, is_target=True)
            return MyMemoryTranslator(source=mm_src, target=mm_tgt).translate(text)
        except Exception as e:
            logger.debug(f"MyMemory error: {e}")
            return None

    async def translate(
        self,
        text: str,
        source_lang: str = "auto",
        target_lang: str = "zh-TW"
    ) -> str:
        """
        Translates text from source_lang to target_lang.
        Guarantees Chinese output when target is Traditional Chinese.
        """
        text = text.strip()
        if not text:
            return ""

        cache_key = (text, source_lang, target_lang)
        if cache_key in self._cache:
            return self._cache[cache_key]

        src = source_lang.lower().split("-")[0] if source_lang != "auto" else "auto"
        tgt = target_lang.lower()
        is_target_zh = tgt in ["zh", "zh-tw", "zh-hk", "zh-cn", "chinese"]

        # If source and target are both Chinese
        if src == "zh" and is_target_zh:
            res = self.to_traditional_chinese(text) if tgt in ["zh-tw", "zh-hk"] else text
            self._cache[cache_key] = res
            return res

        async def _do_translate() -> Optional[str]:
            # 1. Try local Ollama if available
            if self.ollama_available:
                ollama_res = await self._translate_with_ollama(text, target_lang)
                if ollama_res:
                    return self.to_traditional_chinese(ollama_res) if is_target_zh else ollama_res

            # 2. Try Direct Google Translation (Chrome/Mobile API)
            google_res = await asyncio.to_thread(self._translate_google_direct, text, src, tgt)
            if google_res:
                return self.to_traditional_chinese(google_res) if is_target_zh else google_res

            # 3. Try MyMemory Fallback
            mm_res = await asyncio.to_thread(self._translate_mymemory_fallback, text, src, tgt)
            if mm_res:
                return self.to_traditional_chinese(mm_res) if is_target_zh else mm_res

            return None

        try:
            # 4.0s timeout for network background execution
            result = await asyncio.wait_for(_do_translate(), timeout=4.0)
            if result and result.strip():
                if is_target_zh:
                    result = self.to_traditional_chinese(result)
                self._cache[cache_key] = result
                return result
        except asyncio.TimeoutError:
            logger.warning(f"Translation timed out for: '{text[:25]}...'")
        except Exception as e:
            logger.warning(f"Translation failed: {e}")

        # If all translation providers failed and target is Chinese, return a clear placeholder
        # instead of silently returning English text!
        if is_target_zh and src != "zh":
            return "(翻譯處理中...)"
        return text
