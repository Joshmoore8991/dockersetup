#!/bin/bash

# Exit script on error
set -e

# Define the installation directory
INSTALL_DIR="$HOME/opencti"
LOG_FILE="$INSTALL_DIR/setup_opencti.log"

# Docker Compose version check and update
DOCKER_COMPOSE_LATEST_VERSION="1.29.2"  # Set this to the latest stable version if different
DOCKER_COMPOSE_BIN="/usr/local/bin/docker-compose"

# Function to log messages
log_message() {
  echo "$(date "+%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
}

# Function to check and update Docker Compose
ensure_docker_compose() {
  log_message "Checking Docker Compose version..."

  # Get installed version of Docker Compose
  CURRENT_VERSION=$(docker-compose --version 2>/dev/null | awk '{print $3}' | sed 's/,//')

  if [ $? -ne 0 ]; then
    log_message "Docker Compose is not installed. Installing Docker Compose..."
    CURRENT_VERSION=""
  fi

  # Compare installed version with the latest version
  if [ "$CURRENT_VERSION" != "$DOCKER_COMPOSE_LATEST_VERSION" ]; then
    log_message "Docker Compose version is outdated or not installed. Installing/upgrading to version $DOCKER_COMPOSE_LATEST_VERSION..."

    # Install the latest version of Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o "$DOCKER_COMPOSE_BIN"
    sudo chmod +x "$DOCKER_COMPOSE_BIN"
    log_message "Docker Compose has been installed/upgraded to version $DOCKER_COMPOSE_LATEST_VERSION."
  else
    log_message "Docker Compose is already up to date (version $CURRENT_VERSION)."
  fi

  # Verify Docker Compose installation
  docker-compose --version
}

# Function to check and start Docker service
ensure_docker_running() {
  log_message "Checking Docker installation..."

  # Check if Docker is installed
  if ! command -v docker >/dev/null 2>&1; then
    log_message "Docker is not installed. Installing Docker..."
    sudo apt update >>"$LOG_FILE" 2>&1
    sudo apt install -y docker.io >>"$LOG_FILE" 2>&1
  fi

  # Check if Docker service is running
  if ! systemctl is-active --quiet docker; then
    log_message "Docker service is not running. Starting Docker..."
    sudo systemctl start docker >>"$LOG_FILE" 2>&1
    sudo systemctl enable docker >>"$LOG_FILE" 2>&1
  fi

  log_message "Verifying Docker Compose installation..."
  # Check if Docker Compose is installed
  if ! command -v docker-compose >/dev/null 2>&1; then
    log_message "Docker Compose is not installed. Installing Docker Compose..."
    sudo apt install -y docker-compose >>"$LOG_FILE" 2>&1
  fi

  log_message "Ensuring user permissions for Docker..."
  # Ensure the user is part of the Docker group
  if ! groups "$USER" | grep -q "\bdocker\b"; then
    log_message "Adding user to the Docker group..."
    sudo usermod -aG docker "$USER"
    log_message "Please log out and log back in, or run 'newgrp docker' to apply group changes."
    exit 1
  fi

  # Ensure Docker socket has the correct permissions
  log_message "Setting permissions for Docker socket..."
  sudo chmod 666 /var/run/docker.sock >>"$LOG_FILE" 2>&1

  # Test Docker connection
  log_message "Testing Docker connection..."
  if ! docker info >/dev/null 2>&1; then
    log_message "Failed to connect to Docker daemon. Ensure Docker is running and accessible."
    exit 1
  fi
}

# Call the Docker Compose version check function
ensure_docker_compose

# Call the Docker setup function
ensure_docker_running

# Clone or update the OpenCTI Docker repository
log_message "Setting up the OpenCTI Docker repository..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ -d "docker" ]; then
  if [ -d "docker/.git" ]; then
    log_message "Directory 'docker' exists and is a Git repository. Pulling latest changes..."
    cd docker
    git pull >>"$LOG_FILE" 2>&1
  else
    log_message "Directory 'docker' exists but is not a Git repository."
    log_message "Please move or delete the existing 'docker' directory and rerun the script."
    exit 1
  fi
