#!/bin/zsh
#
# script2readme.sh - Generate high-quality README documentation from scripts using Ollama models
# Author: Ian Trimble
# Created: April 28, 2025
# Version: 1.3.0
#

# Enable debug mode only when explicitly requested
if [[ "$1" == "--debug" ]]; then
  set -x
  shift
fi

# =================== COLORS AND FORMATTING ===================
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
  RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' GRAY=''
  BOLD='' DIM='' UNDERLINE='' BLINK='' REVERSE='' RESET=''
  for i in {0..9}; do GRADIENT[$i]=''; done
fi

# =================== CONFIGURATION ===================
APP_NAME="Script to README Generator"
APP_VERSION="1.3.0"
APP_AUTHOR="Ian Trimble"

BENCHMARK_DIR="${HOME}/ollama_benchmarks"
SESSION_ID=$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)
BENCHMARK_LOG="${BENCHMARK_DIR}/benchmark_log.csv"
METRICS_LOG="${BENCHMARK_DIR}/metrics_${SESSION_ID}.json"
CHANGELOG="${BENCHMARK_DIR}/changelog.md"
README="$(pwd)/README.md"
OLLAMA_API="http://localhost:11434/api/chat"
TEMPLATE_DIR="${HOME}/.script2readme/templates"
CONFIG_FILE="${HOME}/.script2readme/config.json"

DEFAULT_MODEL="qwen2.5-coder:7b"
SOUND_ENABLED=0
SOUND_COMPLETE="afplay /System/Library/Sounds/Glass.aiff"
SOUND_ERROR="afplay /System/Library/Sounds/Sosumi.aiff"

# Model complexity factors
declare -A MODEL_COMPLEXITY
MODEL_COMPLEXITY["qwen2.5:1.5b"]=1.0
MODEL_COMPLEXITY["qwen2.5-coder:7b"]=3.5
MODEL_COMPLEXITY["deepseek-coder:6.7b"]=3.0
MODEL_COMPLEXITY["codellama:7b"]=3.0
MODEL_COMPLEXITY["codellama:13b"]=5.5
MODEL_COMPLEXITY["default"]=2.5

# Model descriptions
declare -A MODEL_DESCRIPTIONS
MODEL_DESCRIPTIONS["qwen2.5:1.5b"]="Fastest option for simple scripts. Less detailed but great for quick documentation of straightforward code."
MODEL_DESCRIPTIONS["qwen2.5-coder:7b"]="Excellent for code documentation with balanced performance and accuracy. Specializes in programming patterns."
MODEL_DESCRIPTIONS["deepseek-coder:6.7b"]="Specializes in deep code analysis and explaining complex functionality clearly."
MODEL_DESCRIPTIONS["codellama:7b"]="Good balance of speed and quality. Strong at API and function documentation."
MODEL_DESCRIPTIONS["codellama:13b"]="Most comprehensive but slowest. Best for complex scripts where detail is critical."
MODEL_DESCRIPTIONS["default"]="General-purpose model with unknown performance characteristics."

# Script complexity factors
LINE_FACTOR=0.3
FUNCTION_FACTOR=2.0
CONDITIONAL_FACTOR=1.5
LOOP_FACTOR=1.2

# Tips
declare -a TIPS
TIPS=(
  "Use --interactive to edit documentation before saving."
  "Run with --batch '*.sh' to process multiple scripts."
  "Check benchmarks at ${BENCHMARK_DIR}."
)

# Create directories
mkdir -p "${BENCHMARK_DIR}" "${TEMPLATE_DIR}" "$(dirname "${CONFIG_FILE}")"

# Default config
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "{\"default_model\": \"${DEFAULT_MODEL}\", \"sound_enabled\": false}" > "${CONFIG_FILE}"
fi

# Load config
if [ -f "${CONFIG_FILE}" ] && command -v jq &> /dev/null; then
  DEFAULT_MODEL=$(jq -r '.default_model // "qwen2.5-coder:7b"' "${CONFIG_FILE}")
  SOUND_ENABLED=$(jq -r '.sound_enabled // false' "${CONFIG_FILE}")
  [[ "${SOUND_ENABLED}" == "true" ]] && SOUND_ENABLED=1 || SOUND_ENABLED=0
fi

