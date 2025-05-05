#!/bin/zsh
#
# script2readme.sh - Generate README documentation from scripts using Ollama models
# Author: Ian Trimble
# Created: April 28, 2025
# Version: 1.2.0
#

# Enable debug mode only when explicitly requested
if [[ "$1" == "--debug" ]]; then
  set -x
  shift
fi

# =================== COLORS AND FORMATTING ===================
# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
REVERSE='\033[7m'
RESET='\033[0m'

# Color gradients for progress bar
declare -a GRADIENT
GRADIENT=(
  '\033[38;5;27m' '\033[38;5;33m' '\033[38;5;39m' '\033[38;5;45m' '\033[38;5;51m'
  '\033[38;5;50m' '\033[38;5;49m' '\033[38;5;48m' '\033[38;5;47m' '\033[38;5;46m'
)

# Check if terminal supports colors
if [ -t 1 ]; then
  COLORTERM=1
else
  COLORTERM=0
  # Reset all color variables to empty strings
  RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' GRAY=''
  BOLD='' DIM='' UNDERLINE='' BLINK='' REVERSE='' RESET=''
  for i in {0..9}; do GRADIENT[$i]=''; done
fi

# =================== CONFIGURATION ===================
# App information
APP_NAME="Script to README Generator"
APP_VERSION="1.2.0"
APP_AUTHOR="Ian Trimble"

# Directory structure
BENCHMARK_DIR="${HOME}/ollama_benchmarks"
SESSION_ID=$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)
BENCHMARK_LOG="${BENCHMARK_DIR}/benchmark_log.csv"
METRICS_LOG="${BENCHMARK_DIR}/metrics_${SESSION_ID}.json"
CHANGELOG="${BENCHMARK_DIR}/changelog.md"
README="$(pwd)/README.md"
OLLAMA_API="http://localhost:11434/api/chat"
TEMPLATE_DIR="${HOME}/.script2readme/templates"
CONFIG_FILE="${HOME}/.script2readme/config.json"

# Default model (can be overridden)
DEFAULT_MODEL="qwen2.5:1.5b"

# Sound effects (if enabled)
SOUND_ENABLED=0
SOUND_COMPLETE="afplay /System/Library/Sounds/Glass.aiff"
SOUND_ERROR="afplay /System/Library/Sounds/Sosumi.aiff"

# Model complexity factors (for time estimation)
declare -A MODEL_COMPLEXITY
MODEL_COMPLEXITY["qwen2.5:1.5b"]=1.0
MODEL_COMPLEXITY["qwen2.5-coder:7b"]=3.5
MODEL_COMPLEXITY["deepseek-coder:6.7b"]=3.0
MODEL_COMPLEXITY["codellama:7b"]=3.0
MODEL_COMPLEXITY["codellama:13b"]=5.5
# Default for unknown models
MODEL_COMPLEXITY["default"]=2.5

# Did you know tips
declare -a TIPS
TIPS=(
  "You can create custom templates in ${TEMPLATE_DIR}."
  "Use the --watch flag to automatically process scripts as they're added to a directory."
  "Different models have different strengths - smaller models are faster, larger ones more detailed."
  "The --batch flag lets you process multiple scripts at once."
  "Your benchmarks are saved to ${BENCHMARK_DIR} for performance analysis."
  "You can use --export to generate HTML or PDF documentation from your README."
  "The --interactive mode lets you edit the AI-generated content before it's saved."
  "Set your preferred default model in ${CONFIG_FILE}."
  "Good documentation can reduce project onboarding time by up to 60%."
  "Use --update to refresh documentation while preserving your custom edits."
)

# Create required directories
mkdir -p "${BENCHMARK_DIR}"
mkdir -p "${TEMPLATE_DIR}"
mkdir -p "$(dirname "${CONFIG_FILE}")"

# Create default config if it doesn't exist
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "{\"default_model\": \"${DEFAULT_MODEL}\", \"sound_enabled\": false, \"template\": \"default\"}" > "${CONFIG_FILE}"
fi

# Load config if it exists
if [ -f "${CONFIG_FILE}" ]; then
  if command -v jq &> /dev/null; then
    DEFAULT_MODEL=$(jq -r '.default_model // "qwen2.5:1.5b"' "${CONFIG_FILE}")
    SOUND_ENABLED=$(jq -r '.sound_enabled // false' "${CONFIG_FILE}")
    if [[ "${SOUND_ENABLED}" == "true" ]]; then
      SOUND_ENABLED=1
    else
      SOUND_ENABLED=0
    fi
  fi
fi

# Initialize benchmark file if it doesn't exist
if [ ! -f "${BENCHMARK_LOG}" ]; then
  echo "timestamp,session_id,script_name,script_size_bytes,script_lines,script_chars,model,operation,duration,tokens,cpu_usage,memory_usage" > "${BENCHMARK_LOG}"
fi

# Initialize changelog if it doesn't exist
if [ ! -f "${CHANGELOG}" ]; then
  {
    echo "# Script to README Generator Changelog"
    echo ""
    echo "## Version 1.2.0 - $(date '+%Y-%m-%d')"
    echo "- Initial release"
    echo "- Added colorful UI and improved user experience"
    echo "- Added watch mode for automatic processing"
    echo "- Added batch processing for multiple files"
    echo "- Added interactive mode for editing AI responses"
    echo "- Added benchmarking capabilities"
    echo "- Added time estimation feature"
  } > "${CHANGELOG}"
else
  # Check if version entry exists, add if not
  if ! grep -q "## Version ${APP_VERSION}" "${CHANGELOG}"; then
    sed -i '' "1a\\
\\
## Version ${APP_VERSION} - $(date '+%Y-%m-%d')\\
- Added colorful user interface\\
- Added file watching capability\\
- Added interactive editing mode\\
- Added batch processing\\
- Enhanced error handling\\
- Added tips and help system
" "${CHANGELOG}"
  fi
fi

# Initialize metrics JSON log
echo "{\"session_id\": \"${SESSION_ID}\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"app_version\": \"${APP_VERSION}\", \"metrics\": []}" > "${METRICS_LOG}"

