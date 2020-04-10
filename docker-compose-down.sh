export DOMAIN="home.lab"

stacks=(base folding)

for stack in ${stacks[*]} 
do
    cd $stack
    docker-compose down
    cd ..
done

docker network rm proxy