# Initialize logs
if [ ! -f "${BENCHMARK_LOG}" ]; then
  echo "timestamp,session_id,script_name,script_size,script_lines,model,duration" > "${BENCHMARK_LOG}"
fi
if [ ! -f "${CHANGELOG}" ]; then
  echo "# Changelog\n\n## Version 1.3.0 - $(date '+%Y-%m-%d')\n- Initial release with enhanced features" > "${CHANGELOG}"
fi
echo "{\"session_id\": \"${SESSION_ID}\", \"metrics\": []}" > "${METRICS_LOG}"

# =================== HELPER FUNCTIONS ===================
show_logo() {
  clear
  echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}███████╗${GREEN}██████╗${CYAN} ██████╗${YELLOW}███████╗${RED}██████╗ ${MAGENTA}███████╗${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}██╔════╝${GREEN}██╔══██╗${CYAN}██╔════╝${YELLOW}██╔════╝${RED}██╔══██╗${MAGENTA}██╔════╝${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}███████╗${GREEN}██████╔╝${CYAN}██║     ${YELLOW}█████╗  ${RED}██████╔╝${MAGENTA}█████╗  ${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}╚════██║${GREEN}██╔══██╗${CYAN}██║     ${YELLOW}██╔══╝  ${RED}██╔══██╗${MAGENTA}██╔══╝  ${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}███████║${GREEN}██║  ██║${CYAN}╚██████╗${YELLOW}███████╗${RED}██║  ██║${MAGENTA}███████╗${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}╚══════╝${GREEN}╚═╝  ╚═╝${CYAN} ╚═════╝${YELLOW}╚══════╝${RED}╚═╝  ╚═╝${MAGENTA}╚══════╝${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${CYAN}${APP_NAME} ${WHITE}v${APP_VERSION}${BLUE}              ║${RESET}"
  echo -e "${BLUE}║  ${GRAY}By ${APP_AUTHOR}${BLUE}                                    ║${RESET}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

log_message() {
  local level=$1
  local message=$2
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  case ${level} in
    "INFO")    echo -e "${BLUE}[${timestamp}] ℹ️  ${RESET}${message}" ;;
    "SUCCESS") echo -e "${GREEN}[${timestamp}] ✅ ${BOLD}${message}${RESET}" ;;
    "WARNING") echo -e "${YELLOW}[${timestamp}] ⚠️  ${BOLD}${message}${RESET}" ;;
    "ERROR")   echo -e "${RED}[${timestamp}] ❌ ${BOLD}${message}${RESET}" ;;
    *)         echo -e "[${timestamp}] ${message}" ;;
  esac
}

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

display_progress() {
  local progress=$1
  local duration=$2
  local width=40
  local filled=$((width * progress / 100))
  local empty=$((width - filled))
  local bar=""
  for ((i = 0; i < filled; i++)); do
    local color_index=$((i * 10 / width))
    bar="${bar}${GRADIENT[$color_index]}█"
  done
  for ((i = 0; i < empty; i++)); do
    bar="${bar}${GRAY}░"
  done
  printf "\r${WHITE}[${RESET}${bar}${RESET}${WHITE}]${RESET} ${BOLD}%3d%%${RESET} ${WHITE}(${CYAN}%s${WHITE})${RESET}" $progress "$duration"
}

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

estimate_completion_time() {
  local script_size=$1
  local model=$2
  local model_factor=${MODEL_COMPLEXITY[$model]:-${MODEL_COMPLEXITY["default"]}}
  local base_time=2
  local size_factor=$(printf "%.2f" $(echo "scale=2; ($script_size / 1024) ^ 0.6" | bc))
  local estimate=$(printf "%.0f" $(echo "scale=0; $base_time * $size_factor * $model_factor" | bc))
  [ $estimate -lt 10 ] && estimate=10
  echo $estimate
}

