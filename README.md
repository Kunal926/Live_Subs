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
        # Provide a default path relative to the script if the env var isn't set
        default_model_path = os.path.join(os.path.dirname(__file__), 'models', 'ggml-base.en.bin')
        model_path = os.getenv('WHISPER_MODEL_PATH', default_model_path)
        ```
* **Command-Line Arguments:** Allow users to specify paths when running the script using libraries like `argparse`:
    ```bash
    python your_script_name.py --model-path /path/to/model.bin
    ```

**Action Required:** Review your Python code (`.py` files) and replace any hard-coded paths (like `C:/Users/...` or `/home/user/...`) with one of the methods above. Using environment variables or command-line arguments with sensible defaults is generally preferred for flexibility.

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
(Remember the path where the model is saved, e.g., whisper.cpp/models/ggml-base.en.bin, and configure your script to find it.)2. Manually Download Pre-converted ModelsDownload .bin files directly from Hugging Face:https://huggingface.co/ggerganov/whisper.cpp/tree/main3. Convert Original PyTorch ModelsIf you have the original PyTorch models, you can convert them using the convert-pt-to-ggml.py script from Whisper.cpp.Example conversion (assuming original models are in ~/.cache/whisper and Whisper.cpp is cloned):cd /path/to/whisper.cpp
# Create a temporary directory if needed
mkdir models/whisper-medium-temp
# Convert (adjust paths as necessary)
python models/convert-pt-to-ggml.py ~/.cache/whisper/medium.pt ../whisper ./models/whisper-medium-temp
# Move the final model
mv ./models/whisper-medium-temp/ggml-model.bin models/ggml-medium.bin
# Clean up
rmdir models/whisper-medium-temp
Available Models (Subset)ModelDiskSHANotestiny75 MiBbd577a113a864445d4c299885e0cb97d4ba92b5fMultilingualtiny.en75 MiBc78c86eb1a8faa21b369bcd33207cc90d64ae9dfEnglish-onlybase142 MiB465707469ff3a37a2b9b8d8f89f2f99de7299dacMultilingualbase.en142 MiB137c40403d78fd54d454da0f9bd998f78703390cEnglish-onlysmall466 MiB55356645c2b361a969dfd0ef2c5a50d530afd8d5Multilingualsmall.en466 MiBdb8a495a91d927739e50b3fc1cc4c6b8f6c2d022English-onlymedium1.5 GiBfd9727b6e1217c2f614f9b698455c4ffd82463b4Multilingualmedium.en1.5 GiB8c30f0e44ce9560643ebd10bbe50cd20eafd3723English-onlylarge-v12.9 GiBb1caaf735c4cc1429223d5a74f0f4d0b9b59a299Multilinguallarge-v22.9 GiB0f4c8e34f21cf1a914c59d8b3ce882345ad349d6Multilinguallarge-v32.9 GiBad82bf6a9043ceed055076d0fd39f5f186ff8062Multilinguallarge-v3-q5_01.1 GiBe6e2ed78495d403bef4b7cff42ef4aaadcfea8deQuantized (Multilingual)(Many more models, including quantized versions, are available via the download script or Hugging Face.)Fine-tuned & Distilled ModelsWhisper.cpp also supports converting and using fine-tuned models (e.g., from Hugging Face Hub) or distilled models (like distil-whisper). Refer to the Whisper.cpp documentation (whisper.cpp/models/README.md) for conversion scripts (convert-h5-to-ggml.py) and usage details if needed.Building with GPU Support (CUDA/cuDNN)For significantly faster transcription, especially with larger models, build Whisper.cpp with GPU acceleration:Install Prerequisites:NVIDIA DriversCUDA ToolkitcuDNNBuild Whisper.cpp with CMake Flags: When running CMake for Whisper.cpp, enable CUDA support:cd /path/to/whisper.cpp
# Remove build directory if it exists to ensure clean configuration
rm -rf build
mkdir build
cd build
# Enable cuBLAS support (most common for NVIDIA GPUs)
cmake .. -DWHISPER_CUBLAS=ON
# Alternatively, check Whisper.cpp docs for other flags like -DWHISPER_CUDA=ON
# Compile using multiple cores
make -j
Ensure your Python script uses the GPU-enabled Whisper.cpp build (this might happen automatically if using the compiled executables, or might require specific setup if using Python bindings). Check the Whisper.cpp documentation for how it selects the backend (CPU vs GPU).Usage(Provide instructions on how to run your main script. Replace your_script_name.py with the actual filename.)# Example: Run with default settings (ensure configuration is done via env vars or defaults)
python your_script_name.py

# Example: Run specifying model path and language via arguments (if you implement them)
python your_script_name.py --model /path/to/whisper.cpp/models/ggml-base.en.bin --language en

# Example: Run specifying the path to the whisper.cpp main executable (if you call it as a subprocess)
python your_script_name.py --whisper-main /path/to/whisper.cpp/main --model /path/to/models/ggml-base.en.bin
(Add details specific to your script: required arguments, optional flags, how to select audio input if configurable, how to stop the script, etc.)Memory Usage (Approximate)RAM usage depends heavily on the model selected. These are rough estimates for CPU execution:ModelDiskApprox. RAMtiny75 MiB~273 MBbase142 MiB~388 MBsmall466 MiB~852 MBmedium1.5 GiB~2.1 GBlarge2.9 GiB~3.9 GB(Note: Actual memory usage can vary based on the specific Whisper.cpp version, compilation flags (like GPU usage), and system. GPU usage will also consume VRAM.)Contributing(Optional: Add guidelines if you welcome contributions. E.g., "Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.")License*(Optional: Specify the license for your project, e.g., MIT, Apache 2.0.
