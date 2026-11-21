#!/bin/bash
# run lockstep.js on the browser emulator's core in headless Chrome: jsref.sh scenario.txt
here=$(cd "$(dirname "$0")" && pwd); emu=${MICROTRONIC_EMU:-$here/../../microtronic-emulator}   # a clone of lambdamikel/microtronic-emulator
t=$(mktemp --suffix=.html -p "$here")
{ echo '<!doctype html><meta charset=utf-8><pre id=out></pre>'
  echo '<script>const __o=[];console.log=(...a)=>__o.push(a.join(" "));window.onerror=(m,s,l)=>{__o.push("ERROR "+m+" @"+l);document.getElementById("out").textContent=__o.join("\n")}</script>'
  echo "<script src=\"$emu/js/rom.js\"></script><script src=\"$emu/js/tms1600.js\"></script>"
  printf '<script>const SCENARIO=%s;</script>\n' "$(python3 -c 'import json,sys;print(json.dumps(open(sys.argv[1]).read()))' "$1")"
  echo "<script src=\"$here/lockstep.js\"></script>"
  echo '<script>document.getElementById("out").textContent=__o.join("\n")</script>'; } > "$t"
google-chrome --headless --disable-gpu --no-sandbox --allow-file-access-from-files --virtual-time-budget=600000 --dump-dom "file://$t" 2>/dev/null | sed -n "/<pre id=\"out\">/,/<\/pre>/p" | sed "s/.*<pre id=\"out\">//; s/<\/pre>.*//"
rm -f "$t"
