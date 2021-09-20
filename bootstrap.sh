#!/bin/bash
echo "👋" "This script is going to request some inputs to do the basic information gathering and setup necessary to get started."

# Create the directories to store IDs and credentials for accessibility
if ! [ -d '.ids' ]
then
    mkdir .ids
fi
if ! [ -d '.creds' ]
then
    mkdir .creds
fi

# Check if CCloud exists, if not, download it and add to PATH.
if ! command -v ccloud > /dev/null
then
    echo "🙄" 'CCloud CLI not found, downloading.'
    curl -sL --http1.1 https://cnfl.io/ccloud-cli | sh -s -- latest -b ~/ccloudcli/
    if [ -e ~/ccloudcli/ccloud ]
    then
        echo "🤩" 'Done. Exporting to PATH.'
        export PATH=~/ccloudcli/:$PATH;
        echo "🤩" 'Done.'
    fi
else
    echo "🤩" 'CCloud CLI found.'
fi

# Login to CCloud to create some stuff.
echo "💻" "In order to create some topics, keys, and other fun stuff, please login to CCloud."
ccloud login

# Skip the following if already accomplished
if [ -e '.ids/ENVIRONMENT_ID' ]
then
    echo "🤩" "ENVIRONMENT_ID already set. Skipping."
    ENVIRONMENT_ID=$(cat .ids/ENVIRONMENT_ID)
else
    # Choose and set an environment to use as the active environment.
    if [ -z $(ccloud environment list | grep "default") ]
    then 
        echo "💻" "Specify an environment by ID to use."
        ccloud environment list
        read -p "Environment ID: " ENVIRONMENT_ID
        ccloud environment use $ENVIRONMENT_ID
        echo "👆" "Using '$ENVIRONMENT_ID' going forward."
        echo $ENVIRONMENT_ID > .ids/ENVIRONMENT_ID
        echo "🤩" "Done."
    else
        echo "💻" "Specify an environment by ID to use, or press enter to use 'default'."
        ccloud environment list
        read -p "Environment ID (default): " ENVIRONMENT_ID
        if [ -z $(echo $ENVIRONMENT_ID) ]
        then
            ENVIRONMENT_ID=$(ccloud environment list | grep "default" | awk '{print $2}')
        fi
        ccloud environment use $ENVIRONMENT_ID
        echo "👆" "Using '$ENVIRONMENT_ID' going forward."
        echo $ENVIRONMENT_ID > .ids/ENVIRONMENT_ID
        echo "🤩" "Done."
    fi
fi

if [ -e '.ids/CLUSTER_ID' ]
then
    echo "🤩" "CLUSTER_ID already set. Skipping."
    CLUSTER_ID=$(cat .ids/CLUSTER_ID)
    BOOTSTRAP_SERVERS=$(ccloud kafka cluster describe $CLUSTER_ID | grep "SASL_SSL" | awk '{print $4}' | sed 's/SASL_SSL:\/\///g')
    echo $BOOTSTRAP_SERVERS > .ids/BOOTSTRAP_SERVERS
else
    # Create a cluster to use.
    echo "💻" "Time to create a cluster that you can use."
    read -p "Cool to create the cluster? (yes/no): " CLUSTER_CAN_CREATE
    if [ $CLUSTER_CAN_CREATE = 'yes' ]
    then
        echo "👍" "Creating a new cluster.  This will default to be a 'basic' cluster on GCP."
        ccloud kafka cluster create 'app-mod' --cloud 'gcp' --region 'us-west4'
        echo "👆" "Here's your newly created cluster. Saving the properties."
        CLUSTER_ID=$(ccloud kafka cluster list | grep "app-mod" | awk '{print $1}')
        BOOTSTRAP_SERVERS=$(ccloud kafka cluster describe $CLUSTER_ID | grep "SASL_SSL" | awk '{print $4}' | sed 's/SASL_SSL:\/\///g')
        echo $BOOTSTRAP_SERVERS > .ids/BOOTSTRAP_SERVERS
        echo "💻" "Setting your new cluster as the current active cluster."
        ccloud kafka cluster use $CLUSTER_ID
        echo "👆" "Using '$CLUSTER_ID' going forward."
        echo $CLUSTER_ID > .ids/CLUSTER_ID
        echo "🤩" "Done."
    else if [ $CLUSTER_CAN_CREATE = 'no' ]
        then 
            echo "💀" "You need one to proceed. Sorry."
            echo "Bye"
            exit
        else
            echo "💀" "Needed a 'yes' or 'no' answer"
            exit
        fi
    fi
