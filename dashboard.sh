#!/bin/bash

[ -f "./config.cfg" ] && source "./config.cfg"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'

get_accurate_cpu_usage() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}' | cut -d'.' -f1)
    if [ -z "$cpu_usage" ] || [ "$cpu_usage" -eq 0 ]; then
        cpu_usage=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}' | cut -d'.' -f1)
    fi
    if [ -z "$cpu_usage" ] || [ "$cpu_usage" -gt 100 ]; then
        cpu_usage=0
    fi
    echo "$cpu_usage"
}

get_accurate_mem_usage() {
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    echo "$mem_usage"
}

get_accurate_disk_usage() {
    local disk_usage=$(df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %')
    if [ -z "$disk_usage" ]; then
        disk_usage=$(df / | awk 'NR==2 {gsub("%",""); print $5}')
    fi
    echo "$disk_usage"
}

draw_bar() {
    local percent=$1
    local label=$2
    local length=35
    local filled=$((percent * length / 100))
    local empty=$((length - filled))

    if [ "$filled" -lt 0 ]; then filled=0; fi
    if [ "$filled" -gt "$length" ]; then filled=$length; fi
    if [ "$empty" -lt 0 ]; then empty=0; fi

    if [ "$percent" -lt 50 ]; then 
        local color=$GREEN
        local status="OK"
    elif [ "$percent" -lt 80 ]; then 
        local color=$YELLOW
        local status="WARNING"
    else 
        local color=$RED
        local status="CRITICAL"
    fi

    printf "%-12s [" "$label"
    printf "${color}${BOLD}"
    for ((i=0; i<filled; i++)); do printf "#"; done
    printf "${RESET}"
    for ((i=0; i<empty; i++)); do printf "."; done
    printf "] ${color}%3d%%${RESET} ${BOLD}[%s]${RESET}" "$percent" "$status"
}

get_system_uptime() {
    uptime -p | sed 's/up //'
}

get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | xargs
}

get_top_processes() {
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu --no-headers 2>/dev/null | head -5
}

show_mini_graph() {
    local metric=$1
    local file=$2
    local title=$3
    
    echo -e "  ${BOLD}${WHITE}$title - Last 10 readings:${RESET}"
    if [ -f "$file" ] && [ -s "$file" ]; then
        local values=$(tail -10 "$file" 2>/dev/null | cut -d',' -f2 | tr '\n' ' ')
        if [ -n "$values" ]; then
            echo -n "  "
            for value in $values; do
                if [ "$value" -lt 50 ]; then
                    echo -ne "${GREEN}#${RESET}"
                elif [ "$value" -lt 80 ]; then
                    echo -ne "${YELLOW}|${RESET}"
                else
                    echo -ne "${RED}!${RESET}"
                fi
            done
            echo " [Last: $(echo "$values" | awk '{print $NF}')%]"
        else
            echo "  No data available"
        fi
    else
        echo "  No data available"
    fi
}

while true; do
    clear
    echo -e "${BOLD}${CYAN}UniGuard++ Live Dashboard${RESET}"
    echo -e "${CYAN}=========================${RESET}"
    echo -e "Time: ${WHITE}$(date)${RESET}"
    echo -e "Uptime: ${GREEN}$(get_system_uptime)${RESET}"
    echo -e "Load Average: ${YELLOW}$(get_load_average)${RESET}"
    echo ""
    
    echo -e "${BOLD}Resource Usage:${RESET}"
    echo -e "${BLUE}---------------${RESET}"
    
    local CPU=$(get_accurate_cpu_usage)
    local MEM=$(get_accurate_mem_usage)
    local DISK=$(get_accurate_disk_usage)
    
    if [ -z "$CPU" ] || [ "$CPU" -gt 100 ]; then CPU=0; fi
    if [ -z "$MEM" ] || [ "$MEM" -gt 100 ]; then MEM=0; fi
    if [ -z "$DISK" ] || [ "$DISK" -gt 100 ]; then DISK=0; fi
    
    draw_bar "$CPU" "CPU"
    echo ""
    
    draw_bar "$MEM" "Memory" 
    echo ""
    
    draw_bar "$DISK" "Disk"
    echo ""
    
    local PROC_COUNT=$(ps -e --no-headers 2>/dev/null | wc -l)
    echo -e "Active Processes: ${WHITE}${BOLD}$PROC_COUNT${RESET}"
    
    echo ""
    echo -e "${BOLD}Resource Trends:${RESET}"
    echo -e "${BLUE}----------------${RESET}"
    show_mini_graph "cpu" "./data/cpu_history.csv" "CPU History"
    show_mini_graph "mem" "./data/mem_history.csv" "Memory History"
    show_mini_graph "disk" "./data/disk_history.csv" "Disk History"
    
    echo ""
    echo -e "${BOLD}Top Processes (by CPU):${RESET}"
    echo -e "${BLUE}-----------------------${RESET}"
    local top_procs=$(get_top_processes)
    if [ -n "$top_procs" ]; then
        printf "  ${BOLD}%-6s %-6s %-20s %-4s %-4s${RESET}\n" "PID" "PPID" "COMMAND" "MEM%" "CPU%"
        echo "$top_procs" | while read -r line; do
            printf "  %s\n" "$line"
        done
    else
        echo "  No processes found"
    fi
    
    echo ""
    echo -e "${YELLOW}Refresh: ${DASHBOARD_REFRESH:-2}s | Press Ctrl+C to exit${RESET}"
    sleep "${DASHBOARD_REFRESH:-2}"
done
