-- Required modules
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local json = require 'mp.utils'.parse_json -- Utilize mpv's built-in JSON parser

-- Define constants
local TMP_DIR = "C:/temp"
local TMP_WAV_PATH = utils.join_path(TMP_DIR, "mpv_whisper_live_tmp.wav")
local WHISPER_CMD = 'D:/Whisper/whisper.cpp/build/bin/Release/main.exe'
local WHISPER_MODEL = 'D:/Whisper/whisper.cpp/models/ggml-large-v3-turbo.bin'
local FFMPEG_PATH = 'C:/ffmpeg/bin/ffmpeg.exe'
local THREADS = 8
local LANGUAGE = "en"
local INIT_POS = 0 -- Starting position to start creating subs in ms
local MAIN_SRT_PATH = utils.join_path(TMP_DIR, "mpv_whisper_main_subs.srt") -- Path to accumulate all subtitle chunks
local VAD_SCRIPT_PATH = "C:/Users/chahe/OneDrive/Desktop/software/Scripts/vad_script.py" -- Updated VAD script path

-- Global state tracking
local running = false
local loopRunning = false

-- Define log file path
local LOG_FILE_PATH = utils.join_path(TMP_DIR, "mpv_whisper_log.txt")

-- Ensure TMP_DIR exists
os.execute('mkdir "' .. TMP_DIR .. '"')

-- Function to log messages to a file
local function logMessage(message)
    msg.info(message)
    local log_file = io.open(LOG_FILE_PATH, "a")
    if log_file then
        log_file:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. message .. "\n")
        log_file:close()
    end
end

-- Function to run commands with enhanced logging and error handling
local function runCommand(executable, args_table, callback)
    -- Log the command and its arguments
    logMessage('Running command: ' .. executable)
    for i, arg in ipairs(args_table) do
        logMessage('Arg ' .. i .. ': ' .. arg)
    end

    -- Prepare the arguments array
    local command_args = { executable }
    for _, arg in ipairs(args_table) do
        table.insert(command_args, arg)
    end

    -- Run the subprocess
    local start_time = mp.get_time()
    local res = utils.subprocess({
        args = command_args,
        cancellable = false,
        max_size = 10 * 1024 * 1024, -- Limit output to 10MB
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    })
    local end_time = mp.get_time()
    local elapsed_time = end_time - start_time

    -- Log all outputs
    logMessage('Command Output (stdout): ' .. (res.stdout or ''))
    logMessage('Command Output (stderr): ' .. (res.stderr or ''))

    if res.error then
        logMessage('Command Error: ' .. res.error)
    else
        logMessage('Command exited with status: ' .. tostring(res.status))
    end

    logMessage(string.format('Command execution time: %.2f seconds', elapsed_time))

    -- Call the callback function if provided
    if callback then
        callback(res.stdout or "", res.status == 0, elapsed_time)
    end
end

-- Function to append new subtitles to the main SRT file
local function appendToMainSRT(new_srt_path)
    logMessage("Attempting to append new subtitles to main SRT.")
    local new_srt_file = io.open(new_srt_path, "r")
    if not new_srt_file then
        logMessage("New subtitle file not found: " .. new_srt_path)
        return
    end

    local new_content = new_srt_file:read("*all")
    new_srt_file:close()

    local main_srt_file = io.open(MAIN_SRT_PATH, "a+")
    if main_srt_file then
        main_srt_file:write(new_content)
        main_srt_file:close()
        logMessage("Appended new subtitles to main subtitle file: " .. MAIN_SRT_PATH)
    else
        logMessage("Failed to open main subtitle file: " .. MAIN_SRT_PATH)
    end

    -- Load the updated main subtitles
    mp.commandv("sub-reload")
    -- After appending subtitles
    mp.commandv("sub-add", MAIN_SRT_PATH, "select")
    logMessage("Subtitles added to mpv: " .. MAIN_SRT_PATH)
end

-- Function to append adjusted SRT content to the main SRT file
local function appendToMainSRT(srt_adjusted_path)
    local adjusted_file = io.open(srt_adjusted_path, "r")
    if not adjusted_file then
        logMessage("Failed to open adjusted SRT file: " .. srt_adjusted_path)
        return false
    end

    local adjusted_content = adjusted_file:read("*all")
    adjusted_file:close()

    -- Append adjusted content to the main SRT file
    local main_srt_file = io.open(MAIN_SRT_PATH, "a")
    if not main_srt_file then
        logMessage("Failed to open main SRT file: " .. MAIN_SRT_PATH)
        return false
    end
    main_srt_file:write(adjusted_content)
    main_srt_file:close()
    logMessage("Appended new subtitles to main subtitle file: " .. MAIN_SRT_PATH)
    
    -- Refresh subtitles in the media player (mpv command)
    mp.commandv("sub-reload")
    logMessage("Subtitles reloaded in mpv.")

    return true
