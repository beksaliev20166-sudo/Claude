#!/usr/bin/env bash
# Собирает анимированный ролик из кадров frames/01..16.jpg
# Каждая сцена: плавное движение камеры (зум/панорама) + переходы между сценами.
set -euo pipefail
cd "$(dirname "$0")"

FPS=30
DUR=4.0          # длительность сцены, сек
XF=0.6           # длительность перехода, сек
W=1920; H=1080
N=$(( $(printf '%.0f' "$(echo "$DUR*$FPS" | bc)") ))
mkdir -p build

# Движения камеры по сценам: zoom-выражение | x | y
motion() {
  local d="(on/$N)"
  case $1 in
    in)     echo "1+0.15*$d|iw/2-(iw/zoom/2)|ih/2-(ih/zoom/2)";;
    out)    echo "1.15-0.15*$d|iw/2-(iw/zoom/2)|ih/2-(ih/zoom/2)";;
    left)   echo "1.12|(iw-iw/zoom)*(1-$d)|ih/2-(ih/zoom/2)";;
    right)  echo "1.12|(iw-iw/zoom)*$d|ih/2-(ih/zoom/2)";;
    up)     echo "1.12|iw/2-(iw/zoom/2)|(ih-ih/zoom)*(1-$d)";;
    shake)  echo "1.08+0.04*$d|iw/2-(iw/zoom/2)+12*sin(on*1.7)|ih/2-(ih/zoom/2)+8*cos(on*2.3)";;
    tl)     echo "1+0.18*$d|(iw/2-(iw/zoom/2))*0.6|(ih/2-(ih/zoom/2))*0.7";;
  esac
}

# 16 сцен: подобранное движение под содержание каждой картинки
MOVES=(right shake in up in right in shake in left out shake in in right left)
TRANS=(fade slideleft circleopen fade smoothleft fadeblack circleclose wipeleft fade dissolve smoothright fade radial fadeblack slideleft)

for i in $(seq 1 16); do
  f=$(printf 'frames/%02d.jpg' "$i")
  IFS='|' read -r Z X Y <<<"$(motion "${MOVES[$((i-1))]}")"
  ffmpeg -y -v error -loop 1 -i "$f" -vf \
    "scale=3840:-2:flags=lanczos,zoompan=z='$Z':x='$X':y='$Y':d=$N:s=${W}x${H}:fps=$FPS,format=yuv420p" \
    -frames:v $N -c:v libx264 -preset medium -crf 18 "build/s$(printf %02d "$i").mp4"
  echo "scene $i done"
done

# Склейка с переходами
inputs=(); for i in $(seq 1 16); do inputs+=(-i "build/s$(printf %02d "$i").mp4"); done
fc=""; prev="0:v"; offset=0
for i in $(seq 1 15); do
  offset=$(echo "$offset+$DUR-$XF" | bc)
  out="v$i"
  fc+="[$prev][$i:v]xfade=transition=${TRANS[$((i-1))]}:duration=$XF:offset=$offset[$out];"
  prev=$out
done
fc+="[$prev]fade=t=in:st=0:d=0.5,fade=t=out:st=$(echo "$offset+$DUR-0.8" | bc):d=0.8,format=yuv420p[final]"

ffmpeg -y -v error "${inputs[@]}" -filter_complex "$fc" -map "[final]" \
  -c:v libx264 -preset slow -crf 20 -movflags +faststart animation.mp4
echo "Готово: animation.mp4"