fi

if [ -e '.ids/SCHEMA_REGISTRY_CLUSTER_ID' ]
then
    echo "🤩" "SCHEMA_REGISTRY_CLUSTER_ID already set. Skipping."
    SCHEMA_REGISTRY_CLUSTER_ID=$(cat .ids/SCHEMA_REGISTRY_CLUSTER_ID)
    SCHEMA_REGISTRY_URL=$(cat .ids/SCHEMA_REGISTRY_URL)
else
    # Enable Schema Registry in the environment if it isn't already.
    echo "💻" "Next up is Schema Registry."
    echo "💻" "Checking to see if Schema Registry is already enabled for this environment."
    ccloud schema-registry cluster describe &> /dev/null
    if [ $? -eq 0 ]
    then
        echo "💻" "Schema Registry already enabled for this environment. Saving the properties."
        SCHEMA_REGISTRY_CLUSTER_ID=$(ccloud schema-registry cluster describe | grep "Cluster ID" | awk '{print $5}')
        SCHEMA_REGISTRY_URL=$(ccloud schema-registry cluster describe | grep "Endpoint" | awk '{print $5}')
        echo $SCHEMA_REGISTRY_URL > .ids/SCHEMA_REGISTRY_URL
        echo $SCHEMA_REGISTRY_CLUSTER_ID > .ids/SCHEMA_REGISTRY_CLUSTER_ID
    else
        echo "💻" "Schema Registry not yet enabled. Enabling it in the US on GCP."
        ccloud schema-registry cluster enable --cloud 'gcp' --geo 'us'
        echo "👆" "This will be the Schema Registry you'll use going forward."
        SCHEMA_REGISTRY_CLUSTER_ID=$(ccloud schema-registry cluster describe | grep "Cluster ID" | awk '{print $5}')
        SCHEMA_REGISTRY_URL=$(ccloud schema-registry cluster describe | grep "Endpoint" | awk '{print $5}')
        echo $SCHEMA_REGISTRY_URL > .ids/SCHEMA_REGISTRY_URL
        echo $SCHEMA_REGISTRY_CLUSTER_ID > .ids/SCHEMA_REGISTRY_CLUSTER_ID
        echo "🤩" "Done."
    fi
fi

if [ -e '.creds/CLOUD_KEY' ]
then
    echo "🤩" "CLOUD_KEY, CLOUD_SECRET already created. Skipping."
    CLOUD_KEY=$(cat .creds/CLOUD_KEY)
    CLOUD_SECRET=$(cat .creds/CLOUD_SECRET)
    SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username='$CLOUD_KEY' password='$CLOUD_SECRET';"
    echo "$SASL_JAAS_CONFIG" > .creds/SASL_JAAS_CONFIG
else
    # Create credentials for all the stuff. 
    echo "💻" "Time to create credentials."
    echo "💻" "Creating credentials for Kafka Clients."
    CLUSTER_CREDS=$(ccloud api-key create --resource $CLUSTER_ID --description "API Keys for Clients.")
    CLOUD_KEY=$(echo $CLUSTER_CREDS | awk '{print $6}')
    CLOUD_SECRET=$(echo $CLUSTER_CREDS | awk '{print $11}')
    echo "API Key: " $CLOUD_KEY
    echo "API Secret: " $CLOUD_SECRET
    echo "👆" "Saving these for use later."
    echo "$CLOUD_KEY" > .creds/CLOUD_KEY
    echo "$CLOUD_SECRET" > .creds/CLOUD_SECRET
    SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username='$CLOUD_KEY' password='$CLOUD_SECRET';"
    echo "$SASL_JAAS_CONFIG" > .creds/SASL_JAAS_CONFIG
    echo "🤩" "Done."
fi

if [ -e '.ids/KSQLDB_APP_ID' ]
then
    echo "🤩" "KSQLDB_APP_ID already present and likely created. Skipping."
    KSQLDB_APP_ID=$(cat .ids/KSQLDB_APP_ID)
    KSQLDB_API_ENDPOINT=$(cat .ids/KSQLDB_API_ENDPOINT)
