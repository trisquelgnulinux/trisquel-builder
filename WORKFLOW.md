
      Jenkins job	           Description
  
    +------------------------+     - An automatic build can be fired by a git trigger, or by an ubuntu package upgrade
    |  Watchdogs/Triggers    |     - The job creates files with environment variables related to the packages to be built, and launch
    +------------------------+       the build-dsc job whith them as parameters
               |
	       |
	       |
	       V
    +-----------------------+	   - This job has the BUILDPACKAGE , BUILDBRANCH and BUILDDIST parameters.
    |     build-dsc         |      - It runs on a jenkins slave created using pbuilder, and that can be redeployed at any time
    +-----------------------+	   - On the slave for the BUILDIST trisquel version, does the following steps:
	       |				- clone git repo
	       |				- (While not upstreamed) Patch helpers/config
	       |				- Run helpers/make-$BUILDPACKAGE
	       |				- Archive the .dsc file produced by the previous steps
               |
	       V
   +------------------------+       - Using the previously built dsc file, build the binary packages
   |      build-binaries    |			- pbuild build PACKAGE.dsc
   |    amd64    i386       |			- archive the results outside pbuilder
   +------------------------+
               |
	       |
	       |
  	       V 
   +------------------------+	    - Built packages are left on a development repo, so they can be tested or used for next builds
   |	     Tests	    |	    
   +------------------------+
               |
	       |
               V
   +------------------------+	    - For automatic builds, we can also automate the publishing step
   |        Upload	    |       - For merge requests, and user contributions, we need first to build the package using the users's repo, and once
   |	    Sign	    |	      we are sure about the helper, merge it on the official trisquel repo, so it will reach the official repos
   |	    Publish	    |
   +------------------------+
 
   

