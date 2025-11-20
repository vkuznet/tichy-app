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
LDIR=$DIR/logs
mkdir -p $LDIR

# check existing process
if [ -f $LDIR/srv.pid ]; then
    PID=$(cat $LDIR/srv.pid)
    if ps -p $PID > /dev/null; then
        echo "Tichy server is running (PID $PID)"
        exit 1
    else
        echo "Tichy server is not running"
    fi
fi

# we should start tichy server from AIDIR where .env file resides
cd $DIR
$DIR/tichy/tichy serve > $LDIR/srv.log 2>&1 &
cd -

# Save the PID of the last backgrounded process
echo $! > $LDIR/srv.pid
echo "Tichy server started with PID=`cat $LDIR/srv.pid`"
