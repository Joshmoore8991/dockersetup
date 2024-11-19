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

# Ensure Redis service is defined
echo "Ensuring Redis service is defined in docker-compose.yml..."
if ! grep -q "redis:" docker-compose.yml; then
  sed -i '/services:/a\
  redis:\n\
    image: redis:6.2\n\
    container_name: opencti_redis\n\
    restart: unless-stopped\n\
    healthcheck:\n\
      test: [\"CMD\", \"redis-cli\", \"ping\"]\n\
      interval: 10s\n\
      timeout: 5s\n\
      retries: 5\n' docker-compose.yml
fi

# Ensure OpenCTI depends on Redis
echo "Ensuring OpenCTI depends on Redis in docker-compose.yml..."
if ! grep -q "depends_on:" docker-compose.yml; then
  sed -i '/opencti:/a\
    depends_on:\n\
      - redis' docker-compose.yml
fi

# Ensure docker-compose.yml uses the default network for localhost
echo "Ensuring docker-compose.yml uses the default network for localhost..."
sed -i '/services:/a\
  opencti:\n\
    networks:\n\
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

  for ((i=1; i<=retries; i
