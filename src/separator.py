"""
Vocal separation module using audio-separator.

Isolates vocal tracks from audio using BS-Roformer-Viperx model (FV4).
"""
import os
import logging
from audio_separator.separator import Separator

def separate_vocals(input_path, output_dir):
    """
    Separates vocals using audio-separator with FV4 model.
    Returns the path to the vocal file.
    """
    logging.info("Initializing Audio Separator (FV4)...")

    # Initialize Separator
    # We use output_single_stem="Vocals" to only save the vocal track
    sep = Separator(
        output_dir=output_dir,
        output_single_stem="Vocals"
    )

    # Load the FV4 model
    # The model filename for FV4 in audio-separator is typically 'model_bs_roformer_ep_317_sdr_12.9755.ckpt'
    # or known by key 'BS-Roformer-Viperx-1297'.
    # We use the key which the library resolves.
    model_name = "BS-Roformer-Viperx-1297"
    logging.info(f"Loading model: {model_name}")
    sep.load_model(model_filename=model_name)

    logging.info(f"Separating {input_path}...")
    # Perform separation
    output_files = sep.separate(input_path)

    logging.info(f"Separation output files: {output_files}")

    if not output_files:
        raise RuntimeError("Separation failed: no output files returned.")

    # Filter out any invalid filenames (non-strings, empty or whitespace-only).
    valid_files = [
        f for f in output_files
        if isinstance(f, str) and f.strip()
    ]

    if not valid_files:
        raise RuntimeError(
            "Separation failed: no valid output filenames returned."
        )

    # The library returns filenames. We need the full path.
    # Since we requested "Vocals", we expect one file, or maybe we need to find it.
    # Usually it appends parameters to the filename.

    # Return the first file path found
    for f in valid_files:
        full_path = os.path.join(output_dir, f)
        if os.path.exists(full_path):
            return full_path

    # If we are here, something is wrong with paths: none of the expected output files exist.
    raise RuntimeError(
        f"Separation failed: none of the expected output files exist in '{output_dir}'. "
        f"Reported output files: {output_files}"
    )
