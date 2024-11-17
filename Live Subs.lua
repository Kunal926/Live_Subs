-- Required modules
local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- Define constants
local TMP_DIR = "C:/temp"
local TMP_WAV_PATH = utils.join_path(TMP_DIR, "mpv_whisper_live_tmp.wav")
local WHISPER_CMD = 'D:/Whisper/whisper.cpp/build/bin/Release/main.exe'
local WHISPER_MODEL = 'D:/Whisper/whisper.cpp/models/ggml-medium.en.bin' -- Change to a larger model if needed
local FFMPEG_PATH = 'C:/ffmpeg/bin/ffmpeg.exe'
local CHUNK_DURATION_MS = 15000 -- 15 seconds
local THREADS = 6
local LANGUAGE = "en"
local INIT_POS = 0 -- starting position to start creating subs in ms
local MAIN_SRT_PATH = TMP_DIR .. "/mpv_whisper_main_subs.srt" -- Path to accumulate all subtitle chunks

-- Global state tracking
local running = false
local loopRunning = false

-- Define log file path
local LOG_FILE_PATH = TMP_DIR .. "/mpv_whisper_log.txt"

-- Ensure TMP_DIR exists
os.execute('mkdir "' .. TMP_DIR .. '"')

-- Function to log messages to a file
local function logMessage(message)
    msg.info(message)
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

    -- Log any errors or outputs
    if res.error then
        logMessage('Command Error: ' .. res.error)
    end

    if res.status == 0 then
        logMessage('Command Output (stdout): ' .. (res.stdout or ''))
        logMessage('Command Output (stderr): ' .. (res.stderr or ''))
    else
        logMessage('Command Error Output (stdout): ' .. (res.stdout or ''))
        logMessage('Command Error Output (stderr): ' .. (res.stderr or ''))
    end

    logMessage(string.format('Command execution time: %.2f seconds', elapsed_time))

    -- Call the callback function if provided
    if callback then
        callback(res.stdout or "", res.status == 0, elapsed_time)
    end
end

-- Function to append new subtitles to the main SRT file
local function appendToMainSRT(new_srt_path)
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

-- Function to extract a chunk of audio using FFmpeg
local function extractAudioChunk(media_path, start_ms, duration_ms, callback)
    logMessage("Extracting audio chunk: start_ms=" .. start_ms .. ", duration_ms=" .. duration_ms)

    local args = {
        "-ss", tostring(start_ms / 1000),
        "-t", tostring(duration_ms / 1000),
        "-i", media_path,
        "-map", "0:a:m:language:eng", -- Select English audio track based on metadata
        "-ac", "1",
        "-ar", "16000",
        "-acodec", "pcm_s16le",
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
            logMessage("Audio chunk extracted to " .. TMP_WAV_PATH .. " (Size: " .. size .. " bytes)")
            if size and size > 0 then
                logMessage("Calling transcribeAudio function.")
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

-- Function to adjust timestamps in the SRT file
local function adjustTimestamps(srt_input_path, srt_output_path, chunk_start_time_ms)
    logMessage("Adjusting timestamps in: " .. srt_input_path)
    local input_file = io.open(srt_input_path, "r")
    if not input_file then
        logMessage("Failed to open input SRT file: " .. srt_input_path)
        return false
    end

    local content = input_file:read("*all")
    input_file:close()

    -- Pattern to match timestamps in SRT files
    local timestamp_pattern = "(%d%d):(%d%d):(%d%d),(%d%d%d)"

    -- Function to adjust a single timestamp
    local function shiftTimestamp(h, m, s, ms)
        local total_ms = (((tonumber(h) * 60 + tonumber(m)) * 60) + tonumber(s)) * 1000 + tonumber(ms)
        total_ms = total_ms + chunk_start_time_ms

        local new_h = math.floor(total_ms / (60 * 60 * 1000))
        local new_m = math.floor((total_ms % (60 * 60 * 1000)) / (60 * 1000))
        local new_s = math.floor((total_ms % (60 * 1000)) / 1000)
        local new_ms = total_ms % 1000

        return string.format("%02d:%02d:%02d,%03d", new_h, new_m, new_s, new_ms)
    end

    -- Replace timestamps in the content
    local adjusted_content = content:gsub("(" .. timestamp_pattern .. ")%s*-->%s*(" .. timestamp_pattern .. ")", function(start_ts, h1, m1, s1, ms1, end_ts, h2, m2, s2, ms2)
        local new_start_ts = shiftTimestamp(h1, m1, s1, ms1)
        local new_end_ts = shiftTimestamp(h2, m2, s2, ms2)
        return new_start_ts .. " --> " .. new_end_ts
    end)

    -- Write the adjusted content to the output file
    local output_file = io.open(srt_output_path, "w")
    if not output_file then
        logMessage("Failed to open output SRT file: " .. srt_output_path)
        return false
    end
    output_file:write(adjusted_content)
    output_file:close()
    logMessage("Timestamps adjusted and saved to: " .. srt_output_path)
    return true
end

-- Function to convert timestamp to milliseconds
local function convertToMilliseconds(timestamp)
    local hours, minutes, seconds, milliseconds = timestamp:match("(%d%d):(%d%d):(%d%d),(%d%d%d)")
    return (tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds)) * 1000 + tonumber(milliseconds)
