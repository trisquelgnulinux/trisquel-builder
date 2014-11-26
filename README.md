# Trisquel build system configuration

## Requirements

  - Install pbuilder:

        sudo apt-get install pbuilder

  - Add the following content to /etc/sudoers

        Defaults        env_reset, env_keep="DIST ARCH BUILD* TMPFS SIGNED"
        Cmnd_Alias PBUILDER = /usr/sbin/pbuilder, /usr/bin/pdebuild, /usr/bin/debuild-pbuilder
        [your_user] ALL=(ALL) SETENV: NOPASSWD: PBUILDER

  - Clone the build environment

        git clone http://devel.trisquel.info:10080/aklis/trisquel-builder.git

  - Put config files in place
        ln -s $(readlink -f trisquel-builder/pbuilderrc) ~/.pbuilderrc
        sudo ln -s $(readlink -f trisquel-builder/hooks) /var/cache/pbuilder/hooks.d



## Creating the environment

The first time you will need to create the build jails. This is a one time job that must be done for each version/arch you want to use

    sudo HOME=/home/<user> DIST=belenos ARCH=amd64 pbuilder create

If order to use the same build base for building and development, I do the following:

    sudo HOME=/home/<user> DIST=belenos ARCH=amd64 pbuilder --execute --save-after-exec /bin/mkdir -p /home/<user>/package-helpers

And then, use it with:

    sudo HOME=/home/<user> BUILDHELPERS=/home/<user>/package-helpers DIST=belenos ARCH=amd64 pbuilder login

Where BUILDHELPERS is the place where your git checkout resides.

You can do now the changes to the helper script, and try if it works with:
  `bash make-<package>`

Once everything is finished, you will have a .dsc and a .tar.gz file placed in `$BUILDHELPERS/helpers/PACKAGES/<packagename>` , and you can exit this pbuilder development environment with  `Exit` , 

The binary package can be built be running:


Have in mind that, for now, you will need to cherry-pick [this change](https://devel.trisquel.info/aklis/package-helpers/commit/68801b100df36bd6cb70f3fff2eff0d1f83e8653) into your checkout.
