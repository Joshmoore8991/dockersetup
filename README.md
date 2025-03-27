Portainer Deployment Script

Overview

This script automates the deployment of Portainer, a lightweight management UI for Docker environments. It creates a Docker volume for persistent storage and runs a Portainer container with the necessary configurations.

Prerequisites

Ensure you have the following installed on your system before running the script:

Docker

Bash shell

Usage

Make the script executable (if necessary):

chmod +x script.sh

Run the script:

./script.sh

What This Script Does

Creates a Docker volume named portainer_data to persist Portainer's data.

Runs a Portainer container named portainer in detached mode.

Maps the necessary ports:

8000:8000 (Agent communication)

9443:9443 (Web UI over HTTPS)

Mounts the Docker socket to allow Portainer to manage Docker.

Ensures the container restarts automatically using the --restart=always policy.

Uses the Portainer Community Edition image (portainer/portainer-ce:2.21.4).

Accessing Portainer

Once the script runs successfully, you can access Portainer at:

URL: https://localhost:9443

Follow the setup instructions on the web UI to configure Portainer.

Stopping and Removing Portainer

If you need to stop and remove Portainer, use the following commands:

# Stop the container
docker stop portainer

# Remove the container
docker rm portainer

# Remove the volume (Warning: This deletes all stored data!)
docker volume rm portainer_data

License

This script is open-source and provided under the MIT License.
