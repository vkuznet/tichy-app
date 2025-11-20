#/bin/bash

# configure your ai directory
DIR=/mnt/data1/vk/AI

# DO NOT MODIFY below this line

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

./tichy serve > $LDIR/srv.log 2>&1 &

# Save the PID of the last backgrounded process
echo $! > $LDIR/srv.pid
echo "Tichy server started with PID=`cat $LDIR/srv.pid`"
