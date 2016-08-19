#!/bin/sh

echo "<h1>Hello webhook world from: $HOSTNAME</h1>" > /usr/share/nginx/html/index.html

# Use `exec` so that PID 1 is the nginx process and not this script
exec /usr/sbin/nginx -g "daemon off;"
