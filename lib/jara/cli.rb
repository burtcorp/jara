# encoding: utf-8

require 'jara'
require 'optparse'

module Jara
  class Cli
    def initialize(argv)
      parse_options(argv)
      @releaser = Jara::Releaser.new(@environment, @bucket, archiver: @type)
    end

    def run
      if @release
        @releaser.release
      else
        @releaser.build_artifact
      end
    end

    private

    def parse_options(argv)
      parser = OptionParser.new do |parser|
        parser.on('-r', '--[no-]release', 'Release artifact to S3') { |r| @release = r }
        parser.on('-b', '--bucket=BUCKET', 'S3 bucket for releases') { |b| @bucket = b }
        parser.on('-e', '--environment=ENV', 'Environment to release to (e.g. production, staging)') { |e| @environment = e }
        parser.on('-t', '--type=TYPE', 'Archive type (jar or tgz)') { |t| @type = t.to_sym }
      end
      parser.parse(argv)
    end
  end
end
