"""
ASR module for transcription using faster-whisper.

Provides smart segmentation based on pauses, character limits, and punctuation.
Uses faster-whisper with word-level timestamps for accurate subtitle generation.
"""
import torch
import logging
from typing import List, Dict, Any
from faster_whisper import WhisperModel

HARD_PUNCT = (".", "!", "?", "…", ":", ";")
SOFT_PUNCT = (",", )

def _wtext(w: Dict[str,Any]) -> str:
    return (w.get("word") or "").strip()

def find_best_split_point_in_buffer(words: List[Dict[str,Any]]) -> int:
    if len(words) < 2: return 1
    full_text = " ".join(_wtext(w) for w in words)
    target_len = len(full_text) / 2
    best_idx = -1
    best_score = -float('inf')
    current_len = 0
    for i in range(len(words) - 1):
        w = words[i]
        nxt = words[i+1]
        score = 0.0
        current_len += len(_wtext(w)) + 1
        dist = abs(current_len - target_len)
        score -= dist * 1.5
        gap = (nxt["start"] - w["end"])
        if gap > 0: score += gap * 200.0
        txt = _wtext(w)
        if txt.endswith(HARD_PUNCT): score += 50.0
        elif txt.endswith(SOFT_PUNCT): score += 25.0
        if score > best_score:
            best_score, best_idx = score, i + 1
    return best_idx if best_idx != -1 else len(words) // 2

def segment_smart_stream(words, pause_ms=400, max_chars=84, max_dur_s=7.0):
    out = []
    buf = []
    buf_start = 0.0
    def create_event(word_list):
        if not word_list: return None
        return {"start": float(word_list[0]["start"]), "end": float(word_list[-1]["end"]), "words": word_list, "text": ""}
    for i, w in enumerate(words):
        if not buf: buf_start = w["start"]
        buf.append(w)
        nxt = words[i+1] if i+1 < len(words) else None
        gap = (nxt["start"] - w["end"])*1000.0 if nxt else 0.0
        if gap >= pause_ms:
            out.append(create_event(buf))
            buf = []
            continue
        current_text = " ".join(_wtext(x) for x in buf)
        current_dur = w["end"] - buf_start
        if len(current_text) > max_chars or current_dur > max_dur_s:
            split_idx = find_best_split_point_in_buffer(buf)
            out.append(create_event(buf[:split_idx]))
            buf = buf[split_idx:]
            if buf: buf_start = buf[0]["start"]
    if buf: out.append(create_event(buf))
    return [e for e in out if e]

def transcribe_audio(audio_path, model_id="large-v3-turbo"):
    logging.info(f"Transcribing {audio_path} with {model_id}...")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    compute_type = "float16" if torch.cuda.is_available() else "int8"

    model = WhisperModel(model_id, device=device, compute_type=compute_type)
    segments, info = model.transcribe(
        audio_path, language="en", word_timestamps=True,
        condition_on_previous_text=False, vad_filter=False
    )

    all_words = []
    for s in segments:
        for w in s.words:
            t = w.word.strip()
            if t: all_words.append({"word": t, "start": w.start, "end": w.end})

    events = segment_smart_stream(all_words, pause_ms=400, max_chars=84, max_dur_s=7.0)
    return events
