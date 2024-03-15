#!/bin/bash

KILL=1
UI=1
START_ONLY=0
REFUI_ONLY=0
DEMOSRC="image-gallery-ship"
SIRE_FILE="sire/demo_image_gallery.sire"
UI_DIR="image-gallery/image-gallery-ui"

usage ()
{
  echo "Usage: ./web-demo -d ship_directory -s sire-file.sire -u ui_directory 

  This will:

    1. Create a .ships/ship_directory ship (destroying the dir first if it exists)
    2. Boot a machine here using sire-file.sire
    3. Start the machine
    4. PUT in the UI files (from ui_directory)
    5. Copy the localhost URL to the clipboard (if xclip is installed)

  To re-start an existing ship (non-destructive):
    ./web-demo -d ship_directory --start-only

    - 'plunder start' the ship
    - will not mess with UI files
    - the port will be different - check it.

  To re-set UI files: ./web-demo -d ship_directory -u ui_directory --refresh-ui

    - assumes the ship is already running
    - re-uploads the UI files
    - doesn't restart the ship, so the port stays the same

  All options explained:

    --no-kill will not destroy the dir if it exists
    --no-ui will not PUT the ui files
    --start-only will only start the ship, not do anything with sire files or ui files
    --refresh-ui will PUT the ui files _again_ (must also pass -u flag!)
  "
  exit 2
}

echo "Got access key ${ACCESS_KEY}"

PARSED_ARGUMENTS=$(
    getopt -a -n alphabet \
        -o d:s:u: \
        --long no-kill,no-ui,start-only,refresh-ui,help \
        -- "$@"
)
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
  usage
fi

eval set -- "$PARSED_ARGUMENTS"
while :
do
  case "$1" in
    -d)                    DEMOSRC="$2"             ; shift 2 ;;
    -s)                    SIRE_FILE="$2"           ; shift 2 ;;
    -u)                    UI_DIR="$2"              ; shift 2 ;;
    --start-only)          START_ONLY=1             ; shift   ;;
    --refresh-ui)          REFUI_ONLY=1             ; shift   ;;
    --no-kill)             KILL=0                   ; shift   ;;
    --no-ui)               UI=0                     ; shift   ;;

    # Don't "error" on help.
    --help) usage ;;

    # -- means the end of the arguments; drop this, and break out of the while loop
    --) shift; break ;;

    # If invalid options were passed, then getopt should have reported an error,
    # which we checked as VALID_ARGUMENTS when getopt was called...
    *) echo "Unexpected option: $1 - this should not happen."
       usage ;;
  esac
done

# Only operate on the `.demo` directory.
export MACHINE_DIR=$(realpath .ships/"$DEMOSRC")

plunder=/usr/local/bin/plunder

echo "machine dir $MACHINE_DIR"

function boot () {
  waited=0
  until [ -d "$MACHINE_DIR" ]
  do
      if [ $waited -eq 0 ]; then
          echo "Waiting for $MACHINE_DIR directory to be created"
          waited=1
      fi

      sleep 0.1
  done
  echo "Booting .ships/$DEMOSRC with $SIRE_FILE"
  $plunder boot ".ships/$DEMOSRC" "$SIRE_FILE"
}

function set_address () {
  local port=$1
  local base_url="http://localhost:$port"

  echo "Setting eth address..."
  curl -X POST -H "authorization: $ACCESS_KEY" -H "Content-Type: application/json" --data '{"address":"'"$OWNER_ADDRESS"'"}' "$base_url/set-address"
  echo "Address set to $OWNER_ADDRESS"
}

function set_interface () {
  local port=$1
  local base_url="http://localhost:$port"

  echo "Setting interface files from $UI_DIR..."
  echo "To $base_url"

  # Find all files in UI_DIR and loop over them
    while IFS= read -r file; do
        # Skip directories
        if [[ -d "$file" ]]; then
            continue
        fi

        # Get the path relative to UI_DIR
        local file_relative_path="${file#$UI_DIR}"
        local url="$base_url$file_relative_path"

        # Determine content type
        local content_type=""
        case "$file" in
            *.html) content_type="text/html" ;;
            *.js) content_type="text/javascript" ;;
            *.css) content_type="text/css" ;;
            *.json) content_type="application/json" ;;
            *.png) content_type="image/png" ;;
            *.jpg|*.jpeg) content_type="image/jpeg" ;;
            *.mp4) content_type="video/mp4" ;;
            *.webm) content_type="video/webm" ;;
            *.svg) content_type="image/svg+xml" ;;
            *.otf) content_type="font/otf" ;;
            *.woff) content_type="font/woff" ;;
            *.woff2) content_type="font/woff2" ;;
            *.ttf) content_type="font/ttf" ;;
            # add other file types as needed
        esac

        # Upload the file
        echo "Uploading $file to $url"
        curl --data-binary @"$file" -H "Content-Type: $content_type" -H "authorization: $ACCESS_KEY" -X PUT "$url"

    done < <(find "$UI_DIR" -type f) # Use process substitution to avoid subshell
}

function start () {
  $plunder start "$MACHINE_DIR" &
  RUN_MACHINE=$!

  until find "$MACHINE_DIR" -maxdepth 1 -name "*.http.port" -quit
  do
       echo "Waiting..."
       sleep 0.1
  done

  # Why an additional sleep here? Some weird filesystem sync issue where the
  # port file was created, but hasn't been written to yet.
  sleep 1

  # TODO: for manual port setting. not okay for localhost testing.
  # PORT=$(cat "$MACHINE_DIR"/*.http.port)
  PORT=8080

  if [ "${UI}" -eq "1" ] && [ "${START_ONLY}" -eq "0" ]; then
    # Poll the backend service until it responds with a 200 status code
    # echo "Waiting for the backend service to be ready..."
    # while true; do
    #   response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/")
    #   if [ "$response" -eq "200" ]; then
    #     echo "Backend service is ready"
    #     break
    #   else
    #     echo "Backend service is not ready yet. Retrying in 1 second..."
    #     sleep 1
    #   fi
    # done

    # set eth address
    set_interface $PORT
    set_address $PORT
    echo "Interface files are set. Running on http://localhost:$PORT/index.html"
  fi

  sleep 0.5

  wait $RUN_MACHINE
}

if [ "${START_ONLY}" -eq "1" ]; then
  echo "Only starting ship..."
  start
fi

echo "got ship $DEMOSRC"
echo "got sire $SIRE_FILE"
echo "got ui $UI_DIR"

if [ "${REFUI_ONLY}" -eq "1" ]; then
  PORT=$(cat "$MACHINE_DIR"/*.http.port)
  echo "Rehydrating UI files on $PORT..."
  set_interface $PORT
  exit 0
fi

if [ "${KILL}" -eq "1" ]; then
  echo "removing .ships/$DEMOSRC..."
  rm -rf ".ships/$DEMOSRC"
  echo "creating .ships/$DEMOSRC..."
  mkdir -p ".ships/$DEMOSRC"
else
  echo "just creating $DEMOSRC"
  mkdir -p ".ships/$DEMOSRC"
fi

boot
start
