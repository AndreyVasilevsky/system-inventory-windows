import json
import os
import sys
import logging
from maestro_api_models.models.data.system.model import SystemModel
from maestro_api_models.models.request_response.add_update.model import AddUpdateRequest

# Configure logging
logging.basicConfig(filename='data_restore.log', level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def validate_and_load_json(source_file):
    # Check if file exists and has content
    if not os.path.exists(source_file):
        print(f"Error: File '{source_file}' does not exist")
        sys.exit(1)
        
    if os.path.getsize(source_file) == 0:
        print(f"Error: File '{source_file}' is empty")
        sys.exit(1)
    
    # Print first few bytes to check for BOM or other invisible characters
    with open(source_file, 'rb') as file:
        first_bytes = file.read(10)
        print(f"First bytes (hex): {first_bytes.hex()}")
    
    # Try to read and parse the JSON file
    try:
        with open(source_file, 'r', encoding='utf-16') as file:
            content = file.read()
            print(f"File content starts with: {content[:50]}...")
            
            try:
                data = json.loads(content)
                print("JSON parsed successfully!")
                return data
            except json.JSONDecodeError as e:
                print(f"JSON parsing error: {e}")
                print(f"Error at position {e.pos}, near: '{content[max(0, e.pos-20):e.pos+20]}'")
                sys.exit(1)
    except Exception as e:
        print(f"File reading error: {e}")
        sys.exit(1)

def main(source_file):
    # Validate and load the JSON file
    data = validate_and_load_json(source_file)
    
    # Load the JSON data into the AddUpdateRequest pydantic model
    try:
        response = AddUpdateRequest.model_validate(data)
        logging.info("Data loaded successfully")
        print("Data loaded into AddUpdateRequest model successfully!")
        print(response)
    except Exception as e:
        logging.error(f"Error validating data against AddUpdateRequest model: {e}")
        print(f"Error validating data against AddUpdateRequest model: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Check if the correct number of arguments is provided
    if len(sys.argv) != 2:
        print(f"Usage: python {sys.argv[0]} <json_file>")
        sys.exit(1)
    
    # Call the main function with the provided file path
    main(sys.argv[1])