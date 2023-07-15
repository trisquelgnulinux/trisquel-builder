# Trisquel build system configuration

## Requirements

  - Install sbuild:

        sudo apt-get install sbuild schroot debootstrap eatmydata zstd

  - Configure schroot fstab for ccache

        dir=/var/cache/ccache-sbuild
        sudo install --group=sbuild --mode=2775 -d $dir
        echo $dir $dir none rw,bind 0 0 | sudo tee -a /etc/schroot/sbuild/fstab

        cat << END |sudo tee $dir/sbuild-setup
        #!/bin/sh
        export CCACHE_DIR=$dir
        export CCACHE_UMASK=002
        export CCACHE_COMPRESS=1
        unset CCACHE_HARDLINK
        export PATH="/usr/lib/ccache:\$PATH"
        exec "\$@"
        END

        sudo chmod a+rx $dir/sbuild-setup

  - Add your user to the sbuild group

        sudo addgroup $USER sbuild && newgrp sbuild

## Creating the environment

The first time you will need to create the build jails. This is a one time job that must be done for each version/arch you want to use

    sudo ./sbuild-create.sh $CODENAME $ARCH

This will create the build jails for $CODENAME (flidas, belenos, etc). You can test the jails with:

    schroot -c $CODENAME-$ARCH

You can upgrade the jail with this command:

    sudo sbuild-update -udcar $CODENAME-$ARCH

The binary packages can be built from a dsc by running:

    sbuild --no-run-lintian -v -A --dist $CODENAME --arch $ARCH file.dsc