end

-- Function to extract audio using FFmpeg
local function extractAudio(media_path, start_ms, duration_ms, callback)
    logMessage("Extracting audio: start_ms=" .. start_ms .. ", duration_ms=" .. duration_ms)

    local args = {
        "-ss", tostring(start_ms / 1000),
        "-t", tostring(duration_ms / 1000),
        "-i", media_path,
        "-map", "0:a:m:language:eng", -- Ensure this correctly selects the English audio stream
        "-ac", "1",
        "-ar", "16000",
        "-acodec", "pcm_s16le",
        "-af", "aresample=resampler=soxr",
        "-y", TMP_WAV_PATH
    }

    runCommand(FFMPEG_PATH, args, function(output, success, elapsed_time)
        if not success then
            logMessage("FFmpeg command failed.")
            running = false
            return
        end
        -- Verify that the WAV file was created
        local file = io.open(TMP_WAV_PATH, "rb")
        if file then
            local size = file:seek("end")
            file:close()
            logMessage("Audio extracted to " .. TMP_WAV_PATH .. " (Size: " .. size .. " bytes)")
            if size and size > 0 then
                logMessage("Calling VAD function.")
                callback()
            else
                logMessage("Extracted WAV file is empty: " .. TMP_WAV_PATH)
                running = false
            end
        else
            logMessage("Failed to create WAV file: " .. TMP_WAV_PATH)
            running = false
        end
    end)
end

-- Function to run Silero VAD and get speech segments
local function runVAD(callback)
    logMessage("Running Silero VAD on extracted audio.")

    local args = {
        VAD_SCRIPT_PATH,
        TMP_WAV_PATH,
        "16000",      -- Sampling rate
        "normal"      -- VAD mode ('normal', 'aggressive', etc.)
    }

    runCommand('python', args, function(output, success, elapsed_time)
        if not success then
            logMessage("VAD command failed.")
            running = false
            return
        end

        -- Parse JSON output
        local speech_segments, err = json(output)
        if not speech_segments then
            logMessage("Failed to parse VAD JSON output: " .. (err or "unknown error"))
            running = false
            return
        end

        logMessage("VAD detected " .. #speech_segments .. " speech segments.")

        if #speech_segments == 0 then
            logMessage("No speech segments detected in this chunk.")
            -- Optionally, proceed without transcription or wait for the next chunk
            if callback then callback({}) end
            return
        end

        logMessage("Proceeding to transcribe detected speech segments.")
        callback(speech_segments)
    end)
end

-- Function to adjust timestamps in the SRT file
local function adjustTimestamps(srt_input_path, srt_output_path, time_offset_ms)
    local input_file = io.open(srt_input_path, "r")
    if not input_file then
        logMessage("Failed to open SRT input file: " .. srt_input_path)
        return false
    end

    local content = input_file:read("*all")
    input_file:close()

    -- Adjust the timestamps
    local adjusted_content = content:gsub("(%d%d:%d%d:%d%d),(%d%d%d)", function(time_str, ms_str)
        local hours, minutes, seconds = time_str:match("(%d%d):(%d%d):(%d%d)")
        local total_ms = (tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds)) * 1000 + tonumber(ms_str)
        local adjusted_ms = total_ms + time_offset_ms
        local adjusted_hours = math.floor(adjusted_ms / (3600 * 1000))
        adjusted_ms = adjusted_ms % (3600 * 1000)
        local adjusted_minutes = math.floor(adjusted_ms / (60 * 1000))
        adjusted_ms = adjusted_ms % (60 * 1000)
        local adjusted_seconds = math.floor(adjusted_ms / 1000)
        adjusted_ms = adjusted_ms % 1000
        return string.format("%02d:%02d:%02d,%03d", adjusted_hours, adjusted_minutes, adjusted_seconds, adjusted_ms)
    end)

    local output_file = io.open(srt_output_path, "w")
    if not output_file then
        logMessage("Failed to create adjusted SRT file: " .. srt_output_path)
        return false
    end
    output_file:write(adjusted_content)
    output_file:close()
    logMessage("Timestamps adjusted and saved to: " .. srt_output_path)
    return true
