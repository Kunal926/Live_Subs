import sys
import os
import json
import torch
import torchaudio
import numpy as np
import argparse # Use argparse for better argument handling

# --- read_audio function remains the same ---
def read_audio(audio_path, sampling_rate=16000):
    """Loads, resamples, mono-izes, and normalizes audio."""
    try:
        # Load audio using torchaudio
        wav, sr = torchaudio.load(audio_path)
        # Resample if necessary
        if sr != sampling_rate:
            resampler = torchaudio.transforms.Resample(orig_freq=sr, new_freq=sampling_rate)
            wav = resampler(wav)
        # Convert to mono if not already
        if wav.shape[0] > 1:
            wav = torch.mean(wav, dim=0, keepdim=True)

        # --- Removed normalization - Let Whisper handle it ---
        # wav = wav / torch.max(torch.abs(wav))
        # Ensure it's float32 as expected by Silero
        wav = wav.float()
        # Ensure it's a 1D tensor for VAD
        if wav.dim() > 1 and wav.shape[0] == 1:
             wav = wav.squeeze(0)

        return wav
    except Exception as e:
        print(f'Audio processing error: {e}', file=sys.stderr)
        # Print stack trace for more details
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)
# --- End of read_audio ---

def main():
    """
    Processes the given audio file using Silero VAD and writes speech segments to a JSON file.

    Accepts additional VAD parameters like speech_pad_ms.
    """
    # --- Use argparse for clearer argument parsing ---
    parser = argparse.ArgumentParser(description="Silero VAD processing script.")
    parser.add_argument("input_wav_file", help="Path to the WAV audio file.")
    parser.add_argument("output_dir", help="Directory to save the output JSON file.")
    parser.add_argument("--sampling_rate", type=int, default=16000, help="Sampling rate for audio processing.")
    parser.add_argument("--vad_mode", default='normal', help="VAD sensitivity ('normal', 'aggressive', etc.).")
    parser.add_argument("--speech_pad_ms", type=int, default=200, help="Padding added to the start and end of detected speech segments (ms).") # Default padding
    parser.add_argument("--min_silence_duration_ms", type=int, default=100, help="Minimum silence duration (ms).")
    parser.add_argument("--min_speech_duration_ms", type=int, default=250, help="Minimum speech duration (ms).")


    # --- Check if running with '-h' or '--help' before checking positional args ---
    if '-h' in sys.argv or '--help' in sys.argv:
         parser.print_help()
         sys.exit(0)
    # --- Basic check for positional arguments ---
    if len(sys.argv) < 3:
         print("Usage: vad_script.py <input_wav_file> <output_dir> [options]", file=sys.stderr)
         parser.print_help()
         sys.exit(1)

    # --- Parse arguments ---
    # Note: We parse known args first to handle options correctly even if positional args are missing initially
    # This is a bit of a workaround because argparse expects options before positionals usually.
    try:
        args = parser.parse_args()
    except SystemExit: # Catch exit triggered by argparse error
         sys.exit(1) # Exit with error code
    except Exception as e:
         print(f"Argument parsing error: {e}", file=sys.stderr)
         sys.exit(1)

    input_wav = args.input_wav_file
    output_dir = args.output_dir
    sampling_rate = args.sampling_rate
    vad_mode = args.vad_mode
    speech_pad_ms = args.speech_pad_ms
    min_silence_duration_ms = args.min_silence_duration_ms
    min_speech_duration_ms = args.min_speech_duration_ms

    output_file = os.path.join(output_dir, "vad_segments.json")

    # Ensure the input file exists
    if not os.path.exists(input_wav):
        print(f"Error: The file {input_wav} does not exist.", file=sys.stderr)
        sys.exit(1)

    # Read audio using torchaudio
    print(f"Reading audio file: {input_wav}", file=sys.stderr) # Log progress
    wav = read_audio(input_wav, sampling_rate)
    print(f"Audio loaded, shape: {wav.shape}, dtype: {wav.dtype}", file=sys.stderr) # Log progress

    # Load Silero VAD model and utilities
    try:
        print("Loading Silero VAD model...", file=sys.stderr) # Log progress
        # Use force_reload=True if you suspect cache issues, otherwise False is fine
        model, utils_vad = torch.hub.load(repo_or_dir='snakers4/silero-vad',
                                          model='silero_vad',
                                          force_reload=False,
                                          trust_repo=True)
        # Unpack only the function we need
        (get_speech_timestamps, _, read_audio_silero, *_) = utils_vad
        print("Silero VAD model loaded.", file=sys.stderr) # Log progress
    except Exception as e:
        print(f"Error loading Silero VAD model: {e}", file=sys.stderr)
        sys.exit(1)

    # Map vad_mode to threshold (example, adjust as needed)
    if vad_mode.lower() == 'normal':
        threshold = 0.5
    elif vad_mode.lower() == 'low_bitrate':
         threshold = 0.65 # Example threshold for low bitrate model if used
    elif vad_mode.lower() == 'aggressive':
        threshold = 0.7
    elif vad_mode.lower() == 'very_aggressive':
         threshold = 0.85
    else:
        try:
            threshold = float(vad_mode) # Allow passing a specific threshold
            print(f"Using custom VAD threshold: {threshold}", file=sys.stderr)
        except ValueError:
            threshold = 0.5  # Default threshold
            print(f"Unknown VAD mode '{vad_mode}', using default threshold: {threshold}", file=sys.stderr)


    # Get speech timestamps using VAD with padding
    try:
        print(f"Running VAD with: threshold={threshold}, pad={speech_pad_ms}ms, min_silence={min_silence_duration_ms}ms, min_speech={min_speech_duration_ms}ms", file=sys.stderr)
        speech_timestamps = get_speech_timestamps(
            wav,
            model,
            sampling_rate=sampling_rate,
            threshold=threshold,
            min_silence_duration_ms=min_silence_duration_ms, # Default is often 100
            speech_pad_ms=speech_pad_ms,                     # Add padding here
            min_speech_duration_ms=min_speech_duration_ms    # Default is often 250
        )
        print(f"VAD found {len(speech_timestamps)} segments.", file=sys.stderr)
    except Exception as e:
        print(f"Error during VAD processing: {e}", file=sys.stderr)
        # Print stack trace for more details
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)

    # Collect speech segments
    speech_segments = []
    for segment in speech_timestamps:
        # Ensure start and end keys exist
        if 'start' in segment and 'end' in segment:
            start_ms = int((segment['start'] / sampling_rate) * 1000)
            end_ms = int((segment['end'] / sampling_rate) * 1000)
            speech_segments.append({'start': start_ms, 'end': end_ms})
        else:
             print(f"Warning: VAD segment missing 'start' or 'end' key: {segment}", file=sys.stderr)


    # Write segments to vad_segments.json in the specified output directory
    try:
        print(f"Writing {len(speech_segments)} segments to {output_file}", file=sys.stderr)
        with open(output_file, 'w') as f:
            json.dump(speech_segments, f, indent=2) # Add indent for readability
        print(f"Segments written successfully.") # Print success to stdout for Lua script
    except Exception as e:
        print(f"Error writing segments to file: {e}", file=sys.stderr)
        sys.exit(1)

    sys.exit(0) # Explicitly exit with success code

if __name__ == "__main__":
    main()
