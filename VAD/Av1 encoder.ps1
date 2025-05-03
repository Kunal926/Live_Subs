Add-Type -AssemblyName System.Windows.Forms

# Prompt the user to select an input folder
$inputFolder = [System.Windows.Forms.FolderBrowserDialog]::new()
$inputFolder.Description = "Select the input folder containing MKV files"
$inputFolder.ShowNewFolderButton = $false

if ($inputFolder.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $inputPath = $inputFolder.SelectedPath
    Write-Host "Selected input folder: $inputPath"
} else {
    Write-Host "No folder selected. Exiting..."
    exit
}

# Set the output directory
$outputPath = "C:\Users\chahe\Downloads\Av1 testing"

# Create the output directory if it doesn't exist
if (-not (Test-Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath
}

# Loop through all .mkv files in the input directory
Get-ChildItem -Path $inputPath -Filter *.mkv | ForEach-Object {
    $inputFile = $_.FullName
    $outputFile = Join-Path -Path $outputPath -ChildPath "$($_.BaseName).mkv"

    Write-Host "Processing '$inputFile' to '$outputFile'..."
    & ffmpeg -i "$inputFile" -c:v libsvtav1 -preset 5 -crf 28 -pix_fmt yuv420p10le -c:a libopus -b:a 128k "$outputFile"
}

Write-Host "All files processed."