end

-- Helper function to transcribe audio using Whisper
    local function transcribeAudio(audio_path, whisper_output, adjusted_start_time, callback)
        local whisper_args = {
            "-m", WHISPER_MODEL,
            "-t", tostring(THREADS),
            "--language", LANGUAGE,
            "--output-srt",
            "--file", audio_path,
            "--output-file", whisper_output,
            "--beam-size", "5",
            "--best-of", "5"
        }
    
        runCommand(WHISPER_CMD, whisper_args, function(output, success, elapsed_time)
            if not success then
                logMessage("Whisper command failed for transcription.")
                callback(false)
                return
            end
            callback(true)
        end)
    end
    
-- Modified transcribeSegment function to pad short segments with silence

local function transcribeSegment(segment, chunk_start_time_ms, callback)
    logMessage(string.format("Transcribing segment: start=%d ms, end=%d ms", segment.start, segment["end"]))

    local segment_duration_ms = segment["end"] - segment.start

    -- Define paths for the segment audio and transcription
    local segment_audio_path = utils.join_path(TMP_DIR, string.format("segment_%d_%d.wav", segment.start, segment["end"]))
    local whisper_output = utils.join_path(TMP_DIR, string.format("mpv_whisper_live_sub_%d_%d", segment.start, segment["end"]))

    -- Extract the specific audio segment using FFmpeg
    local extract_args = {
        "-ss", tostring(segment.start / 1000),
        "-t", tostring(segment_duration_ms / 1000),
        "-i", TMP_WAV_PATH,
        "-ac", "1",
        "-ar", "16000",
        "-acodec", "pcm_s16le",
        "-af", "afftdn,volume=2.0,aresample=resampler=soxr",
        "-y", segment_audio_path
    }

    runCommand(FFMPEG_PATH, extract_args, function(output, success, elapsed_time)
        if not success then
            logMessage("FFmpeg command for segment extraction failed.")
            callback(false)
            return
        end

        if segment_duration_ms < 1000 then
            local padding_duration_ms = 1000 - segment_duration_ms
            logMessage("Padding segment with " .. padding_duration_ms .. " ms of silence.")

            -- Apply padding using adelay and apad filters
            local padded_audio_path = utils.join_path(TMP_DIR, string.format("padded_segment_%d_%d.wav", segment.start, segment["end"]))
            local pad_args = {
                "-i", segment_audio_path,
                "-af", string.format("adelay=0|0,apad=pad_dur=%f", padding_duration_ms / 1000),
                "-acodec", "pcm_s16le",
                "-ar", "16000",
                "-ac", "1",
                "-y", padded_audio_path
            }

            runCommand(FFMPEG_PATH, pad_args, function(pad_output, pad_success, pad_elapsed)
                if not pad_success then
                    logMessage("FFmpeg command for padding failed.")
                    callback(false)
                    return
                end

                -- Proceed to transcription using the padded audio
                transcribeAudio(padded_audio_path, whisper_output, chunk_start_time_ms + segment.start, function(transcribe_success)
                    -- After transcribing and adjusting timestamps
                    local srt_input_path = whisper_output .. ".srt"
                    local srt_adjusted_path = utils.join_path(TMP_DIR, string.format("mpv_whisper_live_sub_adjusted_%d_%d.srt", segment.start, segment["end"]))
                    local adjusted = adjustTimestamps(srt_input_path, srt_adjusted_path, chunk_start_time_ms + segment.start)

                    if adjusted then
                        appendToMainSRT(srt_adjusted_path)
                    else
                        logMessage("Failed to adjust timestamps for segment.")
                    end
                    -- Cleanup temporary files
                    os.remove(segment_audio_path)
                    os.remove(padded_audio_path)
                    callback(transcribe_success)
                end)
            end)
        else
            -- Proceed to transcription using the original segment
            transcribeAudio(segment_audio_path, whisper_output, chunk_start_time_ms + segment.start, function(transcribe_success)
                -- After transcribing and adjusting timestamps
                local srt_input_path = whisper_output .. ".srt"
                local srt_adjusted_path = utils.join_path(TMP_DIR, string.format("mpv_whisper_live_sub_adjusted_%d_%d.srt", segment.start, segment["end"]))
                local adjusted = adjustTimestamps(srt_input_path, srt_adjusted_path, chunk_start_time_ms + segment.start)

                if adjusted then
                    appendToMainSRT(srt_adjusted_path)
                else
                    logMessage("Failed to adjust timestamps for segment.")
                end
                -- Cleanup temporary files
                os.remove(segment_audio_path)
                callback(transcribe_success)
            end)
        end
    end)
