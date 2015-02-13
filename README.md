# Jarå

Jarå creates clean artifacts from Git repositories and publishes them to S3. It will check that you've pushed your code, check out a pristine copy from git, build an artifact and upload it to S3 using a name that includes the date, time and Git SHA.

In JRuby it can use [Puck](https://github.com/iconara/puck) to create a standalone JAR file that can be run with `java -jar …`.

# Installation

```ruby
group :development do
  gem 'jara'
  gem 'puck', platform: 'jruby'
end
```

Puck is optional, and only available in JRuby. If Puck is present it will be the default archiver (see below for how to configure this).

# Usage

You can use Jarå either from a `Rakefile` or from the command line. Here's an example from a `Rakefile` that builds an artifact from the master branch and uploads it to the `artifact-bucket` S3 bucket:

```ruby
task :release do
  releaser = Jarå::Releaser.new('production', 'artifact-bucket')
  releaser.release
end
```

## Release names

The JAR artifact will be named from the project name, environment, date stamp and commit SHA, and will be uploaded with a path on S3 that also contains the environment and project name. The name of the directory that contains the code is assumed to be the project name.

For example, if you run it from a directory called "foo_bar" and sets the environment "production" it will build the artifact "foo_bar-production-YYYYmmddHHMMSS-XXXXXXXX.jar", where "YYYYmmddHHMMSS" is the current date and time and "XXXXXXXX" is the first 8 characters from the commit SHA. The artifact will be cached locally in a directory called "build/production" and then uploaded to S3 into the specified bucket, with the key "production/foo_bar/foo_bar-production-YYYYmmddHHMMSS-XXXXXXXX.jar".

If you change "production" to "staging" it will build an artifact from the staging branch instead (and all other paths and names will have "staging" where they had "production" in the description above).

You may have noticed that specifying "production" created an artifact from the master branch, and "staging" used the staging branch. Using anything but "production" means that the branch name is assumed to be the same as the environment.

Before the artifact is built Jarå will check that _branch_name_ and origin/*branch_name* point to the same commit. The reason for this is so that you don't release an artifact with a SHA that is not visible to others (this does not check that you've pulled before you release, but the important thing is to not release something that is not trackable).

## Using the command line tool

The same can be accomplished by running this from the command line:

```
$ jara release --environment production --bucket artifact-bucket
```

## Building tarballs

The primary use case for Jarå is building self contained JAR files, but it can also be used to create tarballs. This can be useful for non-Ruby projects that you want to release the same way you release your JRuby applications.

If you would rather build a tarball you can do that like this:

```ruby
task :tarball do
  releaser = Jarå::Releaser.new('production', 'artifact-bucket', archiver: :tgz)
  releaser.release
end
```

or from the command line:

```
$ jara release --environment production --bucket artifact-bucket --archiver tgz
```

The `tgz` archiver is the default when Puck is not installed.

Sometimes your source code isn't enough to run the application. If you're using Jarå to create a tarball of a purely client side web application you might want to minify all JavaScript and CSS files before the artifact is created. This can be done like this (assuming you have a `Makefile` with a `minify` target):

```ruby
task :tarball do
  releaser = Jarå::Releaser.new('production', 'artifact-bucket', archiver: :tgz, build_command: 'make minify')
  releaser.release
end
```

The command can also be a Ruby proc, or anything that responds to `#call`:

```ruby
task :tarball do
  build_command = lambda do
    FileUtils.touch('very-important-file')
  end
  releaser = Jarå::Releaser.new('production', 'artifact-bucket', archiver: :tgz, build_command: build_command)
  releaser.release
end
```

or from the command line:

```
$ jara release --environment production --bucket artifact-bucket --archiver tgz --build-command 'make minify'
```

The command can be anything, as long as it can run from a cleanly checked out version of your repository.

## Just building an artifact

If you don't want to release an artifact to S3 you can choose to just build one (you don't need to specify the bucket name if you're only building an artifact):

```ruby
task :artifact do
  releaser = Jarå::Releaser.new('production')
  releaser.build_artifact
end
```

and from the command line:

```
$ jara build --environment production
```

## Build from the working directory

In all of the examples above Jarå has checked out a clean copy of your code before building the artifact, but in some cases you just want to pack up everything and see if it works. In those cases you can set the environment to `nil` (or leave out the `--environment` option) to build from the working directory directly. The artifact will be placed directly under the `build` directory and it will be named just after the project directory, it will not have any timestamps nor commit SHA in the name.

# Copyright

© 2014-2015 Burt AB, see LICENSE.txt (BSD 3-Clause).