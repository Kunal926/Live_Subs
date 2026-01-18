"""
Audio processing module for media file handling.

Provides functions for probing, extracting, and preprocessing audio
using ffmpeg and ffprobe.
"""
import subprocess
import json
import logging

def probe_file(filepath):
    """
    Probes the media file using ffprobe and returns the JSON output.
    """
    cmd = [
        "ffprobe",
        "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        filepath
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        logging.error(f"Error probing file {filepath}: {e}")
        raise

def select_best_audio_stream(probe_data):
    """
    Selects the best English audio stream.
    Heuristics:
    1. Look for streams with language 'eng'.
    2. If multiple, prefer the one with more channels (e.g. 5.1 > stereo).
    3. If no 'eng', pick the first audio stream (default).
    Returns the stream index (integer).
    """
    streams = probe_data.get("streams", [])
    audio_streams = [s for s in streams if s["codec_type"] == "audio"]

    if not audio_streams:
        raise ValueError("No audio streams found.")

    # Filter for English
    eng_streams = [
        s for s in audio_streams
        if s.get("tags", {}).get("language", "").lower().startswith("en")
    ]

    candidates = eng_streams if eng_streams else audio_streams

    # Sort by channels (descending), then index (ascending)
    # candidates are dicts.
    candidates.sort(key=lambda s: (-int(s.get("channels", 2)), int(s.get("index"))))

    selected = candidates[0]
    return int(selected["index"])

def extract_audio(input_path, stream_index, output_path):
    """
    Extracts the specified audio stream to 48kHz Stereo PCM WAV.
    """
    cmd = [
        "ffmpeg",
        "-y",
        "-i", input_path,
        "-map", f"0:{stream_index}",
        "-ac", "2",              # Stereo
        "-ar", "48000",          # 48kHz
        "-c:a", "pcm_f32le",     # 32-bit float PCM
        output_path
    ]
    logging.info(f"Extracting stream {stream_index} to {output_path}...")
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        logging.error(f"Error extracting audio: {e}")
        raise

def preprocess_audio(input_path, output_path):
    """
    Preprocesses audio for Whisper:
    - 16kHz
    - Mono
    - Bandpass filter (100Hz - 8kHz)
    """
    cmd = [
        "ffmpeg",
        "-y",
        "-i", input_path,
        "-ac", "1",
        "-ar", "16000",
        "-af", "highpass=f=100,lowpass=f=8000",
        output_path
    ]
    logging.info(f"Preprocessing {input_path} -> {output_path}...")
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        logging.error(f"Error preprocessing audio: {e}")
        raise
