nohup mpv --input-ipc-server="ipc_server" --no-audio --panscan=1 --pause --hwdec="auto" --no-osc --no-osd-bar --no-input-default-bindings --no-input-cursor --cursor-autohide=no --no-window-dragging --no-border --no-taskbar-progress --keep-open=yes --loop-file=inf --idle=yes --input-vo-keyboard=no --x11-bypass-compositor=no --focus-on="never" --ontop=no --stop-screensaver=no --no-config --no-keepaspect-window --force-window=immediate "$1" > nohup.log 2>&1 &
pid=$!
echo "$pid" > mpv.pid
