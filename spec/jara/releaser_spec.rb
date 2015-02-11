# encoding: utf-8

require 'spec_helper'


module Jara
  describe Releaser do
    let :production_releaser do
      described_class.new('production', 'artifact-bucket', options)
    end

    let :staging_releaser do
      described_class.new('staging', 'artifact-bucket', options)
    end

    let :test_releaser do
      described_class.new(nil, nil, options)
    end

    let :options do
      {
        :shell => shell,
        :archiver => archiver,
        :file_system => file_system,
        :s3 => s3,
        :logger => logger,
      }
    end

    let :shell do
      double(:shell)
    end

    let :archiver do
      double(:archiver, extension: 'bar')
    end

    let :file_system do
      double(:file_system)
    end

    let :s3 do
      double(:s3)
    end

    let :logger do
      double(:logger)
    end

    let :executed_commands do
      []
    end

    let :exec_handler do
      lambda do |command|
        raise 'Unsupported command: `%s`' % command
      end
    end

    let :archive_options do
      []
    end

    before do
      shell.stub(:exec) do |command|
        executed_commands << command
        exec_handler.call(command)
      end
    end

    before do
      archiver.stub(:create) do |options|
        archive_options << options
      end
    end

    before do
      logger.stub(:info)
      logger.stub(:warn)
    end

    before do
      file_system.stub(:mkdir_p)
      file_system.stub(:cp)
    end

    around do |example|
      Dir.mktmpdir do |path|
        fake_jruby_path = File.join(path, 'fake_gems', 'jruby-jars-9.9.9', 'lib')
        FileUtils.mkdir_p(fake_jruby_path)
        $LOAD_PATH << fake_jruby_path
        begin
          app_dir = File.join(path, 'fake_app')
          FileUtils.mkdir_p(app_dir)
          Dir.chdir(app_dir) do
            FileUtils.mkdir('.git')
            example.call
          end
        ensure
          $LOAD_PATH.delete(fake_jruby_path)
        end
      end
    end

    describe '#build_artifact' do
      let :master_sha do
        'bdd18c1fce7213525a13d4d2d07fd42bc8f435b8'
      end

      let :staging_sha do
        '13525a13d4d2d07fd4bdd18c1fce722bc8f435b8'
      end

      let :exec_handler do
        lambda do |command|
          case command
          when 'git rev-parse master && git rev-parse origin/master'
            "#{master_sha}\n#{master_sha}\n"
          when 'git rev-parse staging && git rev-parse origin/staging'
            "#{staging_sha}\n#{staging_sha}\n"
          when /^git archive .+ [a-f0-9]{40}/
            nil
          else
            raise 'Unsupported command: `%s`' % command
          end
        end
      end

      it 'creates a clean copy of the code in a temporary directory' do
        working_dir = nil
        archiver.stub(:create) do
          os_x_cleaned_working_dir = Dir.getwd.sub(/^\/private/, '')
          working_dir = os_x_cleaned_working_dir
        end
        production_releaser.build_artifact
        working_dir.should start_with(Dir.tmpdir)
        command = executed_commands.find { |c| c.start_with?('git archive') }
        archive, unarchive = command.split(' | ')
        archive.should include('--format=tar')
        archive.should include("--prefix=#{File.basename(working_dir)}/")
        archive.should end_with(master_sha)
        unarchive.should eq("(cd #{File.dirname(working_dir)}/ && tar xf -)")
      end

      it 'uses the environment to determine which branch to check out' do
        production_releaser.build_artifact
        command = executed_commands.grep(/^git archive .+ #{master_sha}/).first
        command.should_not be_empty
        executed_commands.clear
        staging_releaser.build_artifact
        command = executed_commands.grep(/^git archive .+ #{staging_sha}/).first
        command.should_not be_empty
      end

      it 'logs the SHA and branch it checked out' do
        production_releaser.build_artifact
        logger.should have_received(:info).with(/checked out #{master_sha[0, 8]} from branch master/i)
      end

      it 'builds an artifact from the checked out code' do
        production_releaser.build_artifact
        archiver.should have_received(:create)
      end

      it 'includes the project directory name, UTC time and SHA in the artifact name' do
        production_releaser.build_artifact
        file_name = archive_options.last[:jar_name]
        components = file_name.split('.').first.split('-')
        components[0].should == 'fake_app'
        components[2].should start_with(Time.now.utc.strftime('%Y%m%d%H%M'))
        components[3].should == master_sha[0, 8]
      end

      it 'lets the archiver choose the file extension' do
        production_releaser.build_artifact
        file_name = archive_options.last[:jar_name]
        file_name.should end_with('.bar')
      end

      it 'includes the environment in the artifact name' do
        production_releaser.build_artifact
        file_name = archive_options.last[:jar_name]
        components = file_name.split('.').first.split('-')
        components[1].should == 'production'
        staging_releaser.build_artifact
        file_name = archive_options.last[:jar_name]
        components = file_name.split('.').first.split('-')
        components[1].should == 'staging'
      end

      it 'logs the name of the artifact' do
        production_releaser.build_artifact
        logger.should have_received(:info).with(/created artifact fake_app-production-\d{14}-[a-f0-9]{8}\.bar/i)
      end

      it 'copies the artifact to the project\'s build directory, creating it if necessary' do
        environment_build_dir = File.join(Dir.getwd, 'build', 'production')
        production_releaser.build_artifact
        file_system.should have_received(:mkdir_p).with(environment_build_dir)
        file_system.should have_received(:cp).with(/^build\/fake_app-.+\.bar$/, environment_build_dir)
      end

      it 'returns the path to the artifact' do
        environment_build_dir = File.join(Dir.getwd, 'build', 'production')
        path = production_releaser.build_artifact
        path.should start_with(environment_build_dir)
        path.should match(/fake_app-.+\.bar$/)
      end

      context 'when the project directory can\'t be found' do
        it 'raises an error' do
          Dir.chdir('/var/log') do
            expect { production_releaser.build_artifact }.to raise_error(JaraError, /could not find project dir/i)
          end
        end
      end

      context 'when the checkout fails' do
        let :exec_handler do
          lambda do |command|
            case command
            when 'git rev-parse master && git rev-parse origin/master'
              "bdd18c1fce7213525a13d4d2d07fd42bc8f435b8\nbdd18c1fce7213525a13d4d2d07fd42bc8f435b8\n"
            when /^git archive .+ bdd18c1fce7213525a13d4d2d07fd42bc8f435b8/
              raise ExecError, 'Bork fork'
            else
              raise 'Unsupported command: `%s`' % command
            end
          end
        end

        it 'raises an error' do
          expect { production_releaser.build_artifact }.to raise_error(ExecError, 'Bork fork')
        end
      end

      context 'when master is not in sync' do
        let :exec_handler do
          lambda do |command|
            case command
            when 'git rev-parse master && git rev-parse origin/master'
              "bdd18c1fce7213525a13d4d2d07fd42bc8f435b8\nd65fc91996f00171679dacc5c16da338a1b21062\n"
            else
              raise 'Unsupported command: `%s`' % command
            end
          end
        end

        it 'raises an error' do
          expect { production_releaser.build_artifact }.to raise_error(JaraError, /master and origin\/master are not in sync/i)
        end
      end

      context 'when an artifact for the current SHA already exists' do
        before do
          FileUtils.mkdir_p('build/production')
          FileUtils.touch("build/production/fake_app-production-20140409163201-#{master_sha[0, 8]}.bar")
        end

        it 'does not build a new artifact' do
          production_releaser.build_artifact
          archiver.should_not have_received(:create)
        end

        it 'logs a message saying that no new artifact was built, with the name of the existing' do
          production_releaser.build_artifact
          logger.should have_received(:warn).with(/an artifact for #{master_sha[0, 8]} already exists: fake_app-production-\d{14}-[a-f0-9]{8}\.bar/i)
        end
      end

      context 'when building a test artifact' do
        it 'builds an artifact from the project working directory and puts it in the build directory' do
          app_dir = Dir.getwd
          working_dir = nil
          create_options = nil
          archiver.stub(:create) do |options|
            working_dir = Dir.getwd
            create_options = options
          end
          path = nil
          FileUtils.mkdir_p('foo')
          Dir.chdir('foo') do
            path = test_releaser.build_artifact
          end
          path.should == "#{app_dir}/build/fake_app.bar"
          working_dir.should == app_dir
          create_options.should eql(jar_name: 'fake_app.bar')
        end

        it 'logs that it builds a test artifact' do
          test_releaser.build_artifact
          logger.should have_received(:info).with(/created test artifact/i)
        end
      end
    end

    describe '#release' do
      let :sha do
        'bdd18c1fce7213525a13d4d2d07fd42bc8f435b8'
      end

      let :exec_handler do
        lambda do |command|
          case command
          when /git rev-parse \w+ \&\& git rev-parse origin\/\w+/
            "#{sha}\n#{sha}\n"
          when /^git archive .+ [a-f0-9]{40}/
            nil
          when 'git config --get remote.origin.url'
            'git@example.com:foo/bar'
          else
            raise 'Unsupported command: `%s`' % command
          end
        end
      end

      let :s3_puts do
        []
      end

      before do
        s3.stub(:put_object) do |options|
          s3_puts << options
        end
        s3.stub(:list_objects).and_return(double(contents: []))
        file_system.stub(:cp) do |path, to_dir|
          FileUtils.mkdir_p(to_dir)
          File.open(File.join(to_dir, File.basename(path)), 'w') { |io| io.puts('foo') }
        end
      end

      it 'builds an artifact for the specified environment' do
        production_releaser.release
        staging_releaser.release
        command = executed_commands.find { |c| c.include?('git rev-parse master') }
        command.should_not be_nil
        command = executed_commands.find { |c| c.include?('git rev-parse staging') }
        command.should_not be_nil
        archiver.should have_received(:create).twice
      end

      it 'uploads the artifact' do
        production_releaser.release
        File.read(s3_puts.last[:body].path).should == "foo\n"
      end

      it 'uploads the artifact to S3 into a directory named after the environment' do
        production_releaser.release
        s3_puts.last[:bucket].should == 'artifact-bucket'
        s3_puts.last[:key].should start_with('production/fake_app/fake_app-production-')
      end

      it 'uploads the artifact with an appropriate content type' do
        production_releaser.release
        s3_puts.last[:content_type].should == 'application/java-archive'
      end

      it 'uploads the artifact and sends its MD5 sum as a Base64 encoded string' do
        production_releaser.release
        s3_puts.last[:content_md5].should == '07BzhNET7exJ6qYjitX/AA=='
      end

      it 'sets metadata that includes who built the artifact, the full SHA, the Git remote and the JRuby version' do
        production_releaser.release
        s3_puts.last[:metadata]['packaged_by'].should include(%x(whoami).strip)
        s3_puts.last[:metadata]['packaged_by'].should match(/^.+@.+$/)
        s3_puts.last[:metadata].should include(
          'sha' => sha,
          'remote' => 'git@example.com:foo/bar',
          'jruby' => '9.9.9',
        )
      end

      it 'includes extra metadata from the :metadata option' do
        options[:metadata] = {'foo' => 'bar', 'hello' => 'world'}
        production_releaser.release
        s3_puts.last[:metadata].should include('foo' => 'bar', 'hello' => 'world')
      end

      it 'overwrites default metadata with the :metadata option' do
        options[:metadata] = {'sha' => 'bar', 'packaged_by' => 'me'}
        production_releaser.release
        s3_puts.last[:metadata].should include('sha' => 'bar', 'packaged_by' => 'me')
      end

      it 'logs that the artifact was uploaded' do
        production_releaser.release
        logger.should have_received(:info).with(%r<artifact uploaded to s3://artifact-bucket/production/fake_app/fake_app-production-\d{14}-[a-f0-9]{8}\.bar>i)
      end

      it 'uses an existing artifact for the same SHA' do
        FileUtils.mkdir_p('build/production')
        File.open("build/production/fake_app-production-20140409163201-#{sha[0, 8]}.bar", 'w') { |io| io.puts('bar') }
        production_releaser.release
        archiver.should_not have_received(:create)
        s3_puts.last[:content_md5].should == 'wVenkDHhxA+FkxgpvF/FUg=='
      end

      it 'returns the artifact URI' do
        uri = production_releaser.release
        uri.should match(%r<s3://artifact-bucket/production/fake_app/fake_app-production-\d{14}-[a-f0-9]{8}\.bar>i)
      end

      it 'raises an error when the environment is not set' do
        expect { test_releaser.release }.to raise_error(JaraError, /no environment set/i)
      end

      it 'raises an error when the bucket is not set' do
        releaser = described_class.new('production', nil, shell: shell, archiver: archiver, file_system: file_system, logger: logger)
        expect { releaser.release }.to raise_error(JaraError, /no bucket name set/i)
      end

      context 'when an artifact for the same SHA already exists on S3' do
        before do
          objects = [
            double(key: 'production/fake_app/fake_app-production-20140409163201-eaa6238a.bar'),
            double(key: 'production/fake_app/fake_app-production-20140409180210-bdd18c1f.bar'),
          ]
          listing = double(contents: objects)
          s3.stub(:list_objects).with(bucket: 'artifact-bucket', prefix: 'production/fake_app/fake_app-production-').and_return(listing)
        end

        it 'does not build the artifact' do
          production_releaser.release
          archiver.should_not have_received(:create)
        end

        it 'does not upload any artifact' do
          production_releaser.release
          s3.should_not have_received(:put_object)
        end

        it 'logs a message saying that the artifact was not uploaded, with the URI of the existing' do
          production_releaser.release
          logger.should have_received(:warn).with(%r<an artifact for #{sha[0, 8]} already exists: s3://artifact-bucket/production/fake_app/fake_app-production-\d{14}-[a-f0-9]{8}\.bar>i)
        end

        it 'returns the artifact URI' do
          uri = production_releaser.release
          uri.should match(%r<s3://artifact-bucket/production/fake_app/fake_app-production-\d{14}-[a-f0-9]{8}\.bar>i)
        end

        context 'and the option :re_release is true' do
          before do
            options[:re_release] = true
          end

          it 'proceeds as if the artifact did not already exist' do
            production_releaser.release
            s3.should have_received(:put_object)
          end

          it 'does not list objects on S3' do
            production_releaser.release
            s3.should_not have_received(:list_objects)
          end
        end
      end
    end
  end
end
