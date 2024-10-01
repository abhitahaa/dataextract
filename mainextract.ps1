
#Prompt the user for the date parameters
$year = Read-Host "Enter the year(YYYY)"
$month = Read-Host "Enter the month(MM)"
$day = Read-Host "Enter the day(DD)"

# Construct the date string parameter for the file name

$dateString = "-EventLog-$year$month$day-*"

# Defining the remote server details

$remotePath1 = "\\\\Logs\\POS\A-01"
$remotePath2 = "\\\\Logs\\POS\B-01"

# Dynamically genereate the local paths based on current user
$baseLocalPath = "$env:USERPROFILE\Desktop\Bosfiles"
$localPath1 = "$baseLocalPath\A-01"
$localPath2 = "$baseLocalPath\B-01"
$combinedFileDir = "$baseLocalPath\POSLOG_$year$month$day"
$combinedFilePath = Join-Path -Path $combinedFileDir -ChildPath "BosLogs$day$month$year.txt"
$pythonScriptPath = "C:\Python27\csvconversionscript\ConvertToCSV.py"
$pythonExecutable = "C:\Python27\python.exe"

#Added new line for 0080
$filteredLogFilePath = "$combinedFileDir\0080_$year$month$day.txt"
$outputFilePath = "$combinedFileDir\2080_$year$month$day.txt"

# Function to check if files exist in the remote path for the specific date

function Check-FilesExist {
	param (
		[string] $remotePath
	)
	
	$files = Get-ChildItem -Path $remotePath -Filter "$dateString.zip" -Recurse
	return $files.Count -gt 0
}
	
#Check if the files exist in both the remote paths before proceeding
$filesInRemotePath1 = Check-FilesExist -remotePath $remotePath1
$filesInRemotePath2 = Check-FilesExist -remotePath $remotePath2

if (-not $filesInRemotePath1 -and -not $filesCopiedFromRemotePath2) {
	Write-Host "No files found in both remote paths for the specified date. Exiting now"
	exit
}

	
# Function to clean a directory if files are already present
function Clean-Folder {
	param (
		[string] $folderPath
	)
	if (Test-Path -Path $folderPath) {
		#Check if the folder contains files
		if ((Get-ChildItem -Path $folderPath | Measure-Object).Count -gt 0) {
			Write-Host "Cleaning existing files in the $folderPath....."
			Remove-Item -Path "$folderPath\*" -Recurse -Force
		}
	} else {
		New-Item -Path $folderPath -ItemType Directory
	}
}

#Clean folders before copying new files 
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
		[ref]$filesCopiedList
	)		


#Test if the path exist

if (Test-Path -Path $remotePath) {
	Write-Host "Connection to $remotePath successful" 

	# Get the list of .zip files 
	$filesToCopy = Get-ChildItem -Path $remotePath -Filter "$dateString.zip" -Recurse
	
	
	if ($filesToCopy.Count -eq 0) {
		Write-Host "No Zip files found in $remotePath for the specific date"
	}
	else {
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


# Copy, unzip and list files from both the remote paths

Write-Host "Copy files from $remotePath1"
Copy-Files -remotePath $remotePath1 -localPath $localPath1 -filesCopiedList ([ref]$filesCopiedFromRemotePath1)

Write-Host "Copy files from $remotePath2"
Copy-Files -remotePath $remotePath2 -localPath $localPath2 -filesCopiedList ([ref]$filesCopiedFromRemotePath2)


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

#filtered line 
Write-Host "Parsing loglines which contain only 0080 logs"

$searchPattern = "\(L\s+P\s+R\)"

$filteredLines = Select-String -Path $combinedFilePath -Pattern $searchPattern | ForEach-Object { $_.Line } 

#saving the new files
$filteredLines | Out-File -Filepath $filteredLogFilePath -Encoding UTF8

Write-Host "Logs containing only have been copied to $filteredLogFilePath"

Write-Host "Calling Python Script to convert files to csv"

#Calling python script##
& $pythonExecutable $pythonScriptPath $outputFilePath $combinedFileDir $year $month $day
