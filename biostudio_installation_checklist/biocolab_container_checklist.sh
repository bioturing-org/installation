#!/bin/bash

# Function to log success
log_success() {
    echo "$(date +"%Y-%m-%d %T") - $1 - SUCCESS" >> success.log
}

# Function to log error
log_error() {
    echo "$(date +"%Y-%m-%d %T") - $1 - ERROR: $2" >> error.log
}

# Function to log curl result
log_curl_result() {
    echo "$(date +"%Y-%m-%d %T") - $1 - $2" >> Application_curl.log
}

# Function to log file content to error.log
log_file_content() {
    echo "Content of $1:" >> error.log
    cat "$1" >> error.log
    echo "========================" >> error.log
}

# Clean up existing logs
clean_up_logs() {
    > error.log
    > success.log
    > Application_curl.log

    # Remove adm.png if it exists
    [ -f "adm.png" ] && rm adm.png

    # Remove 0w-byh0iNCWigGEjbZybU.92ae1dec-6bf9-4041-9d06-330e0fe7b564.zip if it exists
    [ -f "0w-byh0iNCWigGEjbZybU.92ae1dec-6bf9-4041-9d06-330e0fe7b564.zip" ] && rm 0w-byh0iNCWigGEjbZybU.92ae1dec-6bf9-4041-9d06-330e0fe7b564.zip

    # Remove adm.png.1 if it exists
    [ -f "adm.png.1" ] && rm adm.png.1
}

# Step 1: System Requirement Checks
check_system_requirements() {
    clean_up_logs
    # Check CPU cores
    cpu_cores=$(grep -c '^processor' /proc/cpuinfo)
    if [ "$cpu_cores" -ge 16 ]; then
        log_success "CPU Check"
    else
        log_error "CPU Check" "CPU cores are less than 16"
    fi

    # Check RAM
    total_ram=$(free -g | awk '/Mem:/{print $2}')
    if [ "$total_ram" -ge 64 ]; then
        log_success "RAM Check"
    else
        log_error "RAM Check" "RAM is less than 64GB"
    fi

    # Check / partition size
    partition_size=$(df -h / | awk 'NR==2 {print $4}')
    if [ "${partition_size%"G"}" -ge 100 ]; then
        log_success "/ Partition Check"
    else
        log_error "/ Partition Check" "/ partition size is less than 100GB"
    fi
}

# Step 2: Network Requirement Checks
check_network_requirements() {
    whitelist_domains=(
        "https://bioturing.com"
        "https://anaconda.org"
        "https://repo.anaconda.com"
        "https://colab.bioturing.com"
        "https://studio.bioturing.com"
        "github.com"
        "https://cdn.bioturing.com"
    )

    for domain in "${whitelist_domains[@]}"; do
        if curl -s -I "$domain" > /dev/null; then
            log_success "Network Whitelist Check - $domain"
        else
            log_error "Network Whitelist Check - $domain" "Failed to access $domain"
        fi
    done

    # Wget Test
    wget -q https://s3.us-west-2.amazonaws.com/cdn.bioturing.com/documentation/adm.png
    if [ $? -eq 0 ]; then
        log_success "wget Test - adm.png"
    else
        log_error "wget Test - adm.png" "Failed to download adm.png"
    fi

    wget -q https://cdn-eu-west-1.s3.eu-west-1.amazonaws.com/colab/apps/0w-byh0iNCWigGEjbZybU.92ae1dec-6bf9-4041-9d06-330e0fe7b564.zip
    if [ $? -eq 0 ]; then
        log_success "wget Test - colab.zip"
    else
        log_error "wget Test - colab.zip" "Failed to download colab.zip"
    fi

    wget -q https://cdn.bioturing.com/documentation/adm.png
    if [ $? -eq 0 ]; then
        log_success "wget Test - adm.png"
    else
        log_error "wget Test - adm.png" "Failed to download adm.png"
    fi
}

# Step 3: Application Port Status Checks
check_application_ports() {
    # Check if application port is running
    if lsof -i :11123 > /dev/null; then
        log_success "Application Port 11123 Check"
    else
        log_error "Application Port 11123 Check" "Port 11123 is not running"
    fi
}

# Step 4: Check for processes
check_process() {
    processes=("miniconda" "aria2c" "t2d_dsc_tool" "t2d_blc_tool")

    for process in "${processes[@]}"; do
        if pgrep -f "$process" > /dev/null; then
            log_success "Process Check - $process"
        else
            log_error "Process Check - $process" "$process is not running"
        fi
    done
}

# Step 5: Check Application status using curl
curl_verification() {
    # Perform curl to localhost:11123
    localhost_11123_curl_output=$(curl -s "localhost:11123")
    if [ $? -eq 0 ]; then
        log_success "Curl Check - localhost:11123"
    else
        log_error "Curl Check - localhost:11123" "Failed to connect to localhost:11123"
    fi
    # Log the output of curl to localhost:11123
    log_curl_result "Curl Check - localhost:11123" "$localhost_11123_curl_output"
}

# Step 6: Check Supervisiord process
check_supervisord() {
    if pgrep supervisord > /dev/null; then
        log_success "Process Check - supervisord"
    else
        log_error "Process Check - supervisord" "supervisord is not running"
    fi
}

