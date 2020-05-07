docker network create proxy

export DOMAIN="home.lab"

for compose_file in ./stacks/*/docker-compose.yml; do
    docker-compose -f $compose_file up -d &
done
