import os
import logging
from google import genai
from google.genai import types
from src.postprocess import reshape_text_string

MODEL_ID = os.environ.get("GEMINI_MODEL_ID", "gemini-2.0-flash")

def correct_text_only_with_gemini(audio_path, events):
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        logging.warning("GEMINI_API_KEY not set. Skipping Gemini correction.")
        return events

    logging.info("Uploading to Gemini...")
    client = genai.Client(api_key=api_key)

    # Upload file
    try:
        file_ref = client.files.upload(file=audio_path)
    except Exception as e:
        logging.error(f"Failed to upload audio to Gemini: {e}")
        return events

    payload_lines = []
    for i, ev in enumerate(events, 1):
        clean_text = ev.get('text', '').replace('\n', ' ')
        payload_lines.append(f"{i}|{clean_text}")
    full_payload = "\n".join(payload_lines)

    logging.info("Requesting Text Corrections (Safe Mode - Anime)...")

    prompt = """
    You are a professional subtitle editor.
    I will provide a list of subtitle lines in the format 'ID|Text'.
    The audio file is provided for context.

    TASK:
    1. Listen to the audio to identify correct Name spellings (Context: Anime).
       * Pay attention to Character Names, Locations, and specific Terminology.
       * Maintain standard romanization for Japanese (Anime) names (e.g. 'Satou', 'Kyouma').
    2. Fix phonetic typos and capitalization.
    3. STRICTLY follow the STYLE GUIDE below.

    STYLE GUIDE:
    - Ellipses: Use the single char (…, U+2026). Do NOT use three dots.
      * Use to indicate trailing off or pauses >2s.
      * NO space after ellipsis at start of line (e.g., "…and then").
    - Numbers & Decades:
      * Decades: "1950s" or "'50s".
      * Ages: Always use numerals (e.g., "He is 5").
      * Times: "9:30 a.m.", "a.m./p.m." (lowercase). Spell out "noon", "midnight", "half past", "quarter of".
      * "o'clock": Spell out the number (e.g., "eleven o'clock").
    - Punctuation:
      * Exclamation marks (!): Use ONLY for shouting/surprise. Avoid overuse.
      * Interrobangs (?!): Allowed for emphatic disbelief (e.g., "What did you say?!").
      * Ampersands (&): Only in initialisms (e.g., "R&B").
      * Hashtags (#): Allowed if mentioned (e.g., "#winning"). Spell out "hashtag" if used as a verb.

    OUTPUT FORMAT:
    - Output ONLY the corrected list in 'ID|Corrected Text' format.
    - Do NOT include timestamps.
    - Do NOT merge or split lines. Keep line count identical.

    INPUT DATA:
    """

    config = types.GenerateContentConfig(
        automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True)
    )

    try:
        response = client.models.generate_content(
            model=MODEL_ID,
            config=config,
            contents=[prompt, file_ref, full_payload]
        )

        corrected_map = {}
        if response.text:
            raw_response = response.text.strip()
            for line in raw_response.split('\n'):
                if "|" in line:
                    parts = line.split("|", 1)
                    if len(parts) == 2 and parts[0].strip().isdigit():
                        idx = int(parts[0].strip())
                        new_text = parts[1].strip()
                        corrected_map[idx] = new_text

        logging.info(f"Received {len(corrected_map)} corrected lines.")

        update_count = 0
        for i, ev in enumerate(events, 1):
            if i in corrected_map:
                old_text = ev.get('text', '').replace('\n', ' ')
                new_text = corrected_map[i]
                if new_text and old_text != new_text:
                    ev['text'] = reshape_text_string(new_text, max_chars=42)
                    update_count += 1

        logging.info(f"Updated {update_count} lines with Gemini corrections.")

    except Exception as e:
        logging.error(f"Gemini API Error: {e}")

    return events