else
  log_message "Cloning the OpenCTI Docker repository..."
  git clone https://github.com/OpenCTI-Platform/docker.git >>"$LOG_FILE" 2>&1
  cd docker
fi

# Generate .env file with default values
log_message "Generating .env file..."
(cat << EOF
OPENCTI_ADMIN_EMAIL=admin@opencti.io
OPENCTI_ADMIN_PASSWORD=ChangeMePlease
OPENCTI_ADMIN_TOKEN=$(cat /proc/sys/kernel/random/uuid)
OPENCTI_BASE_URL=http://localhost:8080
MINIO_ROOT_USER=$(cat /proc/sys/kernel/random/uuid)
MINIO_ROOT_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
RABBITMQ_DEFAULT_USER=guest
RABBITMQ_DEFAULT_PASS=guest
ELASTIC_MEMORY_SIZE=4G
CONNECTOR_HISTORY_ID=$(cat /proc/sys/kernel/random/uuid)
CONNECTOR_EXPORT_FILE_STIX_ID=$(cat /proc/sys/kernel/random/uuid)
CONNECTOR_EXPORT_FILE_CSV_ID=$(cat /proc/sys/kernel/random/uuid)
CONNECTOR_IMPORT_FILE_STIX_ID=$(cat /proc/sys/kernel/random/uuid)
CONNECTOR_EXPORT_FILE_TXT_ID=$(cat /proc/sys/kernel/random/uuid)
CONNECTOR_IMPORT_DOCUMENT_ID=$(cat /proc/sys/kernel/random/uuid)
SMTP_HOSTNAME=localhost
EOF
) > .env

# Ensure Redis service is defined
log_message "Ensuring Redis service is defined in docker-compose.yml..."
if ! grep -q "redis:" docker-compose.yml; then
  sed -i '/services:/a\
  redis:\n\
    image: redis:6.2\n\
    container_name: opencti_redis\n\
    restart: unless-stopped\n\
    healthcheck:\n\
      test: ["CMD", "redis-cli", "ping"]\n\
      interval: 10s\n\
      retries: 5\n\
      start_period: 5s\n' docker-compose.yml
fi

# Ensure OpenCTI depends on Redis
log_message "Ensuring OpenCTI depends on Redis in docker-compose.yml..."
if ! grep -q "depends_on:" docker-compose.yml; then
  sed -i '/opencti:/a\
    depends_on:\n\
      - redis' docker-compose.yml
fi

# Configure ElasticSearch system parameter
log_message "Configuring system parameters for ElasticSearch..."
sudo sysctl -w vm.max_map_count=1048575 >>"$LOG_FILE" 2>&1
if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
  echo "vm.max_map_count=1048575" | sudo tee -a /etc/sysctl.conf >>"$LOG_FILE" 2>&1
fi

# Run Docker Compose with logging to debug issues
log_message "Starting OpenCTI containers with logs..."
docker-compose up --build --remove-orphans | tee -a "$LOG_FILE"

# Check if docker-compose failed and manually start containers if needed
if [ $? -ne 0 ]; then
  log_message "docker-compose failed to start the containers. Checking for errors..."
  tail -n 50 "$LOG_FILE"  # Print the last 50 lines of the log

  log_message "Attempting to start containers manually for debugging..."

  # Start Redis container manually
  log_message "Starting Redis container manually..."
  docker run --name opencti_redis -d redis:6.2 >>"$LOG_FILE" 2>&1

  # Start OpenCTI container manually
  log_message "Starting OpenCTI container manually..."
  docker run --name opencti -d -p 8080:8080 --link opencti_redis:redis opencti/opencti >>"$LOG_FILE" 2>&1

  log_message "Check the containers manually to ensure they are working. You can use the following commands:"
  log_message "docker ps -a  # Check running containers"
  log_message "docker logs opencti_redis  # View Redis container logs"
  log_message "docker logs opencti  # View OpenCTI container logs"
fi

# Check the Docker Compose version to ensure compatibility
log_message "Checking Docker Compose version..."
docker-compose --version

# Inform user of the next steps
log_message "Check '$LOG_FILE' for detailed errors if the containers fail to start."
log_message "If the containers start manually, check the container logs for any specific issues."
