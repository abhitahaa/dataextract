# Prompt the user for the date parameters
$year = Read-Host "Enter the year (YYYY)"
$month = Read-Host "Enter the month (MM)"
$day = Read-Host "Enter the day (DD)"

# Construct the date string parameter for the file name
$currentDateString = "-EventLog-$year$month$day-*"

# Calculate the next day's date
$currentDate = Get-Date "$year-$month-$day"
$nextDate = $currentDate.AddDays(1)

# Extract the year, month, and day for the next day
$nextYear = $nextDate.ToString("yyyy")
$nextMonth = $nextDate.ToString("MM")
$nextDay = $nextDate.ToString("dd")

# Construct the date string parameter for the next day
$nextDateString = "-EventLog-$nextYear$nextMonth$nextDay-*"

# Defining the remote server details
$remotePath1 = "\\Logs\POS\A-01"
$remotePath2 = "\\Logs\POS\B-01"

# Dynamically generate the local paths based on the current user
$baseLocalPath = "$env:USERPROFILE\Desktop\Bosfiles"
$localPath1 = "$baseLocalPath\A-01"
$localPath2 = "$baseLocalPath\B-01"
$combinedFileDir = "$baseLocalPath\POSLOG_$year$month$day"
$combinedFilePath = Join-Path -Path $combinedFileDir -ChildPath "BosLogs$day$month$year.txt"
$pythonScriptPath = "C:\Python27\csvconversionscript\ConvertToCSV.py"
$pythonExecutable = "C:\Python27\python.exe"

# Added new line for 0080
$filteredLogFilePath = "$combinedFileDir\0080_$year$month$day.txt"
$outputFilePath = "$combinedFileDir\2080_$year$month$day.txt"

# Function to check if files exist in the remote path for the specific date
function Check-FilesExist {
    param (
        [string] $remotePath,
        [string] $datePattern
    )
    
    $files = Get-ChildItem -Path $remotePath -Filter $datePattern -Recurse
    return $files.Count -gt 0
}

# Check if the files exist in both the remote paths for both dates
$filesInRemotePath1 = Check-FilesExist -remotePath $remotePath1 -datePattern $currentDateString
$filesInRemotePath2 = Check-FilesExist -remotePath $remotePath2 -datePattern $currentDateString

# Additional checks for the next day's files
$nextFilesInRemotePath1 = Check-FilesExist -remotePath $remotePath1 -datePattern $nextDateString
$nextFilesInRemotePath2 = Check-FilesExist -remotePath $remotePath2 -datePattern $nextDateString

# If files do not exist in either path for both dates, exit the script
if (-not $filesInRemotePath1 -and -not $filesInRemotePath2 -and -not $nextFilesInRemotePath1 -and -not $nextFilesInRemotePath2) {
    Write-Host "No files found in both remote paths for the specified date or the next day. Exiting now."
    exit
}

# Function to clean a directory if files are already present
function Clean-Folder {
    param (
        [string] $folderPath
    )
    if (Test-Path -Path $folderPath) {
        # Check if the folder contains files
        if ((Get-ChildItem -Path $folderPath | Measure-Object).Count -gt 0) {
            Write-Host "Cleaning existing files in the $folderPath....."
            Remove-Item -Path "$folderPath\*" -Recurse -Force
        }
    } else {
        New-Item -Path $folderPath -ItemType Directory
    }
}

# Clean folders before copying new files 
Clean-Folder -folderPath $localPath1
Clean-Folder -folderPath $localPath2
Clean-Folder -folderPath $combinedFileDir

$filesCopiedFromRemotePath1 = @()
$filesCopiedFromRemotePath2 = @()

# Function to copy, unzip and list files from a remote path
function Copy-Files {
    param(
        [string]$remotePath,
        [string]$localPath,
        [ref]$filesCopiedList,
        [string]$datePattern
    )        

    # Test if the path exists
    if (Test-Path -Path $remotePath) {
        Write-Host "Connection to $remotePath successful" 

        # Get the list of .zip files 
        $filesToCopy = Get-ChildItem -Path $remotePath -Filter "$datePattern.zip" -Recurse
        
        if ($filesToCopy.Count -eq 0) {
            Write-Host "No Zip files found in $remotePath for the specific date"
        } else {
            Write-Host "The following files were found for $remotePath"
            foreach ($file in $filesToCopy) {
                Write-Host $file.Name
                $destination = Join-Path -Path $localPath -ChildPath $file.Name
                Copy-Item -Path $file.FullName -Destination $destination
                # Add file to the copied files list
                $filesCopiedList.Value += $file.Name
            }
        }
    } else {
        Write-Host "Failed to connect to the path"
    }
}

# Copy files for current day
Write-Host "Copy files from $remotePath1 for current day"
Copy-Files -remotePath $remotePath1 -localPath $localPath1 -filesCopiedList ([ref]$filesCopiedFromRemotePath1) -datePattern $currentDateString

Write-Host "Copy files from $remotePath2 for current day"
Copy-Files -remotePath $remotePath2 -localPath $localPath2 -filesCopiedList ([ref]$filesCopiedFromRemotePath2) -datePattern $currentDateString

# Copy files for next day
Write-Host "Copy files from $remotePath1 for next day"
Copy-Files -remotePath $remotePath1 -localPath $localPath1 -filesCopiedList ([ref]$filesCopiedFromRemotePath1) -datePattern $nextDateString

Write-Host "Copy files from $remotePath2 for next day"
Copy-Files -remotePath $remotePath2 -localPath $localPath2 -filesCopiedList ([ref]$filesCopiedFromRemotePath2) -datePattern $nextDateString

function Unzip-Files {
    param ( 
        [string]$localPath
    )
    foreach ($file in Get-ChildItem -Path $localPath -Filter "*.zip") {
        $unzipDestination = Join-Path -Path $localPath -ChildPath ($file.BaseName)
        Expand-Archive -Path $file.FullName -DestinationPath $unzipDestination
        Write-Host "Unzipped $($file.Name) to $unzipDestination"
    }
}

Unzip-Files -localPath $localPath1
Unzip-Files -localPath $localPath2

# Combine the contents of all unzipped files from both the locations into one file 
Get-ChildItem -Path $localPath1, $localPath2 -Recurse -Filter "*.txt" | ForEach-Object {
    Get-Content $_.FullName | Add-Content $combinedFilePath
}

Write-Host "All Files have been unzipped and combined into $combinedFilePath"

# Filtered line 
Write-Host "Parsing loglines which contain only 0080 logs"
$searchPattern = "\(L\s+P\s+R\)"
$filteredLines = Select-String -Path $combinedFilePath -Pattern $searchPattern | ForEach-Object { $_.Line } 

# Saving the new files
$filteredLines | Out-File -Filepath $filteredLogFilePath -Encoding UTF8
Write-Host "Logs containing only have been copied to $filteredLogFilePath"

Write-Host "Calling Python Script to convert files to CSV"
# Calling python script
& $pythonExecutable $pythonScriptPath $outputFilePath $combinedFileDir $year $month $day