# =================== HELPER FUNCTIONS ===================
# Function to show the app logo
show_logo() {
  clear
  echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║                                                      ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}███████╗${GREEN}██████╗${CYAN} ██████╗${YELLOW}███████╗${RED}██████╗ ${MAGENTA}███████╗${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}██╔════╝${GREEN}██╔══██╗${CYAN}██╔════╝${YELLOW}██╔════╝${RED}██╔══██╗${MAGENTA}██╔════╝${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}███████╗${GREEN}██████╔╝${CYAN}██║     ${YELLOW}█████╗  ${RED}██████╔╝${MAGENTA}█████╗  ${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}╚════██║${GREEN}██╔══██╗${CYAN}██║     ${YELLOW}██╔══╝  ${RED}██╔══██╗${MAGENTA}██╔══╝  ${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}███████║${GREEN}██║  ██║${CYAN}╚██████╗${YELLOW}███████╗${RED}██║  ██║${MAGENTA}███████╗${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}╚══════╝${GREEN}╚═╝  ╚═╝${CYAN} ╚═════╝${YELLOW}╚══════╝${RED}╚═╝  ╚═╝${MAGENTA}╚══════╝${BLUE}  ║${RESET}"
  echo -e "${BLUE}║                                                      ║${RESET}"
  echo -e "${BLUE}║  ${CYAN}Script to README Generator ${WHITE}v${APP_VERSION}              ${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${GRAY}By ${APP_AUTHOR}                                    ${BLUE}  ║${RESET}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

# Function to show a random tip
show_tip() {
  local tip_index=$((RANDOM % ${#TIPS[@]}))
  local tip="${TIPS[$tip_index]}"
  echo -e "\n${YELLOW}💡 ${BOLD}Did you know?${RESET} ${tip}${RESET}\n"
}

# Function to log messages with different levels
log_message() {
  local level=$1
  local message=$2
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  case ${level} in
    "INFO")
      echo -e "${BLUE}[${timestamp}] ℹ️  ${RESET}${message}"
      ;;
    "SUCCESS")
      echo -e "${GREEN}[${timestamp}] ✅ ${BOLD}${message}${RESET}"
      ;;
    "WARNING")
      echo -e "${YELLOW}[${timestamp}] ⚠️  ${BOLD}${message}${RESET}"
      ;;
    "ERROR")
      echo -e "${RED}[${timestamp}] ❌ ${BOLD}${message}${RESET}"
      ;;
    "DEBUG")
      if [[ "$1" == "--debug" ]]; then
        echo -e "${GRAY}[${timestamp}] 🔍 ${message}${RESET}"
      fi
      ;;
    *)
      echo -e "[${timestamp}] ${message}"
      ;;
  esac
}

# Function to play sounds if enabled
play_sound() {
  local sound_type=$1
  
  if [ ${SOUND_ENABLED} -eq 1 ]; then
    case ${sound_type} in
      "complete")
        eval ${SOUND_COMPLETE} &> /dev/null &
        ;;
      "error")
        eval ${SOUND_ERROR} &> /dev/null &
        ;;
    esac
  fi
}

# Function to display an animated spinner
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  
  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?}
    printf " %c  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# Function to display progress
display_progress() {
  local progress=$1
  local duration=$2
  local width=40
  local filled=$((width * progress / 100))
  local empty=$((width - filled))
  local bar=""
  
  # Create gradient filled part
  for ((i = 0; i < filled; i++)); do
    local color_index=$((i * 10 / width))
    bar="${bar}${GRADIENT[$color_index]}█"
  done
  
  # Create empty part
  for ((i = 0; i < empty; i++)); do
    bar="${bar}${GRAY}░"
  done
  
  # Print the bar
  printf "\r${WHITE}[${RESET}${bar}${RESET}${WHITE}]${RESET} ${BOLD}%3d%%${RESET} ${WHITE}(${CYAN}%s${WHITE})${RESET}" $progress "$duration"
}

# Function to format time in human-readable format
format_time() {
  local seconds=$1
  local minutes=$((seconds / 60))
  local remaining_seconds=$((seconds % 60))
  
  if [ $minutes -gt 0 ]; then
    echo "${minutes}m ${remaining_seconds}s"
  else
    echo "${seconds}s"
  fi
}

# Function to estimate completion time
estimate_completion_time() {
  local script_size=$1
  local model=$2
  
  # Get model complexity factor
  local complexity=${MODEL_COMPLEXITY[$model]}
  if [ -z "$complexity" ]; then
    complexity=${MODEL_COMPLEXITY["default"]}
  fi
  
  # Base time in seconds per KB for a standard model
  local base_time=3
  
  # Adjust based on script size (larger scripts may take disproportionately longer)
  local size_factor=$(printf "%.2f" $(echo "scale=2; ($script_size / 1024) ^ 0.7" | bc))
  
  # Calculate estimated seconds
  local estimate=$(printf "%.0f" $(echo "scale=0; $base_time * $size_factor * $complexity" | bc))
  
  # Ensure minimum reasonable time
  if [ $estimate -lt 10 ]; then
    estimate=10
  fi
  
  echo $estimate
}

# Function to display usage information
show_usage() {
  echo -e "${CYAN}${BOLD}${APP_NAME}${RESET} ${WHITE}(v${APP_VERSION})${RESET}"
  echo -e "${GRAY}Generates README documentation from script files using Ollama models${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Usage:${RESET} $0 ${GREEN}[OPTIONS]${RESET} ${MAGENTA}<input_file>${RESET} ${BLUE}[model]${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Options:${RESET}"
  echo -e "  ${GREEN}--debug${RESET}                Enable debug mode"
  echo -e "  ${GREEN}--help${RESET}                 Show this help message"
  echo -e "  ${GREEN}--list-models${RESET}          List available Ollama models"
  echo -e "  ${GREEN}--version${RESET}              Show version information"
  echo -e "  ${GREEN}--no-estimate${RESET}          Skip time estimation"
  echo -e "  ${GREEN}--no-color${RESET}             Disable colored output"
  echo -e "  ${GREEN}--sound${RESET}                Enable sound notifications"
  echo -e "  ${GREEN}--batch${RESET} ${BLUE}<pattern>${RESET}      Process multiple files matching pattern"
  echo -e "  ${GREEN}--watch${RESET} ${BLUE}<directory>${RESET}    Watch directory for new scripts and process them"
  echo -e "  ${GREEN}--template${RESET} ${BLUE}<name>${RESET}      Use specified template (default: standard)"
  echo -e "  ${GREEN}--interactive${RESET}          Edit AI-generated documentation before saving"
  echo -e "  ${GREEN}--update${RESET}               Update existing documentation preserving manual edits"
  echo -e "  ${GREEN}--export${RESET} ${BLUE}<format>${RESET}      Export documentation to specified format (html, pdf)"
  echo -e "  ${GREEN}--config${RESET}               Create or update configuration"
  echo ""
  echo -e "${YELLOW}${BOLD}Arguments:${RESET}"
  echo -e "  ${MAGENTA}<input_file>${RESET}           Path to script file to document"
  echo -e "  ${BLUE}[model]${RESET}                Optional Ollama model name (default: ${WHITE}${DEFAULT_MODEL}${RESET})"
  echo ""
  echo -e "${YELLOW}${BOLD}Examples:${RESET}"
  echo -e "  ${GRAY}$0 my_script.sh${RESET}"
  echo -e "  ${GRAY}$0 my_script.sh codellama:7b${RESET}"
  echo -e "  ${GRAY}$0 --batch \"*.sh\" --template code${RESET}"
  echo -e "  ${GRAY}$0 --watch ~/scripts --template minimal${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Output:${RESET}"
  echo -e "  - Updates README.md in the current directory with script documentation"
  echo -e "  - Logs performance metrics and benchmarks"
  echo ""
  show_tip
  exit 0
}

