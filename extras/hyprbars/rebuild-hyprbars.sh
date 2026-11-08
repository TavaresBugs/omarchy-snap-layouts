#!/bin/bash
# Build the hyprbars title bar plugin for the running Hyprland and load it.
# Run this after a Hyprland update if a red "[hyprbars] ... Version mismatch"
# notification appears and the title bars are gone.
#
# Hyprbars stops Hyprland's mouse binds from seeing a title bar drag, so this
# adds hyprbars:dragstart and hyprbars:dragend events for Snap Layouts. They go
# right after hyprbars' own "Dragging initiated" and "Dragging ended" log lines
# rather than through a patch file, so rewording nearby code doesn't break them.
# If they can't be added or won't compile, it builds plain title bars and warns.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: rebuild-hyprbars.sh [--check | --build-only]

  (no option)    Build, install and load the plugin
  --check        Only show whether the events can be added; builds nothing
  --build-only   Build and install, but don't load the plugin

Environment:
  HYPRBARS_DEST    Install folder (default: ~/.local/lib/hyprland)
  HYPRBARS_COMMIT  hyprland-plugins commit to use instead of looking one up
  HYPRBARS_REPO    Source repo (default: the official hyprland-plugins)
USAGE
}

mode=install
case ${1:-} in
  "") ;;
  --check) mode=check ;;
  --build-only) mode=build ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

dest="${HYPRBARS_DEST:-$HOME/.local/lib/hyprland}"
repo="${HYPRBARS_REPO:-https://github.com/hyprwm/hyprland-plugins.git}"
work=$(mktemp -d -t hyprbars-XXXXXX)
trap 'rm -rf "$work"' EXIT
src="$work/hyprland-plugins"
log="$work/build.log"
file=hyprbars/barDeco.cpp
header=hyprbars/barDeco.hpp

# Each bar remembers whether it reported a dragstart, so every dragstart gets
# exactly one dragend: also when the window closes mid-drag (its bar is
# destroyed without a release), another window takes focus before the release
# (hyprbars then returns early), or the button is released over a layer surface
# such as the Snap Layouts picker (hyprbars ignores input there, so the release
# is handled before that check). Every anchor must be found, or
# add_basic_events is used instead.
add_paired_events() {
  awk '
    /^[[:space:]]*bool[[:space:]]+m_bCancelledDown[[:space:]]*=[[:space:]]*false;/ {
      print
      print "    bool m_bMoveReported = false;"
      found++
      next
    }
    { print }
    END { exit found == 1 ? 0 : 1 }
  ' "$header" >"$work/barDeco.hpp" || return 1
  awk '
    function start(indent) {
      print indent "if (!m_bMoveReported) {"
      print indent "    m_bMoveReported = true;"
      print indent "    g_pEventManager->postEvent(SHyprIPCEvent{\"custom\", \"hyprbars:dragstart\"});"
      print indent "}"
    }
    function end(indent) {
      print indent "if (m_bMoveReported) {"
      print indent "    m_bMoveReported = false;"
      print indent "    if (g_pEventManager)"
      print indent "        g_pEventManager->postEvent(SHyprIPCEvent{\"custom\", \"hyprbars:dragend\"});"
      print indent "}"
    }
    {
      match($0, /^[[:space:]]*/)
      indent = substr($0, 1, RLENGTH)
    }
    !included && /^#include/ {
      print
      print "#include <hyprland/src/managers/EventManager.hpp>"
      included = 1
      next
    }
    /^void CHyprBar::onMouseButton\(.*IPointer::SButtonEvent e\)[[:space:]]*\{[[:space:]]*$/ {
      print
      print "    // A drag can end over a layer surface, such as the Snap Layouts picker."
      print "    if (e.state != WL_POINTER_BUTTON_STATE_PRESSED && (m_bDraggingThis || m_bCancelledDown || m_bDragPending)) {"
      print "        handleUpEvent(info);"
      print "        return;"
      print "    }"
      release = 1
      next
    }
    /^CHyprBar::~CHyprBar\(\)[[:space:]]*\{[[:space:]]*$/ {
      print
      end("    ")
      destructor = 1
      next
    }
    /^void CHyprBar::handleUpEvent\(/ { up = 1 }
    up && /^}/ { up = 0 }
    up && /^[[:space:]]*if \(m_pWindow\.lock\(\) != Desktop::focusState\(\)->window\(\)\)[[:space:]]*$/ {
      condition = $0
      condition_indent = indent
      if ((getline next_line) <= 0 || next_line !~ /^[[:space:]]*return;[[:space:]]*$/) {
        print condition
        print next_line
        next
      }
      print condition " {"
      end(condition_indent "    ")
      print next_line
      print condition_indent "}"
      focus = 1
      next
    }
    { print }
    /"\[hyprbars\] Dragging initiated on.*;[[:space:]]*$/ { start(indent); starts++ }
    /"\[hyprbars\] Dragging ended on.*;[[:space:]]*$/ { end(indent); ends++ }
    END { exit included && release && destructor && focus && starts >= 1 && ends >= 1 ? 0 : 1 }
  ' "$file" >"$work/barDeco.cpp" || return 1
  cp "$work/barDeco.hpp" "$header"
  cp "$work/barDeco.cpp" "$file"
}

# The older way: post right after the log lines. A window closed or a focus
# change mid-drag can leave a dragstart without its dragend.
add_basic_events() {
  awk '
    !included && /^#include/ {
      print
      print "#include <hyprland/src/managers/EventManager.hpp>"
      included = 1
      next
    }
    {
      print
      match($0, /^[[:space:]]*/)
      indent = substr($0, 1, RLENGTH)
      if ($0 ~ /"\[hyprbars\] Dragging initiated on.*;[[:space:]]*$/)
        print indent "g_pEventManager->postEvent(SHyprIPCEvent{\"custom\", \"hyprbars:dragstart\"});"
      else if ($0 ~ /"\[hyprbars\] Dragging ended on.*;[[:space:]]*$/)
        print indent "g_pEventManager->postEvent(SHyprIPCEvent{\"custom\", \"hyprbars:dragend\"});"
    }
  ' "$file" >"$work/barDeco.cpp"
  cp "$work/barDeco.cpp" "$file"
  grep -q 'hyprbars:dragstart' "$file" && grep -q 'hyprbars:dragend' "$file"
}

reset_source() {
  git checkout -q -- "$file" "$header"
}

# Sets events to paired, basic or no.
add_events() {
  if add_paired_events; then
    events=paired
  elif reset_source && add_basic_events; then
    events=basic
  else
    reset_source
    events=no
  fi
}

no_drag_warning() {
  echo "WARNING: $1; building plain title bars." >&2
  echo "Title bars will work, but dragging one won't open the Snap Layouts picker." >&2
}

git clone -q "$repo" "$src"
cd "$src"

hypr_commit=$(hyprctl -j version | jq -r '.commit')
hypr_tag=$(hyprctl -j version | jq -r '.tag')
commit="${HYPRBARS_COMMIT:-}"
# hyprpm.toml lists which hyprland-plugins commit suits each Hyprland release.
if [[ -z $commit && -f hyprpm.toml ]]; then
  commit=$(grep -F "\"$hypr_commit\"" hyprpm.toml | head -1 | grep -oE '[0-9a-f]{40}' | sed -n 2p || true)
fi
if [[ -n $commit ]]; then
  git checkout -q "$commit"
else
  echo "No hyprland-plugins commit listed for Hyprland $hypr_tag; using the latest." >&2
fi
echo "Using hyprland-plugins $(git rev-parse --short HEAD) for Hyprland $hypr_tag."

add_events

basic_warning() {
  echo "WARNING: $1; using simpler drag events." >&2
  echo "Closing a window or changing focus mid-drag can leave the Snap Layouts picker open." >&2
}

if [[ $mode == check ]]; then
  case $events in
    paired)
      git --no-pager diff -U0 -- "$file" "$header" | grep '^+[^+]' || true
      echo "The drag events can be added."
      exit 0 ;;
    basic)
      git --no-pager diff -U0 -- "$file" | grep '^+[^+]' || true
      echo "Only the simpler drag events can be added: some of hyprbars' code has changed." >&2
      exit 0 ;;
  esac
  echo "The drag events can't be added: hyprbars' log lines have changed." >&2
  exit 1
