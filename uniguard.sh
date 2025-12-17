#!/bin/bash

LOG_DIR="./logs"
DATA_DIR="./data"
REPORTS_DIR="./reports"
CONFIG_FILE="./config.cfg"
PID_FILE="./uniguard.pid"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'

init_directories() {
    mkdir -p "$LOG_DIR" "$DATA_DIR" "$REPORTS_DIR"
    [ ! -f "$DATA_DIR/cpu_history.csv" ] && echo "timestamp,cpu_usage" > "$DATA_DIR/cpu_history.csv"
    [ ! -f "$DATA_DIR/mem_history.csv" ] && echo "timestamp,mem_usage" > "$DATA_DIR/mem_history.csv"
    [ ! -f "$DATA_DIR/disk_history.csv" ] && echo "timestamp,disk_usage" > "$DATA_DIR/disk_history.csv"
    [ ! -f "$LOG_DIR/uniguard.log" ] && touch "$LOG_DIR/uniguard.log"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        DASHBOARD_REFRESH=3
        LOG_LEVEL="INFO"
        GRAPH_REPORTS=true
        CPU_SAFE_MAX=85
        MEM_SAFE_MAX=80
        AUTO_HEAL=false
    fi
}

print_header() {
    clear
    echo -e "${BOLD}${CYAN}UniGuard++ System Monitor${RESET}"
    echo -e "${CYAN}==========================${RESET}"
}

get_accurate_cpu() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -d'.' -f1)
    echo "${cpu_usage:-0}"
}

get_accurate_mem() {
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    echo "${mem_usage:-0}"
}

get_accurate_disk() {
    local disk_usage=$(df / --output=pcent | tail -1 | tr -d ' %')
    echo "${disk_usage:-0}"
}

run_audit_cycle() {
    local cycle_id=$(date +%s)
    echo -e "${BLUE}[INFO]${RESET} Starting audit cycle ${BOLD}$cycle_id${RESET}" | tee -a "$LOG_DIR/uniguard.log"
    echo -e "${CYAN}[STEP 1]${RESET} Initializing system checks..." | tee -a "$LOG_DIR/uniguard.log"
    
    if ! ./audit "$cycle_id" 2>&1 | tee -a "$LOG_DIR/uniguard.log"; then
        echo -e "${RED}[ERROR]${RESET} Audit execution failed" | tee -a "$LOG_DIR/uniguard.log"
        return 1
    fi
    
    echo -e "${CYAN}[STEP 2]${RESET} Gathering system metrics..." | tee -a "$LOG_DIR/uniguard.log"
    local CPU=$(get_accurate_cpu)
    local MEM=$(get_accurate_mem)
    local DISK=$(get_accurate_disk)
    local TIMESTAMP=$(date +%s)
    
    echo "$TIMESTAMP,$CPU" >> "$DATA_DIR/cpu_history.csv"
    echo "$TIMESTAMP,$MEM" >> "$DATA_DIR/mem_history.csv" 
    echo "$TIMESTAMP,$DISK" >> "$DATA_DIR/disk_history.csv"
    
    echo -e "${CYAN}[STEP 3]${RESET} Analyzing system health..." | tee -a "$LOG_DIR/uniguard.log"
    local health_status="HEALTHY"
    if [ "$CPU" -gt "${CPU_SAFE_MAX:-85}" ] || [ "$MEM" -gt "${MEM_SAFE_MAX:-80}" ]; then
        health_status="WARNING"
    fi
    
    echo -e "${GREEN}[SUCCESS]${RESET} Audit completed!" | tee -a "$LOG_DIR/uniguard.log"
    echo -e "   CPU: ${BOLD}$CPU%${RESET} | Memory: ${BOLD}$MEM%${RESET} | Disk: ${BOLD}$DISK%${RESET}" | tee -a "$LOG_DIR/uniguard.log"
    echo -e "   Status: ${BOLD}$health_status${RESET} | Cycle: ${BOLD}$cycle_id${RESET}" | tee -a "$LOG_DIR/uniguard.log"
    echo "---" >> "$LOG_DIR/uniguard.log"
}

