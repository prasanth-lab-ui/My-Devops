#!/usr/bin/env bash

# Trap Ctrl+C to restore cursor and clean up
trap 'echo -e "\033[?25h\033[0m"; exit 0' INT TERM EXIT

# Hide cursor
echo -e "\033[?25l"

# ANSI Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

clear

echo -e "${MAGENTA}${BOLD}"
cat << "EOF"
  ____  _______     ______  ____  ____    ____  ___ _____ _____ _     ___ _   _ _____ 
 |  _ \| ____\ \   / / _ \|  _ \/ ___|  |  _ \|_ _|_   _|_   _/ |   |_ _| \ | | ____|
 | | | |  _|  \ \ / / | | | |_) \___ \  | |_) || |  | |   | | | |    | ||  \| |  _|  
 | |_| | |___  \ V /| |_| |  __/ ___) | |  __/ | |  | |   | | | |___ | || |\  | |___ 
 |____/|_____|  \_/  \___/|_|   |____/  |_|   |___| |_|   |_| |_____|___|_| \_|_____|
EOF
echo -e "${RESET}"

# Funny fake DevOps deployment steps
steps=(
  "☕ Brewing espresso for the deployment hamsters..."
  "📦 Downloading the entire internet into node_modules..."
  "🐛 Converting critical bugs into 'undocumented features'..."
  "🔥 Ignoring 427 linter warnings..."
  "🙏 Praying to the Cloud Gods for zero downtime..."
  "🚀 Preparing for Friday evening production release..."
)

for step in "${steps[@]}"; do
  echo -ne " ${CYAN}⏳ ${step}${RESET}"
  for _ in {1..3}; do
    sleep 0.2
    echo -ne "."
  done
  sleep 0.2
  echo -e " ${GREEN}[ DONE ]${RESET}"
done

echo ""
sleep 0.5

# Countdown
for i in 3 2 1; do
  echo -ne "\r${YELLOW}${BOLD}💥 Ignition in: $i... ${RESET}"
  sleep 0.6
done
echo -e "\r${YELLOW}${BOLD}💥 Ignition: BLASTOFF! 🚀           ${RESET}\n"
sleep 0.3

# Rocket frames
frames=(
"
       ^
      / \\
     /   \\
    |=   =|
    |  D  |
    |  E  |
    |  V  |
    |  O  |
    |  P  |
    |  S  |
    | === |
    /|   |\\
   /_|___|_\\
      | |
     (   )
     (   )
"
"
       ^
      / \\
     /   \\
    |=   =|
    |  D  |
    |  E  |
    |  V  |
    |  O  |
    |  P  |
    |  S  |
    | === |
    /|   |\\
   /_|___|_\\
     (   )
      ) (
     (   )
"
"
       ^
      / \\
     /   \\
    |=   =|
    |  D  |
    |  E  |
    |  V  |
    |  O  |
    |  P  |
    |  S  |
    | === |
    /|   |\\
   /_|___|_\\
     ( . )
    (  *  )
   (   .   )
"
)

colors=("$RED" "$YELLOW" "$MAGENTA" "$CYAN")

# Animate rocket launching
for round in {1..12}; do
  frame_idx=$((round % 3))
  color_idx=$((round % 4))
  
  clear
  echo -e "${colors[$color_idx]}${BOLD}${frames[$frame_idx]}${RESET}"
  
  # Trailing exhaust
  for ((j=0; j<round/2; j++)); do
    echo -e "      ${YELLOW}* ${RED}. ${YELLOW}*${RESET}"
  done
  
  sleep 0.15
done

clear
echo -e "${GREEN}${BOLD}"
cat << "EOF"
  =======================================================
   🎉✨ DEPLOYMENT COMPLETE: IT WORKS ON MY MACHINE! ✨🎉
  =======================================================
EOF
echo -e "${CYAN}   Commit verified! No bugs detected (we didn't look).${RESET}\n"

# Restore cursor (handled by trap too)
echo -e "\033[?25h"
