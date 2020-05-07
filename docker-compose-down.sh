export DOMAIN="home.lab"

for compose_file in ./stacks/*/docker-compose.yml; do
    docker-compose -f $compose_file down &
done

docker network rm proxy
