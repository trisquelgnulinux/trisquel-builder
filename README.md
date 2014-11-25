#Trisquel build system configuration

##Requirements

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



## Building packages

The first time you will need to create the build jails. This is a one time job that must be done for each version/arch you want to use

    sudo DIST=belenos ARCH=amd64 pbuilder create

    
