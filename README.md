# Manage Docker Container using Salt Stack

Formulas to manage a collection of docker images and containers. Includes build and runtime update and dependency management and robustness features as lost link rebuild, images testing and undo update.  

## Feature Details

* builds docker images (from git)
* docker build dependency management
* docker container runtime configuration
* manages updates
* manages deconstruction of old containers
* container dependency management: restart dependant containers
* container link management: rebuild lost links
* container originating IP address management (via )
* docker container lifecycle management

## Bootstrapping a Salt Minion Container

The configuration shown below (Salt fileserver and pillar data from git) works as well with the master as with a stand alone client. 

### Variant 1: Existing Salt Master

Add the minion keys to the Salt Minion Container

### Variant 2: Stand alone from remote git
 
You'll nedd to add the git private key to the container.
  
### Variant 3: Stand alone with local git

In this case just add the git repo to the minion config, no keys are needed.

## Access docker data

We've found it useful to store everything in git, so our `master.yaml` contains something like this:   

    fileserver_backend:
      - git
    
    gitfs_remotes:
      - file:///repos/salt-states.git
      - file:///repos/docker.git:
        - mountpoint: salt://docker
    
    file_ignore_regex:
      - '/\.git($|/)'
    
    
    ext_pillar:
      - git: master file:///repos/salt-pillar.git
    
    pillar_roots:
      base:
        - /

## running from within a container

It's about managing docker from within a docker container and it works like this:
 
0. build the docker image 
1. on a new host, preferrably CoreOS, 


# BUGS AND TODO

## docker.built does not notify `onchanges`

https://github.com/saltstack/salt/issues/13750

    ----------
              ID: something-image
        Function: docker.built
            Name: hinnerk/something:testing
          Result: True
         Comment: Successfully built XXX
         Started: 23:15:16.801226
        Duration: 31560.154 ms
         Changes:
    ----------
              ID: something-tag-previous
        Function: cmd.run
            Name: docker tag -f hinnerk/something:latest hinnerk/something:previous
          Result: True
         Comment: State was not run because onchanges req did not change
         Started:
        Duration:
         Changes:
    ----------
              ID: something-tag-current
        Function: cmd.run
            Name: docker tag -f hinnerk/something:testing hinnerk/something:latest
          Result: True
         Comment: State was not run because onchanges req did not change
         Started:
        Duration:
         Changes:

## Feature: Push to docker registry

Push successfully tested images to a registry.

## Feature: 2x run docker

## Feature: Check for lost link connection

When a linked container is reolaced, the link goes missing. We're detecting thoise missing links by comparing the links declared in the pillar with the output of `docker inspect <container>`. Containers with links missing are removed.
 
Currently this happens after the initial call of `docker.running` of all containers. So we need to trigger an additional call to `docker.running` here.
