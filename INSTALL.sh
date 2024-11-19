#!/bin/bash

# Exit script on error
set -e

# Define the installation directory
INSTALL_DIR="$HOME/opencti"

# Install dependencies
echo "Installing dependencies..."
sudo apt update
sudo apt install -y git jq docker.io docker-compose

# Clone the OpenCTI Docker repository
echo "Cloning the OpenCTI Docker repository..."
mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"
git clone https://github.com/OpenCTI-Platform/docker.git
cd docker

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

# Ensure docker-compose.yml uses the default network for localhost
echo "Ensuring docker-compose.yml uses the default network for localhost..."
sed -i '/services:/a\
  opencti:\
    networks:\
      - default' docker-compose.yml

# Remove custom network configuration
echo "Removing custom Docker network configuration..."
sed -i '/networks:/,+2d' docker-compose.yml

# Configure ElasticSearch system parameter
echo "Configuring system parameters for ElasticSearch..."
sudo sysctl -w vm.max_map_count=1048575
if ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
  echo "vm.max_map_count=1048575" | sudo tee -a /etc/sysctl.conf
fi

# Start Docker service
echo "Starting Docker service..."
sudo systemctl start docker.service

# Run Docker Compose and wait for services to stabilize
echo "Starting OpenCTI containers..."
docker-compose up -d

# Health check function
check_health() {
  echo "Waiting for services to become healthy..."
  local retries=10
  local healthy=0

  for ((i=1; i<=retries; i++)); do
    unhealthy_count=$(docker ps --filter "health=unhealthy" --filter "name=opencti" --format "{{.ID}}" | wc -l)
    healthy_count=$(docker ps --filter "health=healthy" --filter "name=opencti" --format "{{.ID}}" | wc -l)

    if [[ $healthy_count -ge 1 && $unhealthy_count -eq 0 ]]; then
      echo "All services are healthy!"
      healthy=1
      break
    else
      echo "Attempt $i/$retries: Some services are still unhealthy. Retrying in 15 seconds..."
      sleep 15
    fi
  done

  if [[ $healthy -eq 0 ]]; then
    echo "Services failed to reach healthy state. Check container logs."
    docker-compose logs opencti
    exit 1
  fi
}

# Run health checks
check_health

echo "OpenCTI setup completed successfully with IP localhost:8080!"
