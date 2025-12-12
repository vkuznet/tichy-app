#/bin/bash

# ------------------------------------------------------------
# Validate AI directory
# ------------------------------------------------------------
if [ -z "${AIDIR:-}" ]; then
    echo "[ERROR] AIDIR environment variable is not set."
    echo "        Please export AIDIR=/path/to/ai before running services"
    exit 1
fi
DIR=$AIDIR
USER=`cat $DIR/pdb_credentials | grep USERNAME | sed -e "s,USERNAME:,,g"`
PASSWORD=`cat $DIR/pdb_credentials | grep PASSWORD | sed -e "s,PASSWORD:,,g"`
LDIR=$DIR/logs
mkdir -p $LDIR
APID=$LDIR/pdb.pid
ALOG=$LDIR/pdb.log

# check existing process
if [ -f $APID ]; then
    PID=$(cat $APID)
    if ps -p $PID > /dev/null; then
        echo "Postgres is running (PID $PID)"
        exit 1
    else
        echo "Postgres is not running"
    fi
fi

# remove previous databases
echo "remove and recreate $DIR/postgres-data"
#rm -rf $DIR/postgres-data
mkdir -p $DIR/postgres-data
echo "remove and recreate $DIR/postgres-run"
#rm -rf $DIR/postgres-run
mkdir -p $DIR/postgres-run

# Start PostgresDB container
echo "start PostgresDB apptainer..."
apptainer exec \
  --bind $DIR/postgres-data:/var/lib/postgresql/data \
  --bind $DIR/postgres-run:/var/run/postgresql \
  --env POSTGRES_USER=$USER \
  --env POSTGRES_PASSWORD=$PASSWORD \
  $DIR/images/pgvector_pg17.sif \
  docker-entrypoint.sh postgres \
  > $APID 2>&1 &

# start tichy database
echo "wait for PDB to start..."
sleep 5
tail $ALOG
echo "$DIR/tichy/tichy db up"
# we should start db from AIDIR where .env file resides
cd $DIR
$DIR/tichy/tichy db up
cd -

# Save the PID of the last backgrounded process
echo $! > $APID
echo "PostgresDB started with PID=`cat $APID`"