else
    # Create a ksqlDB app to use with the cluster.
    echo "💻" "Time to create a ksqlDB app."
    read -p "Cool to create the ksqlDB app? (yes/no): " KSQLDB_CAN_CREATE
    if [ $KSQLDB_CAN_CREATE = 'yes' ]
    then
        echo "👍" "Creating a new ksqlDB app.  This will default to the smallest size of 4 CSUs."
        ccloud ksql app create ksqldb-appmod --csu 4 --api-key $CLOUD_KEY --api-secret $CLOUD_SECRET
        echo "👆" "Here's your newly created ksqlDB app. Saving the properties."
        KSQLDB_APP_ID=$(ccloud ksql app list | grep "ksqldb-appmod" | awk '{print $1}')
        KSQLDB_API_ENDPOINT=$(ccloud ksql app list | grep "ksqldb-appmod" | awk '{print $11}')
        echo "$KSQLDB_APP_ID" > .ids/KSQLDB_APP_ID
        echo "$KSQLDB_API_ENDPOINT" > .ids/KSQLDB_API_ENDPOINT
        echo "🤩" "Done."
    else if [ $KSQLDB_CAN_CREATE = 'no' ]
        then 
            echo "💀" "You need one to proceed. Sorry."
            echo "Bye"
            exit
        else
            echo "💀" "Needed a 'yes' or 'no' answer"
            exit
        fi
    fi
fi

if [ -e '.ids/TOPICS' ]
then
    echo "🤩" "TOPICS already created. Skipping."
else
    # Create topics that will be used by the connectors and applications.
    echo "💻" "Time to create topics."
    echo "💻" "Creating a few topics needed for the connectors and apps."
    ccloud kafka topic create 'postgres.bank.customers'
    ccloud kafka topic create 'postgres.bank.accounts'
    ccloud kafka topic create 'postgres.bank.transactions'
    echo "DONE" > .ids/TOPICS
    echo "🤩" "Done."
fi

if [ -e '.creds/KSQLDB_API_KEY' ]
then
    echo "🤩" "KSQLDB_API_KEY already created. Skipping."
    KSQLDB_API_KEY=$(cat .creds/KSQLDB_API_KEY)
    KSQLDB_API_SECRET=$(cat .creds/KSQLDB_API_SECRET)
else
    echo "💻" "Creating credentials for ksqlDB."
    KSQLDB_CREDS=$(ccloud api-key create --resource $CLUSTER_ID --description "API Keys for ksqlDB.")
    KSQLDB_API_KEY=$(echo $KSQLDB_CREDS | awk '{print $6}')
    KSQLDB_API_SECRET=$(echo $KSQLDB_CREDS | awk '{print $11}')
    echo "ksqlDB API Key: " $KSQLDB_API_KEY
    echo "ksqlDB API Secret: " $KSQLDB_API_SECRET

    echo "$KSQLDB_API_KEY" > .creds/KSQLDB_API_KEY
    echo "$KSQLDB_API_SECRET" > .creds/KSQLDB_API_SECRET
    echo "🤩" "Done."
fi

if [ -e '.creds/SCHEMA_REGISTRY_KEY' ]
then
    echo "🤩" "SCHEMA_REGISTRY_KEY already created. Skipping."
    SCHEMA_REGISTRY_KEY=$(cat .creds/SCHEMA_REGISTRY_KEY)
    SCHEMA_REGISTRY_SECRET=$(cat .creds/SCHEMA_REGISTRY_SECRET)
    SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO='$SCHEMA_REGISTRY_KEY:$SCHEMA_REGISTRY_SECRET'
    echo "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" > .creds/SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO
else
    echo "💻" "Creating credentials for Schema Registry."
    SR_CREDS=$(ccloud api-key create --resource $SCHEMA_REGISTRY_CLUSTER_ID --description "API Keys for SR.")
    SCHEMA_REGISTRY_KEY=$(echo $SR_CREDS | awk '{print $6}')
    SCHEMA_REGISTRY_SECRET=$(echo $SR_CREDS | awk '{print $11}')
    echo "Schema Registry API Key: " $SCHEMA_REGISTRY_KEY
    echo "Schema Registry API Secret: " $SCHEMA_REGISTRY_SECRET
    echo "👆" "Saving these for use later."
    echo "$SCHEMA_REGISTRY_KEY" > .creds/SCHEMA_REGISTRY_KEY
    echo "$SCHEMA_REGISTRY_SECRET" > .creds/SCHEMA_REGISTRY_SECRET
    echo "🤩" "Done."
fi

