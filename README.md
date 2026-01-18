# LiveSubs Remake

A modular subtitle generation pipeline.

## Features

- **Audio Processing Pipeline**: Probe → Extract (48kHz) → Separate Vocals (FV4) → Preprocess (16kHz)
- **ASR with faster-whisper**: Custom smart segmentation based on pauses and character limits
- **Gemini AI Text Correction**: Spelling/typo fixes and style guide enforcement
- **Post-processing**: Timing adjustments, CPS optimization, and subtitle shaping
- **Modular CLI**: Lazy imports for fast startup
- **PyInstaller Support**: Package as standalone executable

## Installation

```bash
pip install -r requirements.txt
```

## Usage

```bash
python main.py input_video.mp4 --output subtitles.srt
```

### Options

- `--output, -o`: Output SRT path (default: input_file.srt)
- `--no-gemini`: Skip Gemini correction
- `--keep-temp`: Keep temporary files in ./temp directory

## Configuration

### Gemini API Key

To use Gemini text correction, set the `GEMINI_API_KEY` environment variable:

```bash
export GEMINI_API_KEY="your-api-key-here"
```

**⚠️ Security Warning**: 
- Never commit API keys to version control
- Always use environment variables for sensitive credentials
- Keep your `.gitignore` file updated to exclude any files containing secrets
- Consider using a secret management service for production deployments
- If you accidentally commit an API key, rotate it immediately

### Model Selection

You can override the default Gemini model by setting:

```bash
export GEMINI_MODEL_ID="gemini-2.0-flash"  # default
```

## Building with PyInstaller

```bash
pyinstaller main.spec
```

The built executable will be in `dist/SrtforgeRemake/`.

## Dependencies

- `faster-whisper`: ASR with word-level timestamps
- `audio-separator`: Vocal separation using BS-Roformer
- `google-genai`: Gemini API for text correction
- `ffmpeg`: Audio processing (must be installed separately)
- `torch`: Deep learning framework

## License

See LICENSE file for details.
