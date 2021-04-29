#!/usr/bin/env bash

#
# Usage:
#   ./pg-copydb.sh sample.cfg
#

# check if a config file has been provided
if [ $# -eq 0 ]; then
    echo "No arguments supplied."
    exit
fi

if [ -f $1 ]; then
    source $1
else
    printf "%s\n" "Config file not found."
    exit
fi

if ! command -v dbd &> /dev/null
then
    echo "dbd could not be found, please install it first (https://github.com/serbanrobu/dbd)"
    exit
fi

VALID_TARGETS=('local' 'docker' 'backup' 'remote')

if ! grep -q $DESTINATION_TARGET <<< "${VALID_TARGETS[@]}"
then
    echo 'You have selected an invalid destination target'
fi

# we need pv to be found within PATH, otherwise we'll do a lot of steps only to error out
# pv is required only for local and docker
if [ $DESTINATION_TARGET == "local" ] | [ $DESTINATION_TARGET == "docker" ]
then
    if ! command -v pv &> /dev/null
    then
        echo "pv could not be found, please install it first (on MacOS: brew install pv)"
        exit
    fi
fi

# define a couple of variables
TIMESTAMP=$(date +"%Y%m%dT%H%M%S")
DROP_DATABASE_AND_RECREATE=false

if [ -z "$DATABASE_NAME" ]
then
      DESTINATION_DB_NAME=${DBD_DATABASE_ID}"_"${TIMESTAMP}
else
      DESTINATION_DB_NAME=$DATABASE_NAME
      DROP_DATABASE_AND_RECREATE=true
fi

grn=$'\e[1;32m'
end=$'\e[0m'

# excluded tables might be missing, in which case dbd will complain
if [ -z "$EXCLUDED_TABLES" ]
then
      EXCLUDE_TABLES_PART=""
else
      EXCLUDE_TABLES_PART="--exclude-table-data ${EXCLUDED_TABLES}"
fi

if [ $DESTINATION_TARGET == "local" ]; then

    if [ "$DROP_DATABASE_AND_RECREATE" = true ]
    then
        printf "\n%s\n" "${grn}Dropping the existing database${end}"
        sudo -u postgres dropdb -U postgres ${DESTINATION_DB_NAME}
    fi

    printf "\n%s\n" "${grn}Creating new database${end}"
    sudo -u postgres createdb -U postgres ${DESTINATION_DB_NAME}

    printf "\n%s\n" "${grn}Downloading the database${end}"
    dbd ${DBD_CONNECTION_ID} --dbname ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} ${EXCLUDE_TABLES_PART} > /tmp/"${DESTINATION_DB_NAME}.sql.gz" 
    
    printf "\n%s\n" "${grn}Importing the database${end}"
    pv /tmp/"${DESTINATION_DB_NAME}.sql.gz" | gunzip | sudo -u postgres psql -U postgres -d ${DESTINATION_DB_NAME}

    printf "\n%s\n" "${grn}Cleaning up${end}"
    rm /tmp/"${DESTINATION_DB_NAME}.sql.gz"

    printf "\n${grn}The copied database name is \"${end}$DESTINATION_DB_NAME${grn}\".${end}\n\n"

