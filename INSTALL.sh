#!/bin/bash

# Exit script on error
set -e

# Define the installation directory
INSTALL_DIR="$HOME/opencti"

# Function to check and start Docker service
ensure_docker_running() {
  echo "Checking Docker installation..."
  
  # Check if Docker is installed
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed. Installing Docker..."
    sudo apt update
    sudo apt install -y docker.io
  fi

  # Check if Docker service is running
  if ! systemctl is-active --quiet docker; then
    echo "Docker service is not running. Starting Docker..."
    sudo systemctl start docker
    sudo systemctl enable docker
  fi

  echo "Verifying Docker Compose installation..."
  # Check if Docker Compose is installed
  if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Docker Compose is not installed. Installing Docker Compose..."
    sudo apt install -y docker-compose
  fi

  echo "Ensuring user permissions for Docker..."
  # Ensure the user is part of the Docker group
  if ! groups "$USER" | grep -q "\bdocker\b"; then
    echo "Adding user to the Docker group..."
    sudo usermod -aG docker "$USER"
    echo "Please log out and log back in, or run 'newgrp docker' to apply group changes."
    exit 1
  fi

  # Ensure Docker socket has the correct permissions
  echo "Setting permissions for Docker socket..."
  sudo chmod 666 /var/run/docker.sock

  # Test Docker connection
  echo "Testing Docker connection..."
  if ! docker info >/dev/null 2>&1; then
    echo "Failed to connect to Docker daemon. Ensure Docker is running and accessible."
    exit 1
  fi
}

# Call the Docker setup function
ensure_docker_running

# Clone or update the OpenCTI Docker repository
echo "Setting up the OpenCTI Docker repository..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ -d "docker" ]; then
  if [ -d "docker/.git" ]; then
    echo "Directory 'docker' exists and is a Git repository. Pulling latest changes..."
    cd docker
    git pull
  else
    echo "Directory 'docker' exists but is not a Git repository."
    echo "Please move or delete the existing 'docker' directory and rerun the script."
    exit 1
  fi
else
  echo "Cloning the OpenCTI Docker repository..."
  git clone https://github.com/OpenCTI-Platform/docker.git
  cd docker
fi

# Generate .env file with default values
echo "Generating .env file..."
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
echo "Ensuring Redis service is defined in docker-compose.yml..."
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
echo "Ensuring OpenCTI depends on Redis in docker-compose.yml..."
if ! grep -q "depends_on:" docker-compose.yml; then
  sed -i '/opencti:/a\
    depends_on:\n\
      - redis' docker-compose.yml
fi

# Configure ElasticSearch system parameter
echo "Configuring system parameters for ElasticSearch..."
sudo sysctl -w vm.max_map_count=1048575
if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
  echo "vm.max_map_count=1048575" | sudo tee -a /etc/sysctl.conf
fi

# Run Docker Compose
echo "Starting OpenCTI containers..."
docker-compose up