fi

case $events in
  basic) basic_warning "some of hyprbars' code has changed" ;;
  no) no_drag_warning "the drag events can't be added" ;;
esac

build() {
  make -C hyprbars >"$log" 2>&1
}

if ! build; then
  tail -20 "$log" >&2
  if [[ $events == paired ]]; then
    basic_warning "the drag events don't compile on this version"
    reset_source
    if add_basic_events && build; then
      events=basic
    else
      tail -20 "$log" >&2
      events=no
    fi
  elif [[ $events == basic ]]; then
    events=no
  else
    exit 1
  fi
  if [[ $events == no ]]; then
    no_drag_warning "the drag events don't compile on this version"
    reset_source
    if ! build; then
      tail -20 "$log" >&2
      exit 1
    fi
  fi
fi

mkdir -p "$dest"
cp hyprbars/hyprbars.so "$dest/libhyprbars.so.new"

if [[ $mode == build ]]; then
  mv "$dest/libhyprbars.so.new" "$dest/libhyprbars.so"
  echo "Installed $dest/libhyprbars.so (drag events: $events). Not loaded."
  exit 0
fi

mv "$dest/libhyprbars.so.new" "$dest/libhyprbars.so"

# Never swap a running hyprbars. Hyprland 0.56 lists loaded plugins without a
# path, so unloading by path fails and the load adds a second copy. Two copies
# share one set of settings, unloading either breaks the other, and windows end
# up with mismatched title bars.
if hyprctl plugin list 2>/dev/null | grep -q '^Plugin hyprbars '; then
  echo "Installed $dest/libhyprbars.so (drag events: $events)."
  echo "hyprbars is already running, so log out and back in to use the new build."
  exit 0
fi

hyprctl plugin load "$dest/libhyprbars.so" >/dev/null
echo "Installed and loaded $dest/libhyprbars.so (drag events: $events)."