# Function to display version information
show_version() {
  echo -e "${CYAN}${BOLD}${APP_NAME}${RESET} ${WHITE}v${APP_VERSION}${RESET}"
  echo -e "${GRAY}Author: ${WHITE}${APP_AUTHOR}${RESET}"
  echo -e "${GRAY}Created: April 28, 2025${RESET}"
  echo -e "${GRAY}License: MIT${RESET}"
  exit 0
}

# Function to update config
update_config() {
  echo -e "${CYAN}${BOLD}Configuration Setup${RESET}"
  echo ""
  
  # Ask for default model
  echo -e "${YELLOW}Default model:${RESET} (current: ${WHITE}${DEFAULT_MODEL}${RESET})"
  read -r new_model
  if [ -z "$new_model" ]; then
    new_model="${DEFAULT_MODEL}"
  fi
  
  # Ask for sound preference
  echo -e "${YELLOW}Enable sound effects?${RESET} (y/N)"
  read -r sound_pref
  if [[ "${sound_pref}" =~ ^[Yy]$ ]]; then
    sound_enabled="true"
  else
    sound_enabled="false"
  fi
  
  # Write to config file
  echo "{\"default_model\": \"${new_model}\", \"sound_enabled\": ${sound_enabled}, \"template\": \"default\"}" > "${CONFIG_FILE}"
  
  echo -e "${GREEN}${BOLD}Configuration updated!${RESET}"
  exit 0
}

# Function to get system information
get_system_info() {
  local cpu_info=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  local memory_info=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024) " GB"}' || echo "Unknown")
  local os_info=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
  local ollama_version=$(ollama --version 2>/dev/null || echo "Unknown")
  
  # Add system info to metrics log
  jq --arg cpu "${cpu_info}" \
     --arg mem "${memory_info}" \
     --arg os "${os_info}" \
     --arg ollama "${ollama_version}" \
     '.system_info = {"cpu": $cpu, "memory": $mem, "os": $os, "ollama_version": $ollama}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  log_message "INFO" "System Info: CPU: ${cpu_info}, Memory: ${memory_info}, OS: ${os_info}, Ollama: ${ollama_version}"
}

# Function to get current resource usage
get_resource_usage() {
  local cpu_usage=$(ps -o %cpu= -p $$ | awk '{print $1}')
  local memory_usage=$(ps -o rss= -p $$ | awk '{print int($1/1024) " MB"}')
  
  echo "${cpu_usage},${memory_usage}"
}

# Function to log benchmark data
log_benchmark() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local script_name=$1
  local script_size=$2
  local script_lines=$3
  local script_chars=$4
  local model=$5
  local operation=$6
  local duration=$7
  local token_count=$8
  
  # Get resource usage
  local resource_usage=$(get_resource_usage)
  local cpu_usage=$(echo ${resource_usage} | cut -d, -f1)
  local memory_usage=$(echo ${resource_usage} | cut -d, -f2)
  
  # Log to CSV for detailed data
  echo "${timestamp},${SESSION_ID},${script_name},${script_size},${script_lines},${script_chars},${model},${operation},${duration},${token_count},${cpu_usage},${memory_usage}" >> "${BENCHMARK_LOG}"
  
  # Add metric to JSON log
  jq --arg timestamp "${timestamp}" \
     --arg script "${script_name}" \
     --arg size "${script_size}" \
     --arg lines "${script_lines}" \
     --arg chars "${script_chars}" \
     --arg model "${model}" \
     --arg op "${operation}" \
     --arg dur "${duration}" \
     --arg tokens "${token_count}" \
     --arg cpu "${cpu_usage}" \
     --arg mem "${memory_usage}" \
     '.metrics += [{"timestamp": $timestamp, "script": $script, "size_bytes": $size, "line_count": $lines, "char_count": $chars, "model": $model, "operation": $op, "duration": $dur, "token_count": $tokens, "cpu_usage": $cpu, "memory_usage": $mem}]' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Return for chaining
  echo "${operation}:${duration}"
}

