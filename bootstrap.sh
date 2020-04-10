if [ $(id -u) -ne 0 -o $EUID -eq 0 ]; then
  echo "Script must be run using sudo (not as root user)"
  exit 1
fi


apt-get update && apt-get upgrade

# Install docker & docker compose
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add --
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
apt-get update
apt-get install -y docker-ce docker-compose

groupadd docker
usermod -aG docker $USER
newgrp docker

# Run all containers
bash docker-compose-up.sh
