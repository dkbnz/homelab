export DOMAIN="home.lab"

stacks=(base folding)

for stack in ${stacks[*]} 
do
    cd ./stacks/$stack
    docker-compose down
    cd ../..
done

docker network rm proxy
