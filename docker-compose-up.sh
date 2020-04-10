docker network create proxy

export DOMAIN="home.lab"

stacks=(base folding)

for stack in ${stacks[*]} 
do
    cd $stack
    docker-compose up -d
    cd ..
done
