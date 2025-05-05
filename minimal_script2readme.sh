#!/bin/zsh
# Minimal test script
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

APP_NAME="Script to README Generator"
APP_VERSION="1.5.0"
APP_AUTHOR="Ian Trimble"

echo -e "${CYAN}${BOLD}${APP_NAME}${RESET} ${WHITE}(v${APP_VERSION})${RESET}"
echo -e "${GRAY}Generates README documentation from script files using Ollama models${RESET}"

# Basic help display
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

echo "This is a simplified version of the script."