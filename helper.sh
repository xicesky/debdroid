#!/bin/bash

ARCH=${ARCH:-"armel"}
RELEASE=${RELEASE:-"jessie"}
VARIANT=${VARIANT:-"minbase"}
MIRROR=${MIRROR:-"http://ftp2.de.debian.org/debian"}

IMAGE_SIZE_MB=${IMAGE_SIZE_MB:-"512"}
IMAGE_SIZE_BYTES="`expr $IMAGE_SIZE_MB \* 1024 \* 1024`"

REALUSER=${REALUSER:-"`id -un`"}
VERBOSE=${VERBOSE:-"false"}
SUDO=${SUDO:-"`which sudo` -E"}

export ARCH RELEASE VARIANT MIRROR REALUSER VERBOSE SUDO

amiroot() {
    test "`id -u`" = "0"
}

invoke() {
    echo "$@"
    "$@"
}

wrap_bootstrap() {
    invoke debootstrap \
        --foreign --arch="$ARCH" \
        --variant="$VARIANT" \
        "$@"
}

MODE="$1"
shift

case $MODE in
    checks)
        if ! amiroot ; then
            $SUDO "$0" "$MODE" "$@"
        else
            # TODO Check for debootstrap
            ! $VERBOSE || echo "Checks successful." # We avoid negative returns by using "! $VERBOSE ||"
        fi
        ;;

    bootstrap-download)
        DEST="$1"
        [ -z "$DEST" ] && DEST="cache/debootstrap-${RELEASE}-${ARCH}.tar.gz"
        [ -e "$DEST" ] && { echo "Destination file or directory exists: \"$DEST\"" 1>&2 ; exit 1; }
        # EVEN THE FUCKING DOWNLOADER NEEDS TO BE ROOT?
        # FU debootstrap!
        if ! amiroot ; then
            $SUDO "$0" "$MODE" "$@"
        else
            TEMPDIR=`mktemp -d build/debootstrap.XXXXXXXX`
            wrap_bootstrap --verbose --make-tarball "$DEST" "$RELEASE" "$TEMPDIR" "$MIRROR"
            RESULT="$?"
            rm -r "$TEMPDIR"
            # When debootstrap fails it _sometimes_ leaves us with a dest file anyway...
            if [ ! "$RESULT" -eq "0" ] ; then
                echo "debootstrap failed." 1>&2
                rm "$DEST"  # Clean up on error
                exit $RESULT
            fi
            set -e
            chmod 660 "$DEST"
            chown $REALUSER "$DEST"
            set +e
        fi
        ;;

    bootstrap)
        DEST="$1"
        [ -e "$DEST" ] && { echo "Destination file or directory exists: \"$DEST\"" 1>&2 ; exit 1; }
        if ! amiroot ; then
            $SUDO "$0" "$MODE" "$@"
        else
            mkdir "$DEST" || exit 1
            # Check if we have a cached bootstrap thingy
            CACHED="$2"
            # Oh debootstrap why do you care about fucking filenames... tar.gz should be valid...
            [ -z "$CACHED" ] && CACHED="cache/deboostrap-${RELEASE}-${ARCH}.tgz"

            if [ -e "$CACHED" ] ; then
                # WTF does debootstrap need a absolute path for
                CACHED="`readlink -f "$CACHED"`"
                wrap_bootstrap --verbose --unpack-tarball "$CACHED" "$RELEASE" "$DEST"
            else
                wrap_bootstrap --verbose "$RELEASE" "$DEST" "$MIRROR"
            fi

            RESULT="$?"
            if [ "$RESULT" -eq "0" ] ; then
                # debootstrap fucks up the date of the target folder
                touch "$DEST"
            else
                rm -r "$DEST"  # Clean up on error
            fi
            exit $RESULT
        fi
        ;;

    tarball)
        SOURCE="$1"
        DEST="$2"
        [ -z "$DEST" ] && DEST="`basename $SOURCE`.tar.gz"
        [ -d "$SOURCE" ] || { echo "Source directory missing: \"$SOURCE\"" 1>&2 ; exit 1; }
        [ -e "$DEST" ] && { echo "Destination file exists: \"$DEST\"" 1>&2 ; exit 1; }

        if ! amiroot ; then
            $SUDO "$0" "$MODE" "$@"
        else
            set -e
            tar cvzf "$DEST" "$SOURCE"
            chmod 660 "$DEST"
            chown "$REALUSER" "$DEST"
            set +e
        fi
        ;;

    format-fsimage)
        IMAGE="$1"
        FSTYPE=ext4
        if ! amiroot ; then
            $SUDO "$0" "$MODE" "$@"
        else
            set -e
            DEV=`losetup -f`
            losetup "$DEV" "$IMAGE"
            mkfs -t $FSTYPE "$DEV"
            losetup -d "$DEV"
            set +e
        fi
        ;;

    loop-mount)
        SOURCE="$1"
        DEST="$2"
        #MARKER="$3"
        [ -z "$DEST" ] && DEST="`basename $SOURCE`.mnt"
        [ -z "$MARKER" ] && MARKER="`basename $SOURCE`.status"
        [ -f "$SOURCE" ] || { echo "Source file missing: \"$SOURCE\"" 1>&2 ; exit 1; }
        [ -e "$DEST" ] && { echo "Destination file exists: \"$DEST\"" 1>&2 ; exit 1; }
        #[ -e "$MARKER" ] && { echo "Marker file exists: \"$MARKER\"" 1>&2; exit 1; }

        if ! amiroot ; then
            $SUDO "$0" "$MODE" "$@"
        else
            # Oh i didn't know that, how fancy:
            # <quote source="man mount">
            #   Since  Linux 2.6.25 is supported auto-destruction of loop devices and then any loop
            #   device allocated by mount will be freed by umount independently on /etc/mtab.
            # </quote>

            set -e
            mkdir "$DEST"
            mount "$SOURCE" "$DEST" -o loop
            #echo "#!/bin/sh" >$MARKER
            #echo "umount \"$DEST\"" >>$MARKER
            set +e
        fi
        ;;

    umount)
        DEST="$1"
        [ -d "$DEST" ] || { echo "Destination missing or not a directory: \"$DEST\"" 1>&2 ; exit 1; }
        
        if ! amiroot ; then
            $SUDO "$0" "$MODE" "$@"
        else
            umount "$DEST"
        fi
        ;;

    copy-content)
        SOURCE="$1"
        DEST="$2"

        [ -d "$SOURCE" ] || { echo "Source missing or not a directory: \"$SOURCE\"" 1>&2 ; exit 1; }
        [ -d "$DEST" ] || { echo "Destination missing or not a directory: \"$DEST\"" 1>&2 ; exit 1; }

        if ! amiroot ; then
            $SUDO "$0" "$MODE" "$@"
        else
            # rsync >> cp
            # The slash after source is important.
            rsync -avxHAX -W -P --numeric-ids "$SOURCE/" "$DEST"
        fi
        ;;

    info|*)
        FMT="%18s: %s\\n"
        #echo "$0 $MODE $@"
        printf "$FMT" ARCH "$ARCH"
        printf "$FMT" RELEASE "$RELEASE"
        printf "$FMT" VARIANT "$VARIANT"
        printf "$FMT" MIRROR "$MIRROR"
        printf "$FMT" IMAGE_SIZE_MB "$IMAGE_SIZE_MB"
        printf "$FMT" IMAGE_SIZE_BYTES "$IMAGE_SIZE_BYTES"
        ;;

esac

