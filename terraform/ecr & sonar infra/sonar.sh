#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "===== Updating system ====="
apt-get update -y
apt-get upgrade -y

echo "===== Installing Docker ====="
apt-get install -y docker.io curl

systemctl enable docker
systemctl start docker

# Wait until Docker is ready
until docker info >/dev/null 2>&1; do
    sleep 2
done

echo "===== Creating SonarQube directories ====="
mkdir -p /opt/sonarqube/{data,extensions,logs}

echo "===== Running SonarQube ====="
docker run -d \
  --name sonarqube \
  --restart unless-stopped \
  -p 9000:9000 \
  -v /opt/sonarqube/data:/opt/sonarqube/data \
  -v /opt/sonarqube/extensions:/opt/sonarqube/extensions \
  -v /opt/sonarqube/logs:/opt/sonarqube/logs \
  sonarqube:lts-community

echo "===== SonarQube installation completed ====="