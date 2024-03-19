#!/bin/bash

# Log file paths
SUCCESS_LOG="success.log"
ERROR_LOG="error.log"
PORT_LOG="port_connection.log"

# Clean log files
rm -f "$SUCCESS_LOG" "$ERROR_LOG" "$PORT_LOG"

# Function to log success
log_success() {
    echo "$(date) - $1 is running." >> "$SUCCESS_LOG"
}

# Function to log error
log_error() {
    echo "$(date) - $1 is not running." >> "$ERROR_LOG"
}

# Check if Memcached is running
if ps -ef | grep -q '/usr/bin/memcached'; then
    log_success "Memcached"
else
    log_error "Memcached"
fi

# Check if PostgreSQL is running
if ps -ef | grep -q '/opt/bitnami/postgresql/bin/postgres'; then
    log_success "PostgreSQL"
else
    log_error "PostgreSQL"
fi

# Check if Redis is running
if ps -ef | grep -q '/usr/bin/redis-server'; then
    log_success "Redis"
else
    log_error "Redis"
fi

# Check if Nginx is running
if ps -ef | grep -q 'nginx: master process'; then
    log_success "Nginx"
else
    log_error "Nginx"
fi

# Check if HAProxy is running
if ps -ef | grep -q '/usr/local/sbin/haproxy'; then
    log_success "HAProxy"
else
    log_error "HAProxy"
fi

# Verify curl localhost
if curl -IsS localhost ; then
    log_success "Curl localhost"
else
    log_error "Curl localhost"
fi

# Verify port 11211 is running
if netstat -tuln | grep -q ':11211'; then
    log_success "Port 11211"
else
    log_error "Port 11211"
fi

# Read error log files and store content in error log file
for logfile in /var/log/supervisor/*_stderr.log; do
    if [ -s "$logfile" ]; then
        echo "===== $logfile =====" >> "$ERROR_LOG"
        grep -i "error" "$logfile" >> "$ERROR_LOG"
        echo "" >> "$ERROR_LOG"
    fi
done

echo "============================" > $PORT_LOG
netstat -nltup >> $PORT_LOG