elif [ $DESTINATION_TARGET == "docker" ]; then

    printf "\n%s\n" "${grn}Spinning up a new docker container${end}"

    if [ "$DOCKER_NEW_INSTANCE" = true ]
    then
        INSTANCE_NAME="copydb_"${TIMESTAMP}
        docker run -td --name ${INSTANCE_NAME} -p 5432 -e POSTGRES_PASSWORD=${DESTINATION_DB_PASS} -d ${DOCKER_TAG}
    else
        INSTANCE_NAME="$DOCKER_EXISTING_INSTANCE_NAME"
    fi

    while ! docker exec ${INSTANCE_NAME} pg_isready; do
        echo "Waiting for a database connection..."
        sleep 1
    done

    printf "\n${grn}Docker is now running${end}\n"

    if [ "$DROP_DATABASE_AND_RECREATE" = true ]
    then
        printf "\n%s\n" "${grn}Dropping the existing database${end}"
        docker exec -it ${INSTANCE_NAME} dropdb -U postgres ${DESTINATION_DB_NAME}
    fi

    printf "\n%s\n" "${grn}Creating a new database${end}"
    docker exec -it ${INSTANCE_NAME} createdb -U postgres ${DESTINATION_DB_NAME}

    printf "\n%s\n" "${grn}Downloading the database within /tmp/ ${end}"
    dbd ${DBD_CONNECTION_ID} --dbname ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} ${EXCLUDE_TABLES_PART} > /tmp/"${DESTINATION_DB_NAME}.sql.gz"

    printf "\n%s\n" "${grn}Importing the database${end}"

    pv /tmp/"${DESTINATION_DB_NAME}.sql.gz" | gunzip | docker exec -i ${INSTANCE_NAME} psql -U postgres -d ${DESTINATION_DB_NAME}

    printf "\n%s\n" "${grn}Cleaning up${end}"
    rm /tmp/"${DESTINATION_DB_NAME}.sql.gz"

    printf "\n${grn}Docker instance name is \"${end}$INSTANCE_NAME${grn}\".${end}\n"
    
    printf "\n${grn}Ports you can use: ${end}\n"
    docker port ${INSTANCE_NAME}

    printf "\n${grn}Database credentials: postgres / \"${end}$DESTINATION_DB_PASS${grn}\".${end}\n"

    printf "\n${grn}The copied database name is \"${end}$DESTINATION_DB_NAME${grn}\".${end}\n\n"

elif [ $DESTINATION_TARGET == "backup" ]; then

    FILE_PATH="${BACKUP_PATH}/${DESTINATION_DB_NAME}.sql.gz"

    dbd ${DBD_CONNECTION_ID} --dbname ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} ${EXCLUDE_TABLES_PART} > ${FILE_PATH}

elif [ $DESTINATION_TARGET == "remote" ]; then

    status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 ${REMOTE_USER}@${REMOTE_IP} echo ok 2>&1)

    if [[ $status == ok ]] ; then
        
        printf "\n%s\n" "${grn}Downloading the database locally${end}"
        dbd ${DBD_CONNECTION_ID} --dbname ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} ${EXCLUDE_TABLES_PART} > /tmp/"${DESTINATION_DB_NAME}.sql.gz"

        printf "\n%s\n" "${grn}Transferring to remote host${end}"
        scp /tmp/"${DESTINATION_DB_NAME}.sql.gz" ${REMOTE_USER}@${REMOTE_IP}:/tmp/"${DESTINATION_DB_NAME}.sql.gz"

        DROP_DATABASE_SEQUENCE=""
        if [ "$DROP_DATABASE_AND_RECREATE" = true ]
        then
            DROP_DATABASE_SEQUENCE="dropdb -U postgres ${DESTINATION_DB_NAME}"
        fi

        printf "\n%s\n" "${grn}Running commands on remote host${end}"
        ssh ${REMOTE_USER}@${REMOTE_IP} << EOF
 
 echo "Login as postgres"
 sudo su postgres

 echo "Dropping database if required" 
 ${DROP_DATABASE_SEQUENCE}
 
 echo "Creating database"       
 createdb -U postgres ${DESTINATION_DB_NAME}

 echo "Importing database"
 pv /tmp/"${DESTINATION_DB_NAME}.sql.gz" | gunzip | psql -U postgres -d ${DESTINATION_DB_NAME}

 echo "Logout from postgres"
 exit

 echo "Clean up"
 rm /tmp/"${DESTINATION_DB_NAME}.sql.gz"

EOF

        printf "\n%s\n" "${grn}Local clean up${end}"
        rm /tmp/"${DESTINATION_DB_NAME}.sql.gz"

    else
        echo "Error when then trying to remotely login:"
        echo $status
        exit
    fi

fi
