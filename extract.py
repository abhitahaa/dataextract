import re
import sys
import csv

# Get the input 2080 file name from the command-line arguments
if len(sys.argv) < 2:
    print("Usage: python script.py <input_2080_file>")
    sys.exit(1)

input_2080_file = sys.argv[1]  # Input 2080 file name passed from PowerShell
temp_txt_file = "temp_data.txt"  # Temporary text file with | delimiter
output_csv_file = "output_data.csv"  # Final CSV file

# Define the keys to extract from each log line
keys_to_extract = [
    
]

# Define the regex pattern for date extraction
date_pattern = r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{4}'

# Prepare to store data
all_data = []

# Open the input 2080 file and process each line
with open(input_2080_file, 'r') as infile:
    for line in infile:
        date_match = re.match(date_pattern, line)
        if not date_match:
            continue

        date = date_match.group(0)  # Extract the date
        log_entry = {"Date": date}

        for key in keys_to_extract:
            key_pattern = r"<{}=([^>]+)>".format(re.escape(key))
            match = re.search(key_pattern, line)
            if match:
                log_entry[key] = match.group(1)

        # Include only records that have all keys
        if all(key in log_entry for key in keys_to_extract):
            all_data.append(log_entry)

# Write the data to the temporary text file with | as the delimiter
with open(temp_txt_file, 'w') as outfile:
    for record in all_data:
        line = '|'.join([record.get(key, '') for key in ['Date'] + keys_to_extract])
        outfile.write(line + '\n')

# Convert the text file to CSV
with open(temp_txt_file, 'r') as infile, open(output_csv_file, 'w', newline='') as outfile:
    csv_writer = csv.writer(outfile)
    csv_writer.writerow(['Date'] + keys_to_extract)
    for line in infile:
        csv_writer.writerow(line.strip().split('|'))

print(f"CSV conversion complete. {len(all_data)} records processed.")
