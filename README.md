# Live_Subs: Real-time Subtitles with Whisper.cpp

This project generates live subtitles for system audio (or other specified audio inputs) using the efficient Whisper.cpp implementation of OpenAI's Whisper model.

## Features

* Real-time audio transcription.
* Utilizes Whisper.cpp for fast and efficient Speech-to-Text.
* Supports various Whisper models (from tiny to large).
* Requires FFmpeg for audio handling.
* (Potentially) Customizable subtitle display/output.

## Requirements

Before you begin, ensure you have the following installed:

1.  **Python:** Version 3.x recommended.
2.  **pip:** Python package installer (usually comes with Python).
3.  **FFmpeg:**
    * FFmpeg must be installed on your system.
    * Crucially, the `ffmpeg` executable must be accessible via your system's **PATH** environment variable so the script can call it directly. You can test this by typing `ffmpeg -version` in your terminal.
    * Download from [https://ffmpeg.org/download.html](https://ffmpeg.org/download.html) or use a package manager (like `apt`, `brew`, `choco`).
4.  **Whisper.cpp:** This project relies on Whisper.cpp. You will likely need to compile it yourself, especially if you want GPU acceleration.
    * Clone the Whisper.cpp repository: `git clone https://github.com/ggerganov/whisper.cpp.git`
    * Follow their build instructions: [https://github.com/ggerganov/whisper.cpp#build](https://github.com/ggerganov/whisper.cpp#build)
5.  **Python Packages:** Install the required Python libraries using pip:
    ```bash
    pip install -r requirements.txt
    ```
    *(Note: Ensure you have a `requirements.txt` file listing dependencies like `numpy`, `sounddevice`, potentially `whisper-cpp-python` if using bindings, etc.)*

## Installation

1.  **Clone this repository:**
    ```bash
    git clone [https://github.com/Kunal926/Live_Subs.git](https://github.com/Kunal926/Live_Subs.git)
    cd Live_Subs
    ```
2.  **Install Python Dependencies:** (See Requirements section above)
    ```bash
    pip install -r requirements.txt
    ```
3.  **Build Whisper.cpp:** (See Requirements section above). Ensure the compiled Whisper.cpp executables (like `main` or `stream`) or library files are accessible if your Python script calls them or links against them.

## Configuration

### 1. Paths and Environment Variables

**Important:** Avoid hard-coding file paths directly into the script (`.py` files). This makes the project difficult to run on different machines or with different setups.

**Recommended Approaches:**

* **Relative Paths:** Use paths relative to the script's location (e.g., `./models/ggml-base.en.bin`). This is often suitable for models stored within the project directory.
* **Environment Variables:** Define system environment variables to specify locations. This is excellent for paths outside the project directory.
    * **Example:** Set an environment variable `WHISPER_MODEL_PATH` pointing to the location of your downloaded `ggml` model file.
      * *Linux/macOS:* `export WHISPER_MODEL_PATH="/path/to/your/models/ggml-base.en.bin"`
      * *Windows (cmd):* `set WHISPER_MODEL_PATH="C:\path\to\your\models\ggml-base.en.bin"`
      * *Windows (PowerShell):* `$env:WHISPER_MODEL_PATH="C:\path\to\your\models\ggml-base.en.bin"`
    * Your Python script would then read this variable:
        ```python
        import os
        model_path = os.getenv('WHISPER_MODEL_PATH', './models/ggml-default-model.bin') # Provide a default
        ```
* **Command-Line Arguments:** Allow users to specify paths when running the script:
    ```bash
    python your_script_name.py --model-path /path/to/model.bin
    ```

**Action Required:** Review your Python code (`.py` files) and replace any hard-coded paths (like `C:/Users/...` or `/home/user/...`) with one of the methods above.

### 2. Whisper Model Selection

* You need to choose a Whisper model and make it available to the script.
* See the **Whisper Models** section below for details on how to download or convert models.
* Configure your script (via environment variable, command-line argument, or config file) to point to the specific `.bin` model file you want to use.

## Whisper Models (`ggml` Format)

This project uses Whisper models converted to the `ggml` format for use with Whisper.cpp.

The [original Whisper PyTorch models provided by OpenAI](https://github.com/openai/whisper/blob/main/whisper/__init__.py#L17-L30) are converted to the custom `ggml` format.

There are three main ways to obtain `ggml` models:

### 1. Use `download-ggml-model.sh` (Part of Whisper.cpp)

Navigate to your cloned `whisper.cpp` directory and use the provided script:
```bash
cd /path/to/whisper.cpp
./models/download-ggml-model.sh base.en
# Example output:
# Downloading ggml model base.en ...
# models/ggml-base.en.bin              100%[=============================================>] 141.11M   5.41MB/s    in 22s
# Done! Model 'base.en' saved in 'models/ggml-base.en.bin'
