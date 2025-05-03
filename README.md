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
2.  **
