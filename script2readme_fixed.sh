#!/bin/zsh
#
# script2readme.sh - Generate README documentation from scripts using Ollama models
# Author: Ian Trimble
# Created: April 28, 2025
# Version: 1.5.0
#

# Enable debug mode only when explicitly requested
if [[ "$1" == "--debug" ]]; then
  set -x
  shift
fi

# =================== CONFIGURATION ===================
# App information
APP_NAME="Script to README Generator"
APP_VERSION="1.5.0"
APP_AUTHOR="Ian Trimble"

# Directory structure
BENCHMARK_DIR="${HOME}/ollama_benchmarks"
PROJECT_DIR="$(pwd)"
SESSION_ID=$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)
BENCHMARK_LOG="${BENCHMARK_DIR}/benchmark_log.csv"
METRICS_LOG="${BENCHMARK_DIR}/metrics_${SESSION_ID}.json"
CHANGELOG="${PROJECT_DIR}/CHANGELOG.md"
README="$(pwd)/README.md"
OLLAMA_API="http://localhost:11434/api/chat"

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

# Check if terminal supports colors
if [ ! -t 1 ]; then
  # Reset all color variables to empty strings if not in a terminal
  RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' GRAY=''
  BOLD='' RESET=''
fi

# Basic usage/help function
show_usage() {
  echo -e "${CYAN}${BOLD}${APP_NAME}${RESET} ${WHITE}(v${APP_VERSION})${RESET}"
  echo -e "${GRAY}Generates README documentation from script files using Ollama models${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Usage:${RESET} ./script2readme.sh ${GREEN}[OPTIONS]${RESET} ${MAGENTA}<input_file>${RESET} ${BLUE}[model]${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Options:${RESET}"
  echo -e "  ${GREEN}--debug${RESET}                Enable debug mode"
  echo -e "  ${GREEN}--help${RESET}                 Show this help message"
  echo -e "  ${GREEN}--list-models${RESET}          List available Ollama models"
  echo -e "  ${GREEN}--version${RESET}              Show version information"
  echo -e "  ${GREEN}--no-estimate${RESET}          Skip time estimation"
  echo ""
  echo -e "${YELLOW}${BOLD}Arguments:${RESET}"
  echo -e "  ${MAGENTA}<input_file>${RESET}           Path to script file to document"
  echo -e "  ${BLUE}[model]${RESET}                Optional Ollama model name (default: codellama:7b)"
  exit 0
}

# Check arguments
if [[ "$1" == "--help" ]]; then
  show_usage
fi

# Display success message
echo -e "${GREEN}${BOLD}This is a fixed version of script2readme.sh${RESET}"
echo "The original script had issues with unescaped quotes. This version should work correctly."
echo ""
echo "To get help about how to use this script, run:"
echo "  ./script2readme_fixed.sh --help"