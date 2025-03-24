"""
check_file.py
Verify if a JSON file is valid
"""

import json
import sys

def check_json_file(file_path):
    try:
        with open(file_path, 'r', encoding='utf-16') as f:
            json.load(f)
    except ValueError as e:
        print(f"Invalid JSON file: {e}")
        sys.exit(1)
    except FileNotFoundError as e:
        print(f"File not found: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    print("Valid JSON file")

if __name__ == "__main__":
    # Check if the correct number of arguments is provided
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <json_file>")
        sys.exit(1)
    
    # Call the function with the provided file path
    check_json_file(sys.argv[1])
