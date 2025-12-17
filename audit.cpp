#include <iostream>
#include <fstream>
#include <unistd.h>
#include <sys/wait.h>
#include <ctime>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>

class SystemAuditor {
private:
    std::string log_file;
    
    std::string get_current_time() {
        auto now = std::time(nullptr);
        auto tm = *std::localtime(&now);
        std::ostringstream oss;
        oss << std::put_time(&tm, "%Y-%m-%d %H:%M:%S");
        return oss.str();
    }
    
    void log_event(const std::string& message, const std::string& level = "INFO") {
        std::ofstream file(log_file, std::ios::app);
        std::string log_entry = "[" + get_current_time() + "] [" + level + "] " + message;
        file << log_entry << std::endl;
        std::cout << log_entry << std::endl;
    }
    
    bool perform_disk_check() {
        log_event("Checking disk usage and health...");
        std::cout << "[DISK] Current disk usage:" << std::endl;
        system("df -h / | head -2");
        sleep(1);
        log_event("Disk check completed", "SUCCESS");
        return true;
    }
    
    bool perform_memory_analysis() {
        log_event("Analyzing memory usage patterns...");
        std::cout << "[MEMORY] Current memory usage:" << std::endl;
        system("free -h");
        sleep(1);
        log_event("Memory analysis completed", "SUCCESS");
        return true;
    }
    
    bool perform_process_scan() {
        log_event("Scanning running processes...");
        std::cout << "[PROCESSES] Top 5 processes by CPU:" << std::endl;
        system("ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu --no-headers | head -5");
        sleep(1);
        log_event("Process scan completed", "SUCCESS");
        return true;
    }
    
    bool perform_network_check() {
        log_event("Checking network connectivity...");
        int result = system("ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1");
        if (result == 0) {
            log_event("Network connectivity: OK", "SUCCESS");
        } else {
            log_event("Network connectivity: FAILED", "WARNING");
        }
        return result == 0;
    }

public:
    SystemAuditor(const std::string& log_path) : log_file(log_path) {}
    
    void run_comprehensive_audit(const std::string& cycle_id) {
        log_event("STARTING AUDIT CYCLE " + cycle_id, "INFO");
        
        pid_t pid = fork();
        
        if (pid == 0) {
            log_event("Child process started - performing detailed system checks", "INFO");
            
            std::vector<std::pair<std::string, bool>> checks = {
                {"Disk Analysis", perform_disk_check()},
                {"Memory Analysis", perform_memory_analysis()},
                {"Process Scan", perform_process_scan()},
                {"Network Check", perform_network_check()}
            };
            
            int success_count = 0;
            for (const auto& check : checks) {
                if (check.second) success_count++;
            }
            
            log_event("All system checks completed: " + std::to_string(success_count) + 
                     "/" + std::to_string(checks.size()) + " passed", "SUCCESS");
            exit(0);
        } 
        else if (pid > 0) {
            log_event("Parent process monitoring child execution", "INFO");
            int status;
            waitpid(pid, &status, 0);
            
            if (WIFEXITED(status)) {
                log_event("Child process completed successfully - Exit code: " + 
                         std::to_string(WEXITSTATUS(status)), "SUCCESS");
            } else {
                log_event("Child process terminated abnormally", "ERROR");
            }
        } else {
            log_event("Fork operation failed - cannot create child process", "ERROR");
        }
        
        log_event("AUDIT CYCLE " + cycle_id + " COMPLETED", "INFO");
    }
};

int main(int argc, char* argv[]) {
    std::string cycle_id = (argc > 1) ? argv[1] : "MANUAL";
    SystemAuditor auditor("./logs/uniguard.log");
    auditor.run_comprehensive_audit(cycle_id);
    return 0;
}