end

-- Function to process live subtitles with VAD integration
local function processLiveSubtitles(media_path)
    logMessage("processLiveSubtitles called with media_path: " .. media_path)
    if loopRunning then
        logMessage("Loop is already running, skipping duplicate call.")
        return
    end
    loopRunning = true
    running = true
    local duration = mp.get_property_number("duration")
    if not duration then
        logMessage("Media duration not available.")
        running = false
        loopRunning = false
        return
    end
    duration = duration * 1000 -- Convert to milliseconds
    logMessage("Media duration: " .. duration .. " ms")
    local current_time = INIT_POS
    local chunk_duration_ms = 60000 -- Process 60-second chunks

    local function loop()
        logMessage("Loop iteration started.")
        if not running then
            loopRunning = false
            mp.osd_message("Whisper Subtitles: Stopped", 2)
            logMessage("Whisper subtitles stopped by user.")
            return
        end

        if current_time >= duration then
            running = false
            loopRunning = false
            mp.osd_message("Whisper Subtitles: Finished", 2)
            logMessage("Whisper subtitles processing finished.")
            return
        end

        -- Adjust chunk duration if remaining time is less
        local remaining_time = duration - current_time
        if remaining_time < chunk_duration_ms then
            chunk_duration_ms = remaining_time
        end

        logMessage("Calling extractAudio.")
        extractAudio(media_path, current_time, chunk_duration_ms, function()
            logMessage("extractAudio callback executed.")
            runVAD(function(speech_segments)
                if #speech_segments == 0 then
                    logMessage("No speech segments detected in this chunk.")
                end

                -- Function to process each speech segment sequentially
                local function processSegments(index)
                    if index > #speech_segments then
                        -- All segments processed, advance current_time
                        current_time = current_time + chunk_duration_ms
                        -- Schedule next chunk
                        if running then
                            mp.add_timeout(0.5, loop) -- Short delay before next chunk
                        end
                        return
                    end

                    local segment = speech_segments[index]
                    logMessage(string.format("Processing segment %d/%d: start=%d ms, end=%d ms", index, #speech_segments, segment.start, segment["end"]))

                    transcribeSegment(segment, current_time, function(success)
                        if success then
                            logMessage(string.format("Segment %d/%d transcribed successfully.", index, #speech_segments))
                        else
                            logMessage(string.format("Segment %d/%d transcription failed.", index, #speech_segments))
                        end
                        -- Proceed to the next segment
                        processSegments(index + 1)
                    end)
                end

                -- Start processing segments
                processSegments(1)
            end)
        end)
    end

    loop()
end

-- Function to start live subtitles
local function start()
    logMessage("Start function called.")
    running = true

    -- Clear the main subtitle file
    local main_srt_file = io.open(MAIN_SRT_PATH, "w")
    if main_srt_file then
        main_srt_file:write("")
        main_srt_file:close()
        logMessage("Cleared main subtitle file: " .. MAIN_SRT_PATH)
    else
        logMessage("Failed to clear main subtitle file: " .. MAIN_SRT_PATH)
    end

    local media_path = mp.get_property("path")
    if not media_path then
        mp.osd_message("No media file is loaded.", 2)
        running = false
        return
    end
    processLiveSubtitles(media_path)
end

-- Function to stop live subtitles
local function stop()
    logMessage("Stop function called.")
    if running then
        running = false
        loopRunning = false
        mp.osd_message("Whisper Subtitles: Stopping...", 2)
        logMessage("User requested to stop Whisper subtitles.")
    else
        mp.osd_message("Whisper Subtitles: Not running.", 2)
    end
end

-- Toggle function
local function toggle()
    logMessage("Toggle function called.")
    if running then
        stop()
        mp.commandv('show-text', 'Whisper subtitles: Off')
        mp.unregister_event("start-file", start)
        mp.unregister_event("end-file", stop)
    else
        start()
        mp.commandv('show-text', 'Whisper subtitles: On')
        mp.register_event("start-file", start)
        mp.register_event("end-file", stop)
    end
end

-- Key binding to toggle the live subtitle processing
mp.add_key_binding('ctrl+w', 'whisper_subs_toggle', toggle)
