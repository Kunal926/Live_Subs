import math
from typing import List, Dict, Any

HARD_PUNCT = (".","!","?","…",":",";")
SOFT_PUNCT = (",",)

def _wtext(w: Dict[str,Any]) -> str:
    return (w.get("word") or "").strip()

def get_balanced_split_index(words: List[str], max_chars: int) -> int:
    if len(words) < 2: return len(words)
    best_cut = -1
    best_score = -float('inf')

    for i in range(len(words) - 1):
        l1 = " ".join(words[:i+1])
        l2 = " ".join(words[i+1:])
        len1, len2 = len(l1), len(l2)

        score = 0
        if len1 > max_chars: score -= 5000
        if len2 > max_chars: score -= 5000
        score -= abs(len1 - len2) * 5.0
        if words[i].endswith(HARD_PUNCT): score += 5
        elif words[i].endswith(SOFT_PUNCT): score += 3
        if len2 >= len1: score += 1

        if score > best_score:
            best_score, best_cut = score, i + 1

    return len(words) // 2 if best_cut == -1 else best_cut

def shape_block_text(words: List[Dict[str, Any]], max_chars: int = 42) -> str:
    toks = [_wtext(w) for w in words]
    if not toks: return ""
    if len(toks) >= 2:
        cut_idx = get_balanced_split_index(toks, max_chars)
        return f"{' '.join(toks[:cut_idx])}\n{' '.join(toks[cut_idx:])}".strip()
    return " ".join(toks)

def reshape_text_string(text: str, max_chars: int = 42) -> str:
    clean = text.replace('\n', ' ').strip()
    words = clean.split()
    if len(words) < 2: return clean
    cut_idx = get_balanced_split_index(words, max_chars)
    return f"{' '.join(words[:cut_idx])}\n{' '.join(words[cut_idx:])}".strip()

def apply_global_start_offset(events, offset_ms=50):
    offset_s = offset_ms / 1000.0
    for ev in events:
        ev["start"] += offset_s
        if ev["start"] >= ev["end"]:
            ev["end"] = ev["start"] + 0.1
    return events

def apply_extension_then_merge(events, target_cps=22.0, max_silence_s=1.0, max_chars_total=84, min_gap=0.084):
    if not events: return []
    i = 0
    while i < len(events):
        ev = events[i]
        txt_len = len(" ".join(_wtext(w) for w in ev["words"]))
        dur = ev["end"] - ev["start"]
        cps = txt_len / max(0.01, dur)
        if cps <= target_cps and dur >= 1.0:
            i += 1; continue
        next_ev = events[i+1] if i < len(events)-1 else None
        gap_next = (next_ev["start"] - ev["end"]) if next_ev else 999.0
        needed = txt_len / target_cps
        missing = max(0, needed - dur)
        if dur + missing < 1.0: missing = 1.0 - dur
        extended = False
        if missing > 0:
            rn = max(0, gap_next - min_gap)
            if rn > 0:
                take_next = min(missing, rn)
                ev["end"] += take_next
                if take_next >= missing or take_next > 0.3: extended = True
        if extended: i += 1; continue
        merged = False
        prev_ev = events[i-1] if i > 0 else None
        gap_prev = (ev["start"] - prev_ev["end"]) if prev_ev else 999.0
        gap_next = (next_ev["start"] - ev["end"]) if next_ev else 999.0
        min_g = min(gap_prev, gap_next)
        if min_g <= max_silence_s:
            side = 'prev' if gap_prev <= gap_next else 'next'
            if side == 'prev':
                new_w = prev_ev["words"] + ev["words"]
                if len(" ".join(_wtext(w) for w in new_w)) <= max_chars_total:
                    prev_ev["words"] = new_w; prev_ev["end"] = ev["end"]
                    events.pop(i); i -= 1; merged = True
            elif side == 'next':
                new_w = ev["words"] + next_ev["words"]
                if len(" ".join(_wtext(w) for w in new_w)) <= max_chars_total:
                    ev["words"] = new_w; ev["end"] = next_ev["end"]
                    events.pop(i+1); merged = True
        if not merged: i += 1
    return events

def apply_hybrid_linger_with_report(events: List[Dict[str, Any]], linger_ms: int = 600) -> List[Dict[str, Any]]:
    linger_s = linger_ms / 1000.0
    MIN_GAP = 0.084
    CHAIN_THRESHOLD = 0.500
    FORBIDDEN_MIDPOINT = (MIN_GAP + CHAIN_THRESHOLD) / 2.0
    for i in range(len(events)):
        ev = events[i]
        if i == len(events) - 1:
            ev["end"] += linger_s
        else:
            next_start = events[i+1]["start"]
            desired_end = ev["end"] + linger_s
            potential_gap = next_start - desired_end
            if potential_gap >= CHAIN_THRESHOLD:
                ev["end"] = desired_end
            elif potential_gap <= MIN_GAP:
                ev["end"] = next_start - MIN_GAP
            else:
                if potential_gap < FORBIDDEN_MIDPOINT:
                    ev["end"] = next_start - MIN_GAP
                else:
                    ev["end"] = next_start - CHAIN_THRESHOLD
            if ev["end"] <= ev["start"]:
                ev["end"] = ev["start"] + 0.1
    return events

def enforce_timing_constraints(events, min_dur=1.0, min_gap=0.084):
    for i in range(len(events)-1):
        if events[i+1]["start"] - events[i]["end"] < min_gap:
            events[i]["end"] = events[i+1]["start"] - min_gap
            if events[i]["end"] <= events[i]["start"]: events[i]["end"] = events[i]["start"] + 0.1
    return events

def _fmt_ms(t): return f"{int(t//3600):02}:{int((t%3600)//60):02}:{int(t%60):02},{int((t*1000)%1000):03}"

def write_srt(events, out_path):
    with open(out_path, "w", encoding="utf-8") as f:
        for i, ev in enumerate(events, 1):
            text = ev.get('text', '').strip()
            if not text and 'words' in ev:
                 text = shape_block_text(ev['words'])

            f.write(f"{i}\n{_fmt_ms(ev['start'])} --> {_fmt_ms(ev['end'])}\n{text}\n\n")

def run_post_processing(events):
    # Chain of post processing
    events = apply_global_start_offset(events, offset_ms=50)
    events = apply_extension_then_merge(events, target_cps=22.0)
    events = apply_hybrid_linger_with_report(events, linger_ms=600)
    # Shape text
    for ev in events: ev["text"] = shape_block_text(ev["words"], max_chars=42)
    events = enforce_timing_constraints(events, min_dur=1.0, min_gap=0.084)
    return events
