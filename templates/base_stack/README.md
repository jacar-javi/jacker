# Jacker Base Stack

This template is the base docker stack structure to integrate with Jacker core services.

It contains the next structure:

```
├── assets
│   ├── <stack assets, scripts>
├── compose
│   ├── <stack service files yaml>
├── data
│   ├── <stack data folders>
├── secrets
│   ├── <stack secret files>
├── clean.sh
├── dc.sh
├── docker-compose.yml
├── README.md
├── start.sh
├── stop.sh
├── .env
└── .gitignore
```

## .env

Stack's Environment File. It contains all environment variables used.

# dc.sh

Script to launch docker compose using Jacker's Environment + Stack's Environment. Use instead docker compose.

## docker-compose.yml

This is the base stack file. It contains everything necesary to start all docker containers that are part of the stack.

## start.sh

Stack start script. It will setup all system and bring up containers in the stack.

## stop.sh

Stack stop. It will clean the system and bring down containers in the stack.

## clean.sh

It will remove all data and will let the stack as it was at the first time of use.