end

-- Function to convert milliseconds to timestamp
local function convertToTimestamp(milliseconds)
    local hours = math.floor(milliseconds / 3600000)
    milliseconds = milliseconds % 3600000
    local minutes = math.floor(milliseconds / 60000)
    milliseconds = milliseconds % 60000
    local seconds = math.floor(milliseconds / 1000)
    milliseconds = milliseconds % 1000
    return string.format("%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
end

-- Function to transcribe audio using Whisper
local function transcribeAudio(chunk_start_time_ms, callback)
    logMessage("Starting transcription with Whisper.")
    local whisper_output = TMP_DIR .. "/mpv_whisper_live_sub" -- Output without extension
    local args = {
        "-m", WHISPER_MODEL,
        "-t", tostring(THREADS),
        "--language", LANGUAGE,
        "--output-srt",
        "--file", TMP_WAV_PATH,
        "--output-file", whisper_output, -- Do not include .srt extension
        "--beam-size", "5", -- Use beam search with size 5 for better accuracy
        "--best-of", "5" -- Consider the best of 5 candidates
    }
    runCommand(WHISPER_CMD, args, function(output, success, elapsed_time)
        if not success then
            logMessage("Whisper command failed.")
            running = false
            return
        end
        logMessage("Transcription completed.")
        local srt_input_path = whisper_output .. ".srt"
        local srt_adjusted_path = TMP_DIR .. "/mpv_whisper_live_sub_adjusted.srt"
        local adjusted = adjustTimestamps(srt_input_path, srt_adjusted_path, chunk_start_time_ms)
        if adjusted then
            appendToMainSRT(srt_adjusted_path)
        else
            logMessage("Failed to adjust timestamps.")
        end
        if callback then callback() end
    end)
end

-- Function to process live subtitles
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

        logMessage("Calling extractAudioChunk.")
        extractAudioChunk(media_path, current_time, CHUNK_DURATION_MS, function()
            logMessage("extractAudioChunk callback executed.")
            transcribeAudio(current_time, function()
                logMessage("transcribeAudio callback executed.")
                -- Advance current time
                current_time = current_time + CHUNK_DURATION_MS
                -- Schedule next chunk
                if running then
                    mp.add_timeout(1.0, loop) -- Increased delay to ensure transcription completes before next chunk
                end
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
        running = false
        mp.commandv('show-text', 'Whisper subtitles: Off')
        mp.unregister_event("start-file", start)
        mp.unregister_event("end-file", stop)
        stop()
    else
        running = true
        mp.commandv('show-text', 'Whisper subtitles: On')
        mp.register_event("start-file", start)
        mp.register_event("end-file", stop)
        start()
    end
end

-- Key binding to start the live subtitle processing
mp.add_key_binding("ctrl+alt+s", "start_live_subtitles", function()
    local media_path = mp.get_property("path")
    if not media_path then
        mp.osd_message("No media file is loaded.", 2)
        return
    end
    processLiveSubtitles(media_path)
end)

-- Key binding to stop the live subtitle processing
mp.add_key_binding("ctrl+shift+s", "stop_live_subtitles", function()
    if running then
        running = false
        mp.osd_message("Whisper Subtitles: Stopping...", 2)
        logMessage("User requested to stop Whisper subtitles.")
    else
        mp.osd_message("Whisper Subtitles: Not running.", 2)
    end
end)

-- Key binding to toggle the live subtitle processing
mp.add_key_binding('ctrl+w', 'whisper_subs_toggle', toggle)