show_usage() {
  echo -e "${CYAN}${BOLD}${APP_NAME}${RESET} ${WHITE}v${APP_VERSION}${RESET}"
  echo -e "${GRAY}Generates professional README documentation from scripts${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Usage:${RESET} $0 ${GREEN}[OPTIONS]${RESET} ${MAGENTA}<input_file>${RESET} ${BLUE}[model]${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Options:${RESET}"
  echo -e "  ${GREEN}--help${RESET}         Show this help message"
  echo -e "  ${GREEN}--list-models${RESET}  List available Ollama models"
  echo -e "  ${GREEN}--no-estimate${RESET}  Skip time estimation"
  echo -e "  ${GREEN}--interactive${RESET}  Edit documentation before saving"
  echo -e "  ${GREEN}--batch${RESET} ${BLUE}<pattern>${RESET}  Process multiple files"
  echo -e "  ${GREEN}--watch${RESET} ${BLUE}<dir>${RESET}     Watch directory for new scripts"
  echo ""
  echo -e "${YELLOW}${BOLD}Examples:${RESET}"
  echo -e "  ${GRAY}$0 my_script.sh${RESET}"
  echo -e "  ${GRAY}$0 --batch \"*.sh\"${RESET}"
  echo -e "  ${GRAY}$0 --watch ~/scripts${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Output:${RESET}"
  echo -e "  - Updates README.md in current directory"
  echo -e "  - Benchmarks saved to ${BENCHMARK_DIR}"
  echo ""
  echo -e "${YELLOW}💡 Tip:${RESET} ${TIPS[$((RANDOM % ${#TIPS[@]}))]}"
  exit 0
}

check_dependencies() {
  local missing_deps=0
  for cmd in jq bc curl ollama; do
    if ! command -v "$cmd" &> /dev/null; then
      log_message "ERROR" "$cmd is required. Install with 'brew install $cmd'."
      missing_deps=1
    fi
  done
  if ! curl -s -m 2 "${OLLAMA_API}/tags" &> /dev/null; then
    log_message "ERROR" "Ollama server not running. Start with 'ollama serve'."
    missing_deps=1
  fi
  return $missing_deps
}

