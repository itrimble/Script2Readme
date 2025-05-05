#!/bin/bash

# script2readme_beautiful2.sh - Generate README from script using Ollama API

# Check for required dependencies
for cmd in jq bc curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

# Default settings
MODEL="codellama:7b"
OLLAMA_API="http://localhost:11434/api/chat"
TEMP_JSON="/tmp/script2readme_payload.json"

# Function to estimate completion time
estimate_completion_time() {
    local script_size="$1"
    local complexity="$2"
    local base_time=5  # Base time in seconds

    # Debug: Print variables
    echo "Debug: script_size=$script_size, complexity=$complexity"

    # Use bc for floating-point calculations
    local size_factor=$(echo "scale=2; ($script_size / 1024) ^ 0.7" | bc)
    local estimate=$(echo "scale=0; $base_time * $size_factor * $complexity / 1" | bc)
    echo "$estimate"
}

# Function to generate README
generate_readme() {
    local script_file="$1"
    local script_size=$(wc -c < "$script_file")
    local complexity=1  # Simplified complexity factor

    # Read script content
    CONTENT=$(cat "$script_file")
    script_basename=$(basename "$script_file")
    
    # Determine script type
    case "$script_file" in
        *.sh) SCRIPT_TYPE="bash" ;;
        *.py) SCRIPT_TYPE="python" ;;
        *.applescript) SCRIPT_TYPE="applescript" ;;
        *) SCRIPT_TYPE="unknown" ;;
    esac

    # Escape content for JSON
    local content_escaped=$(echo "$CONTENT" | jq -sR .)

    # Create JSON payload
    local payload=$(jq -n \
        --arg model "${MODEL}" \
        --argjson content "$content_escaped" \
        --arg filename "${script_basename}" \
        --arg script_type "${SCRIPT_TYPE}" \
        '{
          "model": $model,
          "messages": [
            {
              "role": "system",
              "content": "You are an expert code documentarian..."
            },
            {
              "role": "user",
              "content": "Analyze the following " + $script_type + " script...\n\nScript Content:\n" + $content
            }
          ],
          "stream": false
        }')

    # Save and validate JSON payload
    echo "$payload" > "$TEMP_JSON"
    if ! jq . "$TEMP_JSON" > /dev/null 2>&1; then
        echo "Invalid JSON payload:"
        cat "$TEMP_JSON"
        exit 1
    fi

    # Estimate and display completion time
    local estimated_time=$(estimate_completion_time "$script_size" "$complexity")
    echo "Estimated completion time: ${estimated_time} seconds"

    # Send request to Ollama API
    response=$(curl -s -X POST "$OLLAMA_API" \
        -H "Content-Type: application/json" \
        -d @"$TEMP_JSON")

    # Extract and display README content
    echo "$response" | jq -r '.message.content'
}

# Main execution
if [ $# -ne 1 ]; then
    echo "Usage: $0 <script_file>"
    exit 1
fi

SCRIPT_FILE="$1"
if [ ! -f "$SCRIPT_FILE" ]; then
    echo "Error: File '$SCRIPT_FILE' not found."
    exit 1
fi

echo "Generating README for $SCRIPT_FILE..."
generate_readme "$SCRIPT_FILE"

# Cleanup
rm -f "$TEMP_JSON"