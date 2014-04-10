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

# Copyright

© 2014 Burt AB, all rights reserved