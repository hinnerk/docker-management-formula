# Salt Minion and Docker Client in a Docker Container 

## Requirements

* `/var/run/docker.sock` must be mounted to access the external docker daemon
* per default assumes the salt master to be available as `salt`.    

## Example RUN

    docker run --name=salt-minion --volume=/some/log/path:/logs --volume=/var/run/docker.sock:/var/run/docker.sock --link=salt:salt hinnerk/salt-minion:latest


## Example TEST

    $ docker run --name=salt-minion --volume=/some/log/path:/logs --volume=/var/run/docker.sock:/var/run/docker.sock --link=salt:salt --rm hinnerk/salt-minion:latest salt-call --debug 
