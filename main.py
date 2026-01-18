"""
LiveSubs/Srtforge Remake - Main entry point.

A modular subtitle generation pipeline that mimics Srtforge audio processing:
- Probe and extract audio (48kHz)
- Separate vocals using BS-Roformer (FV4)
- Preprocess for Whisper (16kHz)
- Transcribe with faster-whisper
- Post-process timing and formatting
- Correct text with Gemini API
"""
import os
import sys
import argparse
import logging
import tempfile

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def main():
    parser = argparse.ArgumentParser(description="LiveSubs/Srtforge Remake")
    parser.add_argument("input_file", help="Path to input media file")
    parser.add_argument("--output", "-o", help="Output SRT path (default: input_file.srt)")
    parser.add_argument("--no-gemini", action="store_true", help="Skip Gemini correction")
    parser.add_argument("--keep-temp", action="store_true", help="Keep temporary files (in ./temp)")

    args = parser.parse_args()

    input_path = os.path.abspath(args.input_file)
    if not os.path.exists(input_path):
        logging.error(f"Input file not found: {input_path}")
        sys.exit(1)

    base_name = os.path.splitext(os.path.basename(input_path))[0]
    output_srt = args.output or os.path.join(os.path.dirname(input_path), f"{base_name}.srt")

    # Logic to handle temp directory
    try:
        if args.keep_temp:
            work_dir = os.path.join(os.getcwd(), "temp")
            os.makedirs(work_dir, exist_ok=True)
            run_pipeline(input_path, output_srt, work_dir, args)
        else:
            with tempfile.TemporaryDirectory() as temp_dir:
                run_pipeline(input_path, output_srt, temp_dir, args)

    except Exception as e:
        logging.error(f"Processing failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

def run_pipeline(input_path, output_srt, work_dir, args):
    # Lazy imports to speed up CLI startup
    from src.audio import probe_file, select_best_audio_stream, extract_audio, preprocess_audio
    from src.separator import separate_vocals
    from src.asr import transcribe_audio
    from src.postprocess import run_post_processing, write_srt

    logging.info(f"Processing: {input_path}")
    logging.info(f"Working directory: {work_dir}")

    # 1. Probe & Select Stream
    probe_data = probe_file(input_path)
    stream_idx = select_best_audio_stream(probe_data)
    logging.info(f"Selected audio stream index: {stream_idx}")

    # 2. Extract Audio (48k Stereo)
    extracted_wav = os.path.join(work_dir, "extracted_48k.wav")
    extract_audio(input_path, stream_idx, extracted_wav)

    # 3. Separate Vocals
    # separate_vocals takes input path and output DIR.
    # It returns the full path to the vocal file.
    vocal_wav_path = separate_vocals(extracted_wav, work_dir)
    if not vocal_wav_path or not os.path.exists(vocal_wav_path):
        logging.error(f"Vocal separation failed; invalid vocal path returned: {vocal_wav_path}")
        raise FileNotFoundError(f"Vocal track not found at path: {vocal_wav_path}")
    logging.info(f"Vocals separated: {vocal_wav_path}")

    # 4. Preprocess (16k Mono)
    final_wav = os.path.join(work_dir, "preprocessed_16k.wav")
    preprocess_audio(vocal_wav_path, final_wav)

    # 5. ASR
    events = transcribe_audio(final_wav)
    logging.info(f"ASR complete. {len(events)} events.")

    # 6. Post Processing (Timing/Shaping)
    events = run_post_processing(events)
    logging.info("Post-processing complete.")

    # 7. Gemini
    if not args.no_gemini:
        from src.gemini import correct_text_only_with_gemini
        events = correct_text_only_with_gemini(final_wav, events)

    # 8. Write SRT
    write_srt(events, output_srt)
    logging.info(f"Subtitle saved to: {output_srt}")

if __name__ == "__main__":
    main()
