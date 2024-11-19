#!/bin/bash

# Exit script on error
set -e

# Define the installation directory
INSTALL_DIR="$HOME/opencti"

# Install dependencies
echo "Installing dependencies..."
sudo apt update
sudo apt install -y git jq docker.io docker-compose

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