get_models() {
  local ollama_output=$(ollama list 2>/dev/null) || { log_message "ERROR" "Failed to fetch models."; exit 1; }
  models=($(echo "$ollama_output" | tail -n +2 | awk '{print $1}'))
  model_sizes=($(echo "$ollama_output" | tail -n +2 | awk '{print $3, $4}'))
  [ ${#models[@]} -eq 0 ] && { log_message "ERROR" "No models found. Run 'ollama pull <model>'."; exit 1; }
}

select_model() {
  get_models
  if [ $# -ge 2 ]; then
    model="$2"
    if ! printf '%s\n' "${models[@]}" | grep -q "^${model}$"; then
      log_message "WARNING" "Model '${model}' not found. Using default: ${DEFAULT_MODEL}"
      model="${DEFAULT_MODEL}"
    fi
  elif [ -t 0 ]; then
    echo -e "${YELLOW}${BOLD}Select a model:${RESET}"
    printf "${WHITE}%-5s %-30s %-15s %-15s${RESET}\n" "NUM" "MODEL" "SIZE" "SPEED"
    printf "${GRAY}%-5s %-30s %-15s %-15s${RESET}\n" "---" "-----" "----" "------"
    for ((i=1; i<=${#models[@]}; i++)); do
      local complexity=${MODEL_COMPLEXITY[${models[$i]}]:-${MODEL_COMPLEXITY["default"]}}
      local speed=""
      local speed_color=""
      if (( $(echo "$complexity < 1.5" | bc -l) )); then speed="Very Fast"; speed_color="${GREEN}"
      elif (( $(echo "$complexity < 2.5" | bc -l) )); then speed="Fast"; speed_color="${CYAN}"
      elif (( $(echo "$complexity < 4.0" | bc -l) )); then speed="Medium"; speed_color="${YELLOW}"
      else speed="Slow"; speed_color="${RED}"; fi
      printf "${WHITE}%-5s ${MAGENTA}%-30s ${BLUE}%-15s ${speed_color}%-15s${RESET}\n" "$i" "${models[$i]}" "${model_sizes[$i]}" "$speed"
    done
    echo -e "${GRAY}${MODEL_DESCRIPTIONS[${models[$i]}]:-${MODEL_DESCRIPTIONS["default"]}}${RESET}"
    echo -e "${CYAN}Enter number:${RESET}"
    read -r model_num
    if [[ "$model_num" =~ ^[0-9]+$ ]] && [ "$model_num" -ge 1 ] && [ "$model_num" -le ${#models[@]} ]; then
      model="${models[$model_num]}"
    else
      log_message "WARNING" "Invalid selection. Using default: ${DEFAULT_MODEL}"
      model="${DEFAULT_MODEL}"
    fi
  else
    model="${DEFAULT_MODEL}"
  fi
  log_message "SUCCESS" "Selected model: ${model}"
}

validate_input_file() {
  local input="$1"
  if [ ! -f "$input" ]; then
    log_message "ERROR" "File '$input' not found."
    exit 1
  fi
  FILE_SIZE=$(stat -f%z "$input")
  CONTENT=$(cat "$input")
  LINE_COUNT=$(echo "$CONTENT" | wc -l | tr -d ' ')
  ext="${input##*.}"
  case "$ext" in
    sh|bash|zsh) SCRIPT_TYPE="shell" ;;
    py|python) SCRIPT_TYPE="python" ;;
    *) SCRIPT_TYPE="generic" ;;
  esac
}

handle_duplicates() {
  local base_name=$(basename "$1")
  if grep -q "^# .*${base_name}" "${README}" 2>/dev/null; then
    SECTION_HEADER="${base_name} ($(date +%Y%m%d_%H%M%S))"
    log_message "INFO" "Duplicate detected. Using: ${SECTION_HEADER}"
  else
    SECTION_HEADER="${base_name}"
  fi
}

generate_readme() {
  local input="$1"
  local model="$2"
  local skip_estimate="$3"
  local interactive="$4"
  local script_basename=$(basename "$input")
  local start_time=$(date +%s.%N)

  handle_duplicates "$input"
  log_message "INFO" "Generating README for ${SECTION_HEADER} with ${model}..."

  local estimated_seconds=""
  if [ "$skip_estimate" != "true" ]; then
    estimated_seconds=$(estimate_completion_time "$FILE_SIZE" "$model")
    log_message "INFO" "Estimated time: $(format_time $estimated_seconds)"
  fi

  local payload=$(jq -n \
    --arg model "$model" \
    --arg content "$CONTENT" \
    --arg filename "$script_basename" \
    --arg script_type "$SCRIPT_TYPE" \
    '{
      "model": $model,
      "messages": [
        {"role": "system", "content": "You are an expert code documentarian producing professional, accurate READMEs."},
        {"role": "user", "content": "Generate a Markdown README section for the following \($script_type) script:\n\n- **Overview**: Summarize purpose and actions.\n- **Requirements**: List prerequisites.\n- **Usage**: Provide run instructions.\n- **What the Script Does**: Detail operations.\n- **Important Notes**: Highlight key details.\n- **Disclaimer**: Warn about risks.\n\nFile: \($filename)\n\nContent:\n\($content)"}
      ],
      "stream": false
    }')

  local temp_response=$(mktemp)
  local request_start=$(date +%s.%N)
  if [ -n "$estimated_seconds" ]; then
    curl -s -X POST "$OLLAMA_API" -H "Content-Type: application/json" -d "$payload" > "$temp_response" &
    local pid=$!
    local start_secs=$SECONDS
    local progress=0
    while kill -0 $pid 2>/dev/null; do
      local elapsed=$((SECONDS - start_secs))
      progress=$((elapsed * 100 / estimated_seconds))
      [ $progress -gt 99 ] && progress=99
      display_progress $progress "$(format_time $elapsed)"
      sleep 0.5
    done
    wait $pid || { log_message "ERROR" "API request failed."; exit 1; }
    display_progress 100 "$(format_time $((SECONDS - start_secs)))"
    echo ""
  else
    curl -s -X POST "$OLLAMA_API" -H "Content-Type: application/json" -d "$payload" > "$temp_response" &
    spinner $!
  fi
  local request_end=$(date +%s.%N)
  local request_duration=$(printf "%.2f" $(echo "$request_end - $request_start" | bc))

  if grep -q "error" "$temp_response"; then
    log_message "ERROR" "Ollama error: $(cat "$temp_response")"
    rm "$temp_response"
    exit 1
  fi

  local RESPONSE=$(jq -r '.message.content' "$temp_response" 2>/dev/null || \
    perl -0777 -ne 'print $1 if /"content":"(.*?)"/s' "$temp_response")
  rm "$temp_response"

  if [ "$interactive" = "true" ] && [ -t 0 ]; then
    local temp_file=$(mktemp)
    echo "$RESPONSE" > "$temp_file"
    ${EDITOR:-nano} "$temp_file"
    RESPONSE=$(cat "$temp_file")
    rm "$temp_file"
  fi

  {
    echo -e "<div align=\"center\">\n"
    echo -e "# 📜 ${SECTION_HEADER}\n"
    echo -e "**Generated with ${APP_NAME} using ${model}**"
    echo -e "\n*Generated on $(date '+%Y-%m-%d %H:%M:%S')*\n</div>\n\n---\n"
    echo -e "${RESPONSE}\n\n---\n"
    echo -e "### License\nMIT License\n\nCopyright (c) $(date +%Y) ${APP_AUTHOR}"
  } >> "$README"

  local end_time=$(date +%s.%N)
  local total_duration=$(printf "%.2f" $(echo "$end_time - $start_time" | bc))
  log_benchmark "$script_basename" "$FILE_SIZE" "$LINE_COUNT" "$model" "$total_duration"
  log_message "SUCCESS" "README.md updated for ${SECTION_HEADER}"
  update_changelog "$script_basename" "$model" "$total_duration"
  show_benchmark_location
}

log_benchmark() {
  local script_name=$1
  local script_size=$2
  local script_lines=$3
  local model=$4
  local duration=$5
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "${timestamp},${SESSION_ID},${script_name},${script_size},${script_lines},${model},${duration}" >> "${BENCHMARK_LOG}"
  jq --arg ts "$timestamp" --arg sn "$script_name" --arg sz "$script_size" --arg sl "$script_lines" --arg m "$model" --arg d "$duration" \
    '.metrics += [{"timestamp": $ts, "script_name": $sn, "size": $sz, "lines": $sl, "model": $m, "duration": $d}]' \
    "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
}

update_changelog() {
  local script_name=$1
  local model=$2
  local duration=$3
  local today=$(date '+%Y-%m-%d')
  if grep -q "### ${today}" "${CHANGELOG}"; then
    sed -i '' "/### ${today}/a\\
- Generated README for ${script_name} with ${model} (${duration}s)
" "${CHANGELOG}"
  else
    sed -i '' "/^## Version/a\\
\\
### ${today}\\
- Generated README for ${script_name} with ${model} (${duration}s)
" "${CHANGELOG}"
  fi
}

show_benchmark_location() {
  echo -e "${BLUE}╔════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║ ${CYAN}${BOLD}Benchmark Files${RESET}                ║${RESET}"
  echo -e "${BLUE}╠════════════════════════════════════╣${RESET}"
  echo -e "${BLUE}║ ${WHITE}Log:${RESET} ${YELLOW}${BENCHMARK_LOG}${RESET}    ║${RESET}"
  echo -e "${BLUE}║ ${WHITE}Metrics:${RESET} ${YELLOW}${METRICS_LOG}${RESET} ║${RESET}"
  echo -e "${BLUE}╚════════════════════════════════════╝${RESET}"
}

# =================== MAIN EXECUTION ===================
main() {
  show_logo
  check_dependencies || exit 1

  local input_file=""
  local model=""
  local skip_estimate=false
  local interactive=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) show_usage ;;
      --list-models) get_models; exit 0 ;;
      --no-estimate) skip_estimate=true; shift ;;
      --interactive) interactive=true; shift ;;
      --batch)
        shift
        for file in $1; do
          validate_input_file "$file"
          select_model "$file" "$model"
          generate_readme "$file" "$model" "$skip_estimate" "$interactive"
        done
        exit 0
        ;;
      --watch)
        shift
        log_message "INFO" "Watching directory: $1"
        fswatch -0 "$1" | while read -d "" event; do
          validate_input_file "$event"
          select_model "$event" "$model"
          generate_readme "$event" "$model" "$skip_estimate" "$interactive"
        done
        exit 0
        ;;
      *) input_file="$1"; [ -n "$2" ] && ! [[ "$2" =~ ^-- ]] && model="$2"; shift; break ;;
    esac
    shift
  done

  [ -z "$input_file" ] && { log_message "ERROR" "Input file required."; show_usage; }
  validate_input_file "$input_file"
  select_model "$input_file" "$model"
  generate_readme "$input_file" "$model" "$skip_estimate" "$interactive"
}

main "$@"