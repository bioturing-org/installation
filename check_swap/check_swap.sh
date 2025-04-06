#!/bin/bash

# Function to get the total physical memory in MB
get_physical_memory() {
  echo "Getting total physical memory..."

  if [ -f /proc/meminfo ]; then
    # Extract memory size from /proc/meminfo
    PHYSICAL_MEMORY=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    PHYSICAL_MEMORY=$((PHYSICAL_MEMORY / 1024))  # Convert from KB to MB
    echo "Total physical memory from /proc/meminfo: ${PHYSICAL_MEMORY}MB"
  elif command -v free &> /dev/null; then
    # Fallback to free if /proc/meminfo doesn't exist
    PHYSICAL_MEMORY=$(free -m | awk 'NR==2 {print $2}')
    echo "Total physical memory from free: ${PHYSICAL_MEMORY}MB"
  else
    echo "Error: Unable to determine physical memory using /proc/meminfo or free."
    exit 1
  fi
}

# Function to create swap file
create_swap() {
  # Calculate swap size as half of physical memory
  SWAP_SIZE=$((PHYSICAL_MEMORY / 2))

  if [ "$SWAP_SIZE" -lt 512 ]; then
    echo "Swap size too small ($SWAP_SIZE MB). Setting minimum to 512 MB."
    SWAP_SIZE=512
  fi

  echo "Allocating ${SWAP_SIZE}MB for swap file..."

  # Check if the swap file already exists
  if [ -f /swapfile ]; then
    echo "Swap file already exists. Skipping creation."
  else
    echo "Creating swap file at /swapfile..."
    # Create a swap file using dd
    dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    echo "/swapfile none swap sw 0 0" | tee -a /etc/fstab
    sync  # Ensure the disk writes are completed before activating swap
    swapon /swapfile
    echo "Swap file created and activated successfully."
  fi

  # Verify swap activation
  echo "Verifying swap activation..."
  swapon --show
  free -h

  # Check for any errors
  if [ $? -ne 0 ]; then
    echo "Error: Swap could not be activated."
  else
    echo "Swap successfully activated."
  fi
}

# Function to check if swap is available
check_swap() {
  echo "Checking swap..."
  SWAP_AVAILABLE=$(swapon --show)

  if [ -z "$SWAP_AVAILABLE" ]; then
    echo "No swap available, creating swap..."
    create_swap
  else
    echo "Swap is already available."
  fi
}

# Function to get root partition stats (in GB)
print_root_partition_stats() {
  echo -e "\nRoot Partition Info:"
  df -h / | awk 'NR==1 || NR==2'  # Show header and root partition
}

# Main function to execute the script
# Main function to execute the script
main() {
  get_physical_memory        # Step 1: Show total physical memory
  print_root_partition_stats # Step 2: Show root partition space info

  echo
  read -p "Do you want to create swap if it's not available? [y/n]: " CONFIRM_SWAP

  if [[ "$CONFIRM_SWAP" == "y" || "$CONFIRM_SWAP" == "Y" ]]; then
    check_swap               # Step 3: Check or create swap only if confirmed
  else
    echo "Swap creation skipped by user."
  fi
}

# Run the script
main