start_monitoring() {
    echo -e "${YELLOW}[INFO]${RESET} Starting continuous monitoring..." | tee -a "$LOG_DIR/uniguard.log"
    echo "Monitoring PID: $$" > "$PID_FILE"
    
    trap "echo -e '${YELLOW}[INFO]${RESET} Monitoring stopped.' | tee -a '$LOG_DIR/uniguard.log'; rm -f '$PID_FILE'; exit 0" SIGINT SIGTERM
    
    local cycle_count=0
    while true; do
        ((cycle_count++))
        echo -e "${CYAN}Monitoring Cycle #$cycle_count${RESET}" | tee -a "$LOG_DIR/uniguard.log"
        run_audit_cycle
        echo -e "${BLUE}[WAIT]${RESET} Next cycle in 3 seconds..." | tee -a "$LOG_DIR/uniguard.log"
        sleep 3
    done
}

show_logs() {
    print_header
    echo -e "${BOLD}${YELLOW}Recent Audit Logs${RESET}"
    echo -e "${CYAN}=================${RESET}"
    
    if [ -f "$LOG_DIR/uniguard.log" ] && [ -s "$LOG_DIR/uniguard.log" ]; then
        local log_count=$(wc -l < "$LOG_DIR/uniguard.log")
        echo -e "Total log entries: ${BOLD}$log_count${RESET}"
        echo -e "Last updated: ${BOLD}$(stat -c %y "$LOG_DIR/uniguard.log" 2>/dev/null || echo "Unknown")${RESET}"
        
        local recent_logs=$(grep -A 5 -B 5 "$(date -d '10 minutes ago' '+%Y-%m-%d %H:%M')" "$LOG_DIR/uniguard.log" 2>/dev/null || tail -30 "$LOG_DIR/uniguard.log")
        
        if [ -z "$recent_logs" ]; then
            recent_logs=$(tail -30 "$LOG_DIR/uniguard.log")
        fi
        
        echo "$recent_logs" | while IFS= read -r line; do
            if [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"FAILED"* ]]; then
                echo -e "${RED}$line${RESET}"
            elif [[ "$line" == *"WARNING"* ]]; then
                echo -e "${YELLOW}$line${RESET}"
            elif [[ "$line" == *"SUCCESS"* ]] || [[ "$line" == *"OK"* ]] || [[ "$line" == *"completed"* ]]; then
                echo -e "${GREEN}$line${RESET}"
            elif [[ "$line" == *"INFO"* ]] || [[ "$line" == *"STEP"* ]]; then
                echo -e "${BLUE}$line${RESET}"
            else
                echo -e "${WHITE}$line${RESET}"
            fi
        done
    else
        echo -e "${RED}No log entries found${RESET}"
        echo -e "Run an audit first to generate logs"
    fi
}

generate_report() {
    echo -e "${BLUE}[INFO]${RESET} Generating comprehensive system report..." | tee -a "$LOG_DIR/uniguard.log"
    local REPORT_FILE="$REPORTS_DIR/report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "UniGuard++ System Report"
        echo "Generated: $(date)"
        echo "System: $(uname -srm)"
        echo "Current CPU Usage: $(get_accurate_cpu)%"
        echo "Current Memory Usage: $(get_accurate_mem)%"
        echo "Current Disk Usage: $(get_accurate_disk)%"
        echo "Running Processes: $(ps -e --no-headers | wc -l)"
        echo "System Uptime: $(uptime -p)"
        echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
        echo "Recent Audit History:"
        tail -5 "$DATA_DIR/cpu_history.csv" 2>/dev/null | while IFS= read -r line; do
            local ts=$(echo "$line" | cut -d',' -f1)
            local cpu=$(echo "$line" | cut -d',' -f2)
            echo "  $(date -d "@$ts" '+%H:%M:%S'): CPU=$cpu%"
        done
    } > "$REPORT_FILE"
    
    echo -e "${GREEN}[SUCCESS]${RESET} Report saved: ${BOLD}$REPORT_FILE${RESET}" | tee -a "$LOG_DIR/uniguard.log"
}