# Step 7: Check File availability
licence_file_availability() {
    if ls /appdata/.bbcache/*.license >/dev/null 2>&1 && ls /appdata/.bbcache/*.license_bk >/dev/null 2>&1; then
        log_success "File Check - License Files"
    else
        log_error "File Check - License Files" "One or both license files are missing"
    fi
}

# Step 8: Check the existence of t2d_dsc_tool and t2d_blc_tool processes in /appdata/apps folder
check_process_files() {
    if [ -x "/appdata/apps/t2d_dsc_tool" ] && [ -x "/appdata/apps/t2d_blc_tool" ]; then
        log_success "Process File Check - t2d_dsc_tool and t2d_blc_tool"
    else
        log_error "Process File Check - t2d_dsc_tool and t2d_blc_tool" "One or both process files are missing"
    fi
}

# Step 9: Verify Application Logs
verify_application_logs() {
    log_files=(
        "/var/log/supervisor/aria2c_stderr.log"
        "/var/log/supervisor/colab_stderr.log"
        "/var/log/supervisor/mosquitto_stderr.log"
        "/var/log/supervisor/colabblc_stderr.log"
        "/var/log/supervisor/beanstalkd_stderr.log"
        "/var/log/supervisor/bhub-create-custom-task-worker_stderr.log"
        "/var/log/supervisor/bhub-create-kernel-worker_stderr.log"
        "/var/log/supervisor/bhub-pack-notebook-worker_stderr.log"
        "/var/log/supervisor/bhub-setup-notebook-worker_stderr.log"
        "/var/log/supervisor/jupyterhub_stderr.log"
        "/var/log/supervisor/mosquitto_stderr.log"
        "/var/log/supervisor/bhub-setup-notebook-worker_stdout.log"
    )

    for log_file in "${log_files[@]}"; do
        if grep -qi "error" "$log_file"; then
            # Remove duplicate lines and keep only one instance of each unique line
            awk '!seen[$0]++' "$log_file" > tmp.log && mv tmp.log "$log_file"
            log_error "Application Log Check" "Error found in $log_file"
            log_file_content "$log_file"
        else
            log_success "Application Log Check - $log_file"
        fi
    done
}

# Step 10: Check PID Stability
check_pid_stability() {
    # Start watching PIDs for t2d_blc_tool and t2d_dsc_tool
    pids_blc=$(pgrep -f "t2d_blc_tool")
    pids_dsc=$(pgrep -f "t2d_dsc_tool")

    # Sleep for 1 minute
    sleep 60

    # Check if the PIDs are still the same after 1 minute
    new_pids_blc=$(pgrep -f "t2d_blc_tool")
    new_pids_dsc=$(pgrep -f "t2d_dsc_tool")

    if [ "$pids_blc" = "$new_pids_blc" ] && [ "$pids_dsc" = "$new_pids_dsc" ]; then
        log_success "PID Stability Check - t2d_blc_tool and t2d_dsc_tool"
    else
        log_error "PID Stability Check - t2d_blc_tool and t2d_dsc_tool" "PIDs for t2d_blc_tool or t2d_dsc_tool changed"
    fi
}

# Step 11: Function to test Telnet connection
test_telnet_connection() {
   # apt-get update && apt-get install -y netcat
    local ip_address="$1"
    local port="$2"

    # Introduce a delay before attempting the connection
    sleep 1

    if nc -z -w 5 "$ip_address" "$port" </dev/null; then
        log_success "Telnet Test - $ip_address:$port"
    else
        log_error "Telnet Test - $ip_address:$port" "Failed to connect to $ip_address:$port"
        # Add debug output
        echo "Connection failed for $ip_address:$port" >&2
    fi
}

# Function to obtain container IP
get_container_ip() {
    ip_address=$(ifconfig eth0 | awk '/inet /{print $2}')
    echo "$ip_address"
}

# Function to obtain container IP and test Telnet connections
obtain_container_ip_and_test_telnet() {
    echo "Feel free to check server status using https:<domain name>/server_status"
    local container_ip
    container_ip=$(get_container_ip)

    if [ -n "$container_ip" ]; then
        # Display BioColab IP address
        echo "BioColab IP address is: $container_ip"

        # Prompt for BioProxy container IP
        read -p "Enter BioProxy container IP address: " bioproxy_ip

        # Test PostgreSQL connection
        test_telnet_connection "$bioproxy_ip" 5432

        # Test Redis connection
        test_telnet_connection "$bioproxy_ip" 6379
    else
        log_error "Container IP Address Retrieval" "Failed to retrieve container IP address"
    fi
}

confirm_biocolab_ip() {
        # Display Biocolab IP address
        # echo "Biocolab IP address is: $biocolab_ip"
        read -p "Do you have the correct Biocolab IP address? (Y/n): " confirm_ip

        if [[ $confirm_ip == "Y" || $confirm_ip == "y" ]]; then
            # Execute main function
            main
        else
            echo "Please ensure you have the correct Biocolab IP address before running this script."
            exit 1
        fi
}

# Main function
main() {
    check_system_requirements
    check_network_requirements
    check_application_ports
    check_process
    curl_verification
    check_supervisord
    licence_file_availability
    check_process_files
    verify_application_logs
    check_pid_stability
    obtain_container_ip_and_test_telnet
}

confirm_biocolab_ip