#!/bin/zsh

# Enable debug mode
set -x

# Check if running in a terminal
if [ -t 0 ]; then
  echo "Running in a terminal."
else
  echo "Not running in a terminal. Using default model selection."
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required. Please install jq (e.g., 'brew install jq')."
  exit 1
fi

# Check if ollama is installed
if ! command -v ollama &> /dev/null; then
  echo "Error: ollama is required. Please install Ollama."
  exit 1
fi

# Input handling
if [ $# -lt 1 ]; then
  echo "Usage: $0 <input_file> [model]"
  exit 1
fi

INPUT="$1"
echo "Input file: $INPUT"

# Model selection
echo "Running ollama list..."
ollama_output=$(ollama list 2>/dev/null)
if [ $? -ne 0 ]; then
  echo "Error: Failed to run 'ollama list'. Ensure Ollama is running."
  exit 1
fi

models=($(echo "$ollama_output" | tail -n +2 | awk '{print $1}'))
if [ ${#models[@]} -eq 0 ]; then
  echo "No models found. Please download a model using 'ollama pull <model>'."
  exit 1
fi

echo "Available models: ${models[@]}"

# If a model is provided as an argument, use it; otherwise, prompt or default
if [ $# -eq 2 ]; then
  provided_model="$2"
  if [[ " ${models[@]} " =~ " ${provided_model} " ]]; then
    model="$provided_model"
  else
    echo "Model '$provided_model' not found in available models: ${models[@]}"
    exit 1
  fi
elif [ -t 0 ]; then
  # Interactive selection if terminal is available
  echo "Select a model:"
  select model in "${models[@]}"; do
    if [ -n "$model" ]; then
      break
    fi
  done
else
  # Non-interactive: default to the first model
  echo "No terminal available for interactive selection. Defaulting to first model: ${models[1]}"  # zsh arrays are 1-indexed
  model="${models[1]}"
fi

echo "Selected model: $model"

# Proceed with the rest of the script
EXT="${INPUT##*.}"
README="$(dirname "$INPUT")/README.md"
OLLAMA_API="http://localhost:11434/api/chat"

# Validate input file
if [ ! -f "$INPUT" ]; then
  echo "Error: Input file '$INPUT' does not exist."
  exit 1
fi

# Check supported file types
case "$EXT" in
  sh)
    # Read content and check if it's base64
    CONTENT=$(cat "$INPUT")
    if echo "$CONTENT" | grep -qE '^[A-Za-z0-9+/=]+$'; then
      # Attempt to decode as base64
      DECODED_CONTENT=$(echo "$CONTENT" | base64 -d 2>/dev/null)
      if [ $? -eq 0 ] && echo "$DECODED_CONTENT" | grep -qE "^#!/bin/(bash|zsh|sh)"; then
        CONTENT="$DECODED_CONTENT"
        echo "Input detected as base64-encoded shell script. Decoded successfully."
      else
        echo "Input appears to be base64 but failed to decode as a valid shell script. Treating as plain text."
      fi
    fi
    # Validate content as a shell script
    if ! echo "$CONTENT" | grep -qE "^#!/bin/(bash|zsh|sh)"; then
      echo "Error: Input does not appear to be a valid shell script (missing shebang)."
      exit 1
    fi
    SCRIPT_TYPE="shell"
    ;;
  scpt)
    # Read content for AppleScript
    CONTENT=$(cat "$INPUT")
    SCRIPT_TYPE="applescript"
    ;;
  *)
    echo "Unsupported file type: $EXT"
    exit 1
    ;;
esac

# Create a temporary JSON file for the request
TEMP_JSON=$(mktemp)

# Construct JSON payload with enhanced prompt using jq
jq -n --arg model "$model" --arg content "$CONTENT" --arg filename "$(basename "$INPUT")" --arg script_type "$SCRIPT_TYPE" '
{
  "model": $model,
  "messages": [
    {
      "role": "system",
      "content": "You are an expert code analyst tasked with producing professional, accurate, and comprehensive documentation at the level of an advanced AI like Grok3. Analyze the provided macOS \($script_type) script with precision, describing only the functionality explicitly present in the code. Do not invent features, assume unstated behaviors, or add speculative commentary. Generate a detailed Markdown README section that is clear, thorough, and professionally structured, suitable for developers and end-users."
    },
    {
      "role": "user",
      "content": "Analyze the following macOS \($script_type) script provided as plain text. Pay close attention to macOS-specific elements such as references to applications (e.g., Stickies, Finder), system paths (e.g., /Library, ~/Library, /System), command-line tools (e.g., defaults, osascript for shell scripts; tell blocks for AppleScript), and any variables, loops, or conditional logic. Consider the script's potential impact on the system, such as file modifications or application interactions.\n\nGenerate a Markdown README section with these sections:\n\n- **Overview**: Summarize the script's purpose and primary actions based solely on its code.\n- **Requirements**: List prerequisites (e.g., macOS version, permissions, tools like bash, zsh, or AppleScript dependencies) inferred from the script.\n- **Usage**: Provide precise instructions for running the script, including any arguments or environment setup from the code.\n- **What the Script Does**: Describe the script's operations step-by-step, explaining each command or block as it appears in the code.\n- **Important Notes**: Highlight critical details (e.g., file backups, system changes, error handling) derived from the script.\n- **Disclaimer**: Warn about risks of running the script, such as unintended system modifications.\n\nEnsure your analysis is exhaustive yet concise, focusing on clarity and fidelity to the script's content. Avoid assumptions about functionality not present in the code.\n\nFile: \($filename)\n\nScript Content:\n\($content)"
    }
  ],
  "stream": false
}
' > "$TEMP_JSON"

# Send the request to Ollama API
echo "Sending request to Ollama API..."
RAW_RESPONSE=$(curl -s -X POST "$OLLAMA_API" \
  -H "Content-Type: application/json" \
  -d @"$TEMP_JSON")

# Remove the temporary file
rm "$TEMP_JSON"

# Check if curl failed
if [ $? -ne 0 ]; then
  echo "Error: Failed to connect to Ollama API at $OLLAMA_API. Ensure Ollama is running and the model '$model' is available."
  exit 1
fi

# Debug output
echo "OLLAMA RAW RESPONSE LENGTH: $(echo "$RAW_RESPONSE" | wc -c) bytes"
echo "First 100 chars: $(echo "$RAW_RESPONSE" | head -c 100)"

# Check for error in response
if echo "$RAW_RESPONSE" | grep -q "error"; then
  echo "Error in Ollama response: $RAW_RESPONSE"
  exit 1
fi

# Extract content using jq
RESPONSE=$(echo "$RAW_RESPONSE" | jq -r '.message.content')
if [[ $? -ne 0 || -z "$RESPONSE" || "$RESPONSE" == "null" ]]; then
  echo "Error: Failed to extract valid response content from Ollama."
  echo "Raw response: $RAW_RESPONSE"
  exit 1
fi

# Append to README.md with license section
{
  echo -e "\n## $(basename "$INPUT") (Model: $model, Time: $(date))\n$RESPONSE\n"
  echo -e "### License\nThis script is provided under the MIT License.\n"
  echo -e "MIT License\n\nCopyright (c) $(date +%Y)\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
} >> "$README"

echo "README.md updated for $(basename "$INPUT")"