show_graphs() {
    if ! command -v gnuplot &> /dev/null; then
        echo -e "${RED}[ERROR]${RESET} gnuplot is required for graphs. Install with: sudo apt-get install gnuplot" | tee -a "$LOG_DIR/uniguard.log"
        return 1
    fi
    
    echo -e "${BLUE}[INFO]${RESET} Generating system usage graphs..." | tee -a "$LOG_DIR/uniguard.log"
    
    local graph_file="$REPORTS_DIR/graphs_$(date +%Y%m%d_%H%M%S).png"
    
    gnuplot << EOF
set terminal png size 1200,800
set output "$graph_file"
set multiplot layout 2,2 title "UniGuard++ System Metrics"

set title "CPU Usage History"
set xlabel "Time"
set ylabel "CPU Usage %"
set yrange [0:100]
set grid
plot "$DATA_DIR/cpu_history.csv" using 1:2 with lines linewidth 2 title "CPU %"

set title "Memory Usage History"
set xlabel "Time"
set ylabel "Memory Usage %"
set yrange [0:100]
set grid
plot "$DATA_DIR/mem_history.csv" using 1:2 with lines linewidth 2 title "Memory %"

set title "Disk Usage History"
set xlabel "Time"
set ylabel "Disk Usage %"
set yrange [0:100]
set grid
plot "$DATA_DIR/disk_history.csv" using 1:2 with lines linewidth 2 title "Disk %"

set title "Current System Status"
set xlabel "Metric"
set ylabel "Usage %"
set style data histogram
set style histogram cluster gap 1
set style fill solid border -1
set boxwidth 0.8
set yrange [0:100]
plot '-' using 2:xtic(1) title "Current Usage"
"CPU" $(get_accurate_cpu)
"Memory" $(get_accurate_mem)
"Disk" $(get_accurate_disk)
e

unset multiplot
EOF

    echo -e "${GREEN}[SUCCESS]${RESET} Graphs generated: ${BOLD}$graph_file${RESET}" | tee -a "$LOG_DIR/uniguard.log"
}

show_system_status() {
    print_header
    echo -e "${BOLD}${YELLOW}Current System Status${RESET}"
    echo -e "${CYAN}=====================${RESET}"
    
    local CPU=$(get_accurate_cpu)
    local MEM=$(get_accurate_mem)
    local DISK=$(get_accurate_disk)
    
    echo -e "CPU Usage:    $(colorize_percent $CPU) $CPU%"
    echo -e "Memory Usage: $(colorize_percent $MEM) $MEM%"
    echo -e "Disk Usage:   $(colorize_percent $DISK) $DISK%"
    echo -e "Processes:    $(ps -e --no-headers | wc -l)"
    echo -e "Uptime:       $(uptime -p | sed 's/up //')"
    echo -e "Load Average: $(uptime | awk -F'load average:' '{print $2}' | xargs)"
    
    echo ""
    echo -e "${BOLD}${YELLOW}Recent Activity${RESET}"
    if [ -f "$DATA_DIR/cpu_history.csv" ] && [ -s "$DATA_DIR/cpu_history.csv" ]; then
        echo "Last 5 CPU readings:"
        tail -5 "$DATA_DIR/cpu_history.csv" | while IFS= read -r line; do
            local ts=$(echo "$line" | cut -d',' -f1)
            local cpu=$(echo "$line" | cut -d',' -f2)
            echo -e "  $(date -d "@$ts" '+%H:%M:%S') - ${BOLD}$cpu%${RESET}"
        done
    else
        echo "  No audit data available"
    fi
}

colorize_percent() {
    local value=$1
    if [ "$value" -lt 50 ]; then
        echo -e "${GREEN}$value${RESET}"
    elif [ "$value" -lt 80 ]; then
        echo -e "${YELLOW}$value${RESET}"
    else
        echo -e "${RED}$value${RESET}"
    fi
}

show_menu() {
    while true; do
        print_header
        echo -e "${BOLD}${GREEN}Main Menu:${RESET}"
        echo -e "${CYAN}1)${RESET} Run single audit"
        echo -e "${CYAN}2)${RESET} Continuous monitoring" 
        echo -e "${CYAN}3)${RESET} View system logs"
        echo -e "${CYAN}4)${RESET} Live dashboard"
        echo -e "${CYAN}5)${RESET} Generate report"
        echo -e "${CYAN}6)${RESET} Show graphs"
        echo -e "${CYAN}7)${RESET} System status"
        echo -e "${CYAN}8)${RESET} Open configuration"
        echo -e "${CYAN}9)${RESET} Exit"
        
        read -rp "Select an option [1-9]: " choice
        
        case $choice in
            1) run_audit_cycle; pause ;;
            2) start_monitoring ;;
            3) show_logs; pause ;;
            4) bash ./dashboard.sh ;;
            5) generate_report; pause ;;
            6) show_graphs; pause ;;
            7) show_system_status; pause ;;
            8) ${EDITOR:-nano} "$CONFIG_FILE" ;;
            9) echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;;
            *) echo -e "${RED}Invalid choice. Please try again.${RESET}"; sleep 1 ;;
        esac
    done
}

pause() {
    echo -e "${YELLOW}Press Enter to continue...${RESET}"
    read -r
}

init_directories
load_config
show_menu
