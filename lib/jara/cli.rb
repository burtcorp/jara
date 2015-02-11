# encoding: utf-8

require 'jara'
require 'optparse'

module Jara
  class Cli
    def initialize(argv)
      @command = argv.first
      @argv = argv.drop(1)
    end

    def run
      parse_argv(@argv)
      options = {}
      options[:archiver] = @archiver if @archiver
      options[:build_command] = @build_command if @build_command
      releaser = Jara::Releaser.new(@environment, @bucket, options)
      case @command
      when /help|-h/
        $stderr.puts(option_parser)
      when 'release'
        releaser.release
      when 'build'
        releaser.build_artifact
      else
        $stderr.puts('Unknown command "%s", expected "build" or "release"' % @command)
        exit(1)
      end
    rescue JaraError => e
      $stderr.puts(sprintf('Could not %s artifact: %s', @command, e.message))
      exit(1)
    end

    private

    def option_parser
      @option_parser ||= OptionParser.new do |parser|
        parser.banner = "Usage: jara build [options]\n       jara release [options]"
        parser.separator ''
        parser.separator 'Common options:'
        parser.on('-e', '--environment=ENV', 'Environment to release to (e.g. production, staging)') { |e| @environment = e }
        parser.on('-a', '--archiver=TYPE', 'Archiver to use (jar or tgz)') { |t| @archiver = t.to_sym }
        parser.on('-c', '--build-command=COMMAND', 'Command to run before creating the artifact') { |c| @build_command = c }
        parser.on('-h', '--help', 'Show this message') { @command = 'help' }
        parser.separator ''
        parser.separator 'Release options:'
        parser.on('-b', '--bucket=BUCKET', 'S3 bucket for releases') { |b| @bucket = b }
        parser.separator ''
      end
    end

    def parse_argv(argv)
      option_parser.parse(argv)
    end
  end
end