# Function to generate a benchmark summary
generate_benchmark_summary() {
  local model=$1
  local script_name=$2
  local total_time=$3
  local api_time=$4
  local parse_time=$5
  local script_size=$6
  local script_lines=$7
  local script_chars=$8
  local token_count=$9
  local estimated_time=${10}
  
  echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║ ${CYAN}${BOLD}README GENERATION COMPLETE                         ${RESET}${BLUE}║${RESET}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${RESET}"
  echo -e "${BLUE}║ ${WHITE}📄 Script:${RESET} ${YELLOW}${script_name}${RESET}$(printf "%$((40-${#script_name}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}🤖 Model:${RESET} ${MAGENTA}${model}${RESET}$(printf "%$((41-${#model}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}⏱️  Total time:${RESET} ${GREEN}${total_time}s${RESET}$(printf "%$((37-${#total_time}))s" "")${BLUE}║${RESET}"
  
  if [ -n "$estimated_time" ]; then
    local accuracy=$(printf "%.1f" $(echo "scale=1; $estimated_time / $total_time * 100" | bc))
    echo -e "${BLUE}║ ${WHITE}🔮 Est. vs Actual:${RESET} ${estimated_time}s vs ${total_time}s (${accuracy}%)$(printf "%$((21-${#estimated_time}-${#total_time}-${#accuracy}))s" "")${BLUE}║${RESET}"
  fi
  
  echo -e "${BLUE}║ ${WHITE}🔄 API request time:${RESET} ${CYAN}${api_time}s${RESET}$(printf "%$((31-${#api_time}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}🔍 Response parse time:${RESET} ${CYAN}${parse_time}s${RESET}$(printf "%$((29-${#parse_time}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}📝 Response size:${RESET} ~${token_count} words$(printf "%$((33-${#token_count}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}📂 Script metrics:${RESET}$(printf "%$((35))s" "")${BLUE}║${RESET}"
  
  local kb_size=$(printf "%.2f" $(echo "scale=2; ${script_size}/1024" | bc))
  echo -e "${BLUE}║   ${GRAY}- Size: ${script_size} bytes (${kb_size} KB)${RESET}$(printf "%$((38-${#script_size}-${#kb_size}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║   ${GRAY}- Lines: ${script_lines}${RESET}$(printf "%$((43-${#script_lines}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║   ${GRAY}- Characters: ${script_chars}${RESET}$(printf "%$((37-${#script_chars}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${RESET}"
  echo -e "${BLUE}║ ${GRAY}📋 Session ID: ${DIM}${SESSION_ID}${RESET}$(printf "%$((38-${#SESSION_ID}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
}

# Function to update the changelog
update_changelog() {
  local script_name=$1
  local model=$2
  local duration=$3
  
  # Get the current date
  local today=$(date '+%Y-%m-%d')
  
  # Check if there's already an entry for today
  if grep -q "### ${today}" "${CHANGELOG}"; then
    # Append to today's entry
    sed -i '' "/### ${today}/a\\
- Generated README for ${script_name} with ${model} (${duration}s)
" "${CHANGELOG}"
  else
    # Create a new entry for today
    sed -i '' "/^## Version/a\\
\\
### ${today}\\
- Generated README for ${script_name} with ${model} (${duration}s)
" "${CHANGELOG}"
  fi
}

# Function to check if running in a terminal
is_terminal() {
  [ -t 0 ]
}

# Function to edit text interactively
edit_text() {
  local text="$1"
  local temp_file=$(mktemp)
  
  # Write text to temp file
  echo "${text}" > "${temp_file}"
  
  # Determine editor
  local editor="${EDITOR:-nano}"
  
  # Prompt user
  echo -e "${YELLOW}${BOLD}Interactive Edit Mode${RESET}"
  echo -e "${GRAY}Opening text in ${editor}. Make your changes and save the file.${RESET}"
  echo -e "${GRAY}Press Enter to continue...${RESET}"
  read -r
  
  # Open editor
  ${editor} "${temp_file}"
  
  # Read back edited text
  local edited_text=$(cat "${temp_file}")
  
  # Clean up
  rm "${temp_file}"
  
  echo "${edited_text}"
}

# Function to count script features
count_script_features() {
  local content="$1"
  
  # Count functions (very basic, may need refinement)
  local function_count=$(echo "${content}" | grep -c "function " || echo "0")
  
  # Count commands (very rough estimate)
  local command_count=$(echo "${content}" | grep -v "^#" | grep -v "^$" | grep -c ";" || echo "0")
  
  # Count conditionals
  local if_count=$(echo "${content}" | grep -c "if " || echo "0")
  local case_count=$(echo "${content}" | grep -c "case " || echo "0")
  
  # Count loops
  local for_count=$(echo "${content}" | grep -c "for " || echo "0")
  local while_count=$(echo "${content}" | grep -c "while " || echo "0")
  
  # Add features to metrics log
  jq --arg functions "${function_count}" \
     --arg commands "${command_count}" \
     --arg ifs "${if_count}" \
     --arg cases "${case_count}" \
     --arg fors "${for_count}" \
     --arg whiles "${while_count}" \
     '.script_features = {"function_count": $functions, "command_count": $commands, "if_count": $ifs, "case_count": $cases, "for_count": $fors, "while_count": $whiles}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
}

# Function to check for dependencies
check_dependencies() {
  local missing_deps=0
  
  # Start timer
  local start_time=$(date +%s.%N)
  
  # Check for jq
  if ! command -v jq &> /dev/null; then
    log_message "ERROR" "jq is required. Please install jq (e.g., 'brew install jq')."
    missing_deps=1
  fi
  
  # Check for bc
  if ! command -v bc &> /dev/null; then
    log_message "ERROR" "bc is required. Please install bc."
    missing_deps=1
  fi
  
  # Check for fswatch if in watch mode
  if [ "${WATCH_MODE}" = "true" ] && ! command -v fswatch &> /dev/null; then
    log_message "ERROR" "fswatch is required for watch mode. Please install fswatch."
    missing_deps=1
  fi
  
  # Check for ollama
  if ! command -v ollama &> /dev/null; then
    log_message "ERROR" "ollama is required. Please install Ollama."
    missing_deps=1
  else
    # Check if Ollama server is running
    log_message "INFO" "Checking Ollama server..."
    if ! curl -s -m 2 "http://localhost:11434/api/tags" &> /dev/null; then
      log_message "ERROR" "Ollama server is not running. Please start it with 'ollama serve'."
      missing_deps=1
    else
      log_message "SUCCESS" "Ollama server is running."
    fi
  fi
  
  # End timer
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "system" "0" "0" "0" "system" "dependency_check" "${duration}" "0"
  
  return ${missing_deps}
}

# Function to get available models
get_models() {
  local start_time=$(date +%s.%N)
  
  log_message "INFO" "Fetching available models..."
  local ollama_output=$(ollama list 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    log_message "ERROR" "Failed to run 'ollama list'. Ensure Ollama is running."
    exit 1
  fi
  
  # Parse models
  models=($(echo "$ollama_output" | tail -n +2 | awk '{print $1}'))
  model_ids=($(echo "$ollama_output" | tail -n +2 | awk '{print $2}'))
  model_sizes=($(echo "$ollama_output" | tail -n +2 | awk '{print $3, $4}'))
  
  if [ ${#models[@]} -eq 0 ]; then
    log_message "ERROR" "No models found. Please download a model using 'ollama pull <model>'."
    exit 1
  fi
  
  # Add models to metrics log
  local models_json="["
  for ((i=1; i<=${#models[@]}; i++)); do
    models_json+="\"${models[$i]}\""
    if [ $i -lt ${#models[@]} ]; then
      models_json+=","
    fi
  done
  models_json+="]"
  
  jq --argjson models "${models_json}" '.available_models = $models' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "system" "0" "0" "0" "system" "fetch_models" "${duration}" "${#models[@]}"
  
  # Just list models if that's what was requested
  if [[ "$1" == "--list" ]]; then
    echo -e "${CYAN}${BOLD}Available Ollama models for README generation:${RESET}"
    echo ""
    printf "${WHITE}%-30s %-15s %-15s${RESET}\n" "MODEL" "SIZE" "EST. SPEED"
    printf "${GRAY}%-30s %-15s %-15s${RESET}\n" "-----" "----" "---------"
    for ((i=1; i<=${#models[@]}; i++)); do
      local model_name="${models[$i]}"
      local model_size="${model_sizes[$i]}"
      
      # Get complexity factor for speed estimation
      local complexity=${MODEL_COMPLEXITY[$model_name]}
      if [ -z "$complexity" ]; then
        complexity=${MODEL_COMPLEXITY["default"]}
      fi
      
      # Calculate relative speed
      local speed=""
      local speed_color=""
      if (( $(echo "$complexity < 1.5" | bc -l) )); then
        speed="Very Fast"
        speed_color="${GREEN}"
      elif (( $(echo "$complexity < 2.5" | bc -l) )); then
        speed="Fast"
        speed_color="${CYAN}"
      elif (( $(echo "$complexity < 4.0" | bc -l) )); then
        speed="Medium"
        speed_color="${YELLOW}"
      else
        speed="Slow"
        speed_color="${RED}"
      fi
      
      printf "${MAGENTA}%-30s ${BLUE}%-15s ${speed_color}%-15s${RESET}\n" "$model_name" "$model_size" "$speed"
    done
    exit 0
  fi
  
  log_message "INFO" "Found ${#models[@]} available models"
}

# Function to select a model
select_model() {
  local start_time=$(date +%s.%N)
  
  # If a model is provided as an argument, use it
  if [ $# -ge 2 ]; then
    local provided_model="$2"
    # Check if the model is available
    if ollama list | grep -q "${provided_model}"; then
      model="${provided_model}"
      log_message "SUCCESS" "Using specified model: ${model}"
    else
      log_message "WARNING" "Model '${provided_model}' not found in available models."
      log_message "INFO" "Trying to pull the model..."
      ollama pull "${provided_model}"
      if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to pull model '${provided_model}'. Using default model: ${DEFAULT_MODEL}"
        model="${DEFAULT_MODEL}"
      else
        model="${provided_model}"
        log_message "SUCCESS" "Model '${provided_model}' pulled successfully."
      fi
    fi
  elif is_terminal; then
    # Interactive selection if terminal is available
    echo -e "${YELLOW}${BOLD}Select a model for README generation:${RESET}"
    echo ""
    printf "${WHITE}%-5s %-30s %-15s %-15s${RESET}\n" "NUM" "MODEL" "SIZE" "EST. SPEED"
    printf "${GRAY}%-5s %-30s %-15s %-15s${RESET}\n" "---" "-----" "----" "---------"
    for ((i=1; i<=${#models[@]}; i++)); do
      local model_name="${models[$i]}"
      local model_size="${model_sizes[$i]}"
      
      # Get complexity factor for speed estimation
      local complexity=${MODEL_COMPLEXITY[$model_name]}
      if [ -z "$complexity" ]; then
        complexity=${MODEL_COMPLEXITY["default"]}
      fi
      
      # Calculate relative speed
      local speed=""
      local speed_color=""
      if (( $(echo "$complexity < 1.5" | bc -l) )); then
        speed="Very Fast"
        speed_color="${GREEN}"
      elif (( $(echo "$complexity < 2.5" | bc -l) )); then
        speed="Fast"
        speed_color="${CYAN}"
      elif (( $(echo "$complexity < 4.0" | bc -l) )); then
        speed="Medium"
        speed_color="${YELLOW}"
      else
        speed="Slow"
        speed_color="${RED}"
      fi
      
      printf "${WHITE}%-5s ${MAGENTA}%-30s ${BLUE}%-15s ${speed_color}%-15s${RESET}\n" "$i" "$model_name" "$model_size" "$speed"
    done
    echo ""
    echo -e "${CYAN}Enter the number of the model to use:${RESET}"
    read -r model_num
    
    if [[ "$model_num" =~ ^[0-9]+$ ]] && [ "$model_num" -ge 1 ] && [ "$model_num" -le ${#models[@]} ]; then
      model="${models[$model_num]}"
      log_message "SUCCESS" "Selected model: ${model}"
    else
      log_message "WARNING" "Invalid selection. Using default model: ${DEFAULT_MODEL}"
      model="${DEFAULT_MODEL}"
    fi
  else
    # Non-interactive: use the default model
    model="${DEFAULT_MODEL}"
    log_message "INFO" "No terminal available for interactive selection. Using default model: ${model}"
  fi
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "${INPUT}" "0" "0" "0" "${model}" "model_selection" "${duration}" "0"
  
  # Record the selected model
  jq --arg model "${model}" '.selected_model = $model' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
}

# Function to validate input file
validate_input_file() {
  local input="$1"
  local start_time=$(date +%s.%N)
  
  if [ ! -f "${input}" ]; then
    log_message "ERROR" "Input file '${input}' does not exist."
    exit 1
  fi
  
  # Get file stats
  local file_size=$(stat -f%z "${input}")
  CONTENT=$(cat "${input}")
  local line_count=$(echo "${CONTENT}" | wc -l | tr -d ' ')
  local char_count=$(echo "${CONTENT}" | wc -c | tr -d ' ')
  
  # Record file metrics
  jq --arg file "${input}" \
     --arg size "${file_size}" \
     --arg lines "${line_count}" \
     --arg chars "${char_count}" \
     '.input_file = {"path": $file, "size_bytes": $size, "line_count": $lines, "char_count": $chars}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Determine file extension
  ext="${input##*.}"
  
  # Check supported file types
  case "${ext}" in
    sh|bash|zsh)
      # Check if it's base64 encoded (from legacy code)
      if echo "$CONTENT" | grep -qE '^[A-Za-z0-9+/=]+$'; then
        # Attempt to decode as base64
        local DECODED_CONTENT=$(echo "$CONTENT" | base64 -d 2>/dev/null)
        if [ $? -eq 0 ] && echo "$DECODED_CONTENT" | grep -qE "^#!/bin/(bash|zsh|sh)"; then
          CONTENT="$DECODED_CONTENT"
          log_message "INFO" "Input detected as base64-encoded shell script. Decoded successfully."
        else
          log_message "WARNING" "Input appears to be base64 but failed to decode as a valid shell script. Treating as plain text."
        fi
      fi
      
      # Validate as shell script
      if echo "${CONTENT}" | grep -qE "^#!/bin/(bash|zsh|sh)"; then
        SCRIPT_TYPE="shell"
        log_message "SUCCESS" "Validated shell script with ${line_count} lines."
      else
        SCRIPT_TYPE="shell"
        log_message "WARNING" "Input does not appear to be a valid shell script (missing shebang)."
      fi
      ;;
    scpt|applescript)
      # AppleScript
      SCRIPT_TYPE="applescript"
      log_message "SUCCESS" "Validated AppleScript with ${line_count} lines."
      ;;
    py|python)
      # Python script
      SCRIPT_TYPE="python"
      log_message "SUCCESS" "Validated Python script with ${line_count} lines."
      ;;
    rb|ruby)
      # Ruby script
      SCRIPT_TYPE="ruby"
      log_message "SUCCESS" "Validated Ruby script with ${line_count} lines."
      ;;
    js|javascript)
      # JavaScript
      SCRIPT_TYPE="javascript"
      log_message "SUCCESS" "Validated JavaScript with ${line_count} lines."
      ;;
    *)
      SCRIPT_TYPE="generic"
      log_message "WARNING" "Unsupported file type: ${ext}. Will attempt to analyze as generic script."
      ;;
  esac
  
  # Count script features
  count_script_features "${CONTENT}"
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "${input}" "${file_size}" "${line_count}" "${char_count}" "${model}" "file_validation" "${duration}" "0"
  
  # Store file metrics for later use
  FILE_SIZE="${file_size}"
  LINE_COUNT="${line_count}"
  CHAR_COUNT="${char_count}"
  
  log_message "INFO" "File validated: ${input} (${file_size} bytes, ${line_count} lines)"
}

# Function to generate README from script
generate_readme() {
  local input="$1"
  local model="$2"
  local skip_estimate="$3"
  local interactive_mode="$4"
  local script_basename=$(basename "${input}")
  local start_time=$(date +%s.%N)
  
  log_message "INFO" "Generating README documentation for ${script_basename} with ${model}..."
  
  # Estimate completion time if not skipped
  local estimated_seconds=""
  if [ "$skip_estimate" != "true" ]; then
    estimated_seconds=$(estimate_completion_time "${FILE_SIZE}" "${model}")
    local estimated_time=$(format_time "${estimated_seconds}")
    log_message "INFO" "Estimated completion time: ${YELLOW}${estimated_time}${RESET}"
    jq --arg est "${estimated_seconds}" '.estimated_completion_time = $est' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  fi
  
  # Create request payload
  local payload=$(jq -n \
    --arg model "${model}" \
    --arg content "${CONTENT}" \
    --arg filename "${script_basename}" \
    --arg script_type "${SCRIPT_TYPE}" \
    '{
      "model": $model,
      "messages": [
        {
          "role": "system",
          "content": "You are an expert code documentarian tasked with producing professional, accurate, and comprehensive documentation. Analyze the provided \($script_type) script with precision, describing only the functionality explicitly present in the code. Generate a detailed Markdown README section that is clear, thorough, and professionally structured, suitable for developers and end-users."
        },
        {
          "role": "user",
          "content": "Analyze the following \($script_type) script provided as plain text. Pay close attention to specific elements such as references to applications, system paths, and command-line tools. Consider the script'\''s potential impact on the system.\n\nGenerate a Markdown README section with these sections:\n\n- **Overview**: Summarize the script'\''s purpose and primary actions.\n- **Requirements**: List prerequisites inferred from the script.\n- **Usage**: Provide precise instructions for running the script.\n- **What the Script Does**: Describe the script'\''s operations step-by-step.\n- **Important Notes**: Highlight critical details derived from the script.\n- **Disclaimer**: Warn about risks of running the script.\n\nFile: \($filename)\n\nScript Content:\n\($content)"
        }
      ],
      "stream": false
    }')
  
  # Log the prompt size (in characters)
  local prompt_size=$(echo "${payload}" | jq -r '.messages[1].content' | wc -c | tr -d ' ')
  jq --arg size "${prompt_size}" '.prompt_size_chars = $size' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Send request to Ollama API
  log_message "INFO" "Sending request to Ollama API..."
  local request_start_time=$(date +%s.%N)
  
  # Temporary file for response
  local temp_response=$(mktemp)
  
  # Show progress bar if estimate is available
  if [ -n "$estimated_seconds" ]; then
    # Send the request in background
    curl -s -X POST "${OLLAMA_API}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > "${temp_response}" &
    
    local pid=$!
    local start_secs=$SECONDS
    local progress=0
    
    # Show progress while curl is running
    while kill -0 $pid 2>/dev/null; do
      local elapsed=$((SECONDS - start_secs))
      if [ $estimated_seconds -gt 0 ]; then
        progress=$((elapsed * 100 / estimated_seconds))
        # Cap at 99% until complete
        if [ $progress -gt 99 ]; then
          progress=99
        fi
      else
        progress=50  # Default to 50% if no estimate
      fi
      
      display_progress $progress "$(format_time $elapsed)"
      sleep 0.5
    done
    
    # Make sure curl completed successfully
    wait $pid
    if [ $? -ne 0 ]; then
      echo ""
      log_message "ERROR" "Failed to connect to Ollama API. Ensure the server is running."
      play_sound "error"
      exit 1
    fi
    
    # Show 100% completion
    display_progress 100 "$(format_time $((SECONDS - start_secs)))"
    echo ""
  else
    # Regular request without progress bar
    log_message "INFO" "Processing request..."
    curl -s -X POST "${OLLAMA_API}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > "${temp_response}" &
    
    local pid=$!
    spinner $pid
    
    wait $pid
    if [ $? -ne 0 ]; then
      log_message "ERROR" "Failed to connect to Ollama API. Ensure the server is running."
      play_sound "error"
      exit 1
    fi
  fi
  
  local request_end_time=$(date +%s.%N)
  local request_duration=$(printf "%.2f" $(echo "${request_end_time} - ${request_start_time}" | bc))
  
  log_benchmark "${script_basename}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "api_request" "${request_duration}" "${prompt_size}"
  
  # Parse response
  log_message "INFO" "Processing response..."
  local parse_start_time=$(date +%s.%N)
  
  if grep -q "error" "${temp_response}"; then
    log_message "ERROR" "Ollama response error:"
    cat "${temp_response}"
    jq --arg error "$(cat ${temp_response})" '.error = $error' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
    rm "${temp_response}"
    play_sound "error"
    exit 1
  fi
  
  # Extract metrics from response if available
  local total_duration=$(jq -r '.total_duration // 0' "${temp_response}")
  local eval_count=$(jq -r '.eval_count // 0' "${temp_response}")
  local prompt_eval_count=$(jq -r '.prompt_eval_count // 0' "${temp_response}")
  local eval_duration=$(jq -r '.eval_duration // 0' "${temp_response}")
  local prompt_eval_duration=$(jq -r '.prompt_eval_duration // 0' "${temp_response}")
  
  # Convert to seconds if in nanoseconds
  if [ "${total_duration}" -gt 1000000000 ]; then
    total_duration=$(printf "%.2f" $(echo "scale=2; ${total_duration}/1000000000" | bc))
  fi
  
  # Add Ollama-reported metrics to log
  jq --arg total "${total_duration}" \
     --arg eval "${eval_count}" \
     --arg prompt_eval "${prompt_eval_count}" \
     --arg eval_dur "${eval_duration}" \
     --arg prompt_dur "${prompt_eval_duration}" \
     '.ollama_metrics = {"total_duration": $total, "eval_count": $eval, "prompt_eval_count": $prompt_eval, "eval_duration": $eval_dur, "prompt_eval_duration": $prompt_dur}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Extract response content - try different methods for compatibility
  if jq -e '.message.content' "${temp_response}" > /dev/null 2>&1; then
    RESPONSE=$(jq -r '.message.content' "${temp_response}")
  else
    # Fallback method using grep and sed
    RESPONSE=$(grep -o '"content":"[^"]*"' "${temp_response}" | sed 's/"content":"//;s/"//')
    
    # If that fails, try perl
    if [ -z "${RESPONSE}" ]; then
      RESPONSE=$(perl -0777 -ne 'print $1 if /"content":"(.*?)"/s' "${temp_response}")
    fi
  fi
  
  # If still empty, try one more approach
  if [ -z "${RESPONSE}" ]; then
    RESPONSE=$(cat "${temp_response}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['message']['content'])
except Exception as e:
    print(f'Error parsing JSON: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)
  fi
  
  # Check if response is empty
  if [ -z "${RESPONSE}" ]; then
    log_message "ERROR" "Empty response from Ollama."
    echo "Raw response:"
    cat "${temp_response}"
    jq --arg error "Empty response" '.error = $error' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
    rm "${temp_response}"
    play_sound "error"
    exit 1
  fi
  
  # Calculate response metrics
  local response_char_count=$(echo "${RESPONSE}" | wc -c | tr -d ' ')
  local response_line_count=$(echo "${RESPONSE}" | wc -l | tr -d ' ')
  local response_word_count=$(echo "${RESPONSE}" | wc -w | tr -d ' ')
  
  # Add response metrics to log
  jq --arg chars "${response_char_count}" \
     --arg lines "${response_line_count}" \
     --arg words "${response_word_count}" \
     '.response_metrics = {"char_count": $chars, "line_count": $lines, "word_count": $words}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Save the full response for analysis
  echo "${RESPONSE}" > "${BENCHMARK_DIR}/response_${SESSION_ID}.md"
  
  # Clean up
  rm "${temp_response}"
  
  local parse_end_time=$(date +%s.%N)
  local parse_duration=$(printf "%.2f" $(echo "${parse_end_time} - ${parse_start_time}" | bc))
  
  log_benchmark "${script_basename}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "response_parsing" "${parse_duration}" "${response_word_count}"
  
  # Interactive edit if requested
  if [ "${interactive_mode}" = "true" ]; then
    log_message "INFO" "Opening documentation in editor for customization..."
    RESPONSE=$(edit_text "${RESPONSE}")
    log_message "SUCCESS" "Documentation customized."
  fi
  
  # Update README.md (with model information)
  log_message "INFO" "Updating README.md..."
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  {
    echo -e "\n## ${script_basename} (Analyzed with ${model})"
    echo -e "#### Analysis Date: ${timestamp}"
    echo -e "${RESPONSE}\n"
    echo -e "### License"
    echo -e "This script is provided under the MIT License.\n"
    echo -e "MIT License\n"
    echo -e "Copyright (c) $(date +%Y) ${APP_AUTHOR}\n"
    echo -e "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n"
    echo -e "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n"
    echo -e "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
  } >> "${README}"
  
  log_message "SUCCESS" "README.md updated for ${script_basename}"
  
  local end_time=$(date +%s.%N)
  local total_duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  # Log total analysis time
  log_benchmark "${script_basename}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "total_analysis" "${total_duration}" "${response_word_count}"
  
  # Update changelog
  update_changelog "${script_basename}" "${model}" "${total_duration}"
  
  # Generate benchmark summary
  generate_benchmark_summary "${model}" "${script_basename}" "${total_duration}" "${request_duration}" "${parse_duration}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${response_word_count}" "${estimated_seconds}"
  
  # Add final timestamp to metrics log
  jq --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '.completion_timestamp = $ts' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Play completion sound
  play_sound "complete"
  
  # Show tip
  show_tip
  
  return 0
}

# Function to export README to different formats
export_readme() {
  local format="$1"
  
  if [ ! -f "${README}" ]; then
    log_message "ERROR" "README.md not found. Generate documentation first."
    return 1
  fi
  
  case "${format}" in
    html)
      # Check if pandoc is installed
      if ! command -v pandoc &> /dev/null; then
        log_message "ERROR" "pandoc is required for HTML export. Please install pandoc."
        return 1
      fi
      
      local output_file="${README%.*}.html"
      log_message "INFO" "Exporting to HTML: ${output_file}"
      
      pandoc -s "${README}" -o "${output_file}" --metadata title="Documentation" \
        --css "https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css" \
        --template=default
      
      if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Exported to HTML: ${output_file}"
      else
        log_message "ERROR" "Failed to export to HTML."
        return 1
      fi
      ;;
    pdf)
      # Check if pandoc is installed
      if ! command -v pandoc &> /dev/null; then
        log_message "ERROR" "pandoc is required for PDF export. Please install pandoc."
        return 1
      fi
      
      local output_file="${README%.*}.pdf"
      log_message "INFO" "Exporting to PDF: ${output_file}"
      
      pandoc "${README}" -o "${output_file}" --pdf-engine=wkhtmltopdf
      
      if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Exported to PDF: ${output_file}"
      else
        log_message "ERROR" "Failed to export to PDF."
        return 1
      fi
      ;;
    *)
      log_message "ERROR" "Unsupported export format: ${format}"
      return 1
      ;;
  esac
  
  return 0
}

# Function to watch a directory for new files
watch_directory() {
  local directory="$1"
  local model="$2"
  
  # Check if directory exists
  if [ ! -d "${directory}" ]; then
    log_message "ERROR" "Directory '${directory}' does not exist."
    exit 1
  fi
  
  # Check if fswatch is installed
  if ! command -v fswatch &> /dev/null; then
    log_message "ERROR" "fswatch is required for watch mode. Please install fswatch."
    exit 1
  fi
  
  log_message "INFO" "Watching directory: ${directory}"
  log_message "INFO" "Using model: ${model}"
  log_message "INFO" "Press Ctrl+C to stop watching."
  
  # Create a list of processed files
  local processed_files=()
  
  # Process existing files first if requested
  if [ "${PROCESS_EXISTING}" = "true" ]; then
    log_message "INFO" "Processing existing files..."
    for file in "${directory}"/*.{sh,bash,zsh,py,rb,js}; do
      # Check if file exists and is a regular file
      if [ -f "${file}" ]; then
        log_message "INFO" "Processing existing file: ${file}"
        validate_input_file "${file}"
        generate_readme "${file}" "${model}" "${SKIP_ESTIMATE}" "${INTERACTIVE_MODE}"
        processed_files+=("$(realpath "${file}")")
      fi
    done
  fi
  
  # Watch for new files
  fswatch -0 -r "${directory}" | while read -d "" event; do
    # Check if the event is a new file or modified file
    if [ -f "${event}" ]; then
      # Get the file extension
      local ext="${event##*.}"
      
      # Check if it's a script file
      if [[ "${ext}" =~ ^(sh|bash|zsh|py|rb|js)$ ]]; then
        # Check if the file has already been processed
        local realpath_event=$(realpath "${event}")
        if [[ ! " ${processed_files[@]} " =~ " ${realpath_event} " ]]; then
          log_message "INFO" "New script detected: ${event}"
          validate_input_file "${event}"
          generate_readme "${event}" "${model}" "${SKIP_ESTIMATE}" "${INTERACTIVE_MODE}"
          processed_files+=("${realpath_event}")
        fi
      fi
    fi
  done
}

# Function to process multiple files
batch_process() {
  local pattern="$1"
  local model="$2"
  
  # Find matching files
  local files=()
  for file in ${pattern}; do
    if [ -f "${file}" ]; then
      files+=("${file}")
    fi
  done
  
  # Check if any files were found
  if [ ${#files[@]} -eq 0 ]; then
    log_message "ERROR" "No files found matching pattern: ${pattern}"
    exit 1
  fi
  
  log_message "INFO" "Found ${#files[@]} files to process."
  
  # Process each file
  local count=1
  for file in "${files[@]}"; do
    log_message "INFO" "Processing file ${count}/${#files[@]}: ${file}"
    validate_input_file "${file}"
    generate_readme "${file}" "${model}" "${SKIP_ESTIMATE}" "${INTERACTIVE_MODE}"
    ((count++))
  done
  
  log_message "SUCCESS" "Batch processing complete. Processed ${#files[@]} files."
}

# =================== MAIN SCRIPT ===================

# Start timer for overall execution
SCRIPT_START_TIME=$(date +%s.%N)

# Initialize default values
SKIP_ESTIMATE=false
INTERACTIVE_MODE=false
WATCH_MODE=false
BATCH_MODE=false
EXPORT_MODE=false
PROCESS_EXISTING=false
WATCH_DIR=""
BATCH_PATTERN=""
EXPORT_FORMAT=""

# Show logo if running in terminal
if is_terminal; then
  show_logo
fi

# Get system information
get_system_info

# Process command-line arguments
while [[ "$1" == --* ]]; do
  case "$1" in
    --help)
      show_usage
      ;;
    --version)
      show_version
      ;;
    --list-models)
      get_models --list
      ;;
    --no-estimate)
      SKIP_ESTIMATE=true
      shift
      ;;
    --no-color)
      # Disable colors
      RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' GRAY=''
      BOLD='' DIM='' UNDERLINE='' BLINK='' REVERSE='' RESET=''
      for i in {0..9}; do GRADIENT[$i]=''; done
      shift
      ;;
    --sound)
      SOUND_ENABLED=1
      shift
      ;;
    --interactive)
      INTERACTIVE_MODE=true
      shift
      ;;
    --watch)
      WATCH_MODE=true
      shift
      if [ $# -ge 1 ] && [[ ! "$1" == --* ]]; then
        WATCH_DIR="$1"
        shift
      else
        WATCH_DIR="."
      fi
      ;;
    --process-existing)
      PROCESS_EXISTING=true
      shift
      ;;
    --batch)
      BATCH_MODE=true
      shift
      if [ $# -ge 1 ] && [[ ! "$1" == --* ]]; then
        BATCH_PATTERN="$1"
        shift
      else
        log_message "ERROR" "No pattern specified for batch mode."
        exit 1
      fi
      ;;
    --export)
      EXPORT_MODE=true
      shift
      if [ $# -ge 1 ] && [[ ! "$1" == --* ]]; then
        EXPORT_FORMAT="$1"
        shift
      else
        log_message "ERROR" "No format specified for export."
        exit 1
      fi
      ;;
    --config)
      update_config
      ;;
    --debug)
      # Already handled at the top
      shift
      ;;
    *)
      log_message "ERROR" "Unknown option: $1"
      log_message "INFO" "Run '$0 --help' for usage information."
      exit 1
      ;;
  esac
done

# Export mode - just export the README and exit
if [ "${EXPORT_MODE}" = "true" ]; then
  log_message "INFO" "Exporting README to ${EXPORT_FORMAT} format."
  export_readme "${EXPORT_FORMAT}"
  exit $?
fi

# Check dependencies
check_dependencies || exit 1

# Get available models
get_models

# Watch mode - watch a directory for new files
if [ "${WATCH_MODE}" = "true" ]; then
  log_message "INFO" "Starting watch mode on directory: ${WATCH_DIR}"
  select_model
  watch_directory "${WATCH_DIR}" "${model}"
  exit 0
fi

# Batch mode - process multiple files
if [ "${BATCH_MODE}" = "true" ]; then
  log_message "INFO" "Starting batch mode with pattern: ${BATCH_PATTERN}"
  select_model
  batch_process "${BATCH_PATTERN}" "${model}"
  exit 0
fi

# Input handling for single file
if [ $# -lt 1 ]; then
  log_message "ERROR" "No input file specified."
  log_message "INFO" "Run '$0 --help' for usage information."
  exit 1
fi

INPUT="$1"
log_message "INFO" "Input file: ${INPUT}"

# Select model and generate README
select_model "$@"
validate_input_file "${INPUT}"
generate_readme "${INPUT}" "${model}" "${SKIP_ESTIMATE}" "${INTERACTIVE_MODE}"

# End timer for overall execution
SCRIPT_END_TIME=$(date +%s.%N)
TOTAL_EXECUTION_TIME=$(printf "%.2f" $(echo "${SCRIPT_END_TIME} - ${SCRIPT_START_TIME}" | bc))

log_benchmark "${INPUT}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "script_execution" "${TOTAL_EXECUTION_TIME}" "0"

log_message "SUCCESS" "Script completed in ${TOTAL_EXECUTION_TIME} seconds"