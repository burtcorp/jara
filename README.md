# Jarå

Jarå builds self-contained JARs of JRuby applications and publishes them to S3. It will check that you've pushed your code, check out a pristine copy from git, build a JAR and upload it to S3.

# Usage

```
# this will build an artifact from master and upload it to
# the "artifact-bucket" on S3
releaser = Jarå::Releaser.new('production', 'artifact-bucket')
releaser.release
```

The JAR artifact will be named from the project name, environment, date stamp and commit SHA, and will be uploaded with a path on S3 that also contains the environment and project name. The name of the directory that contains the code is assumed to be the project name.

For example, if you run it from a directory called "foo_bar" and sets the environment "production" it will build the artifact "foo_bar-production-YYYYmmddHHMMSS-XXXXXXXX.jar", where "YYYYmmddHHMMSS" is the current date and time and "XXXXXXXX" is the first 8 characters from the commit SHA. The artifact will be cached locally in a directory called "build/production" and then uploaded to S3 into the specified bucket, with the key "production/foo_bar/foo_bar-production-YYYYmmddHHMMSS-XXXXXXXX.jar".

If you change "production" to "staging" it will build an artifact from the staging branch instead (and all other paths and names will have "staging" where they had "production" in the description above).

You may have noticed that specifying "production" created an artifact from the master branch, and "staging" used the staging branch. Using anything but "production" means that the branch name is assumed to be the same as the environment.

Before the artifact is built Jarå will check that _branch_name_ and origin/*branch_name* point to the same commit. The reason for this is so that you don't release an artifact with a SHA that is not visible to others (this does not check that you've pulled before you release, but the important thing is to not release something that is not trackable).

# Copyright

© 2014 Burt AB, see LICENSE.txt (BSD 3-Clause).