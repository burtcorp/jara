# encoding: utf-8

require 'spec_helper'


module Jara
  describe Releaser do
    let :production_releaser do
      described_class.new('production', shell: shell, archiver: archiver, file_system: file_system)
    end

    let :staging_releaser do
      described_class.new('staging', shell: shell, archiver: archiver, file_system: file_system)
    end

    let :shell do
      double(:shell)
    end

    let :archiver do
      double(:archiver)
    end

    let :file_system do
      double(:file_system)
    end

    let :executed_commands do
      []
    end

    let :exec_handler do
      lambda { }
    end

    let :archive_options do
      []
    end

    let :project_dir do
      File.expand_path('../../..', __FILE__)
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
      file_system.stub(:mkdir_p)
      file_system.stub(:cp)
    end

    describe '#build_artifact' do
      let :sha do
        'bdd18c1fce7213525a13d4d2d07fd42bc8f435b8'
      end

      let :exec_handler do
        lambda do |command|
          case command
          when 'git rev-parse master && git rev-parse origin/master'
            "#{sha}\n#{sha}\n"
          when /^git clone \S+ \. \&\& git checkout #{sha}$/
            nil
          else
            raise 'Unsupported command: `%s`' % command
          end
        end
      end

      it 'moves to a temporary directory' do
        working_dir = nil
        archiver.stub(:create) do
          os_x_cleaned_working_dir = Dir.getwd.sub(/^\/private/, '')
          working_dir = os_x_cleaned_working_dir
        end
        production_releaser.build_artifact
        working_dir.should start_with(Dir.tmpdir)
      end

      it 'checks out a clean copy of the code' do
        production_releaser.build_artifact
        command = executed_commands.find { |c| c.start_with?('git clone') }
        command.split(' ')[2].should == project_dir
        command.should include("git checkout #{sha}")
      end

      it 'builds an artifact from the checked out code' do
        production_releaser.build_artifact
        archiver.should have_received(:create)
      end

      it 'names the artifact from the project directory, UTC time and SHA' do
        production_releaser.build_artifact
        file_name = archive_options.last[:jar_name]
        components = file_name.split('.').first.split('-')
        components[0].should == 'jara'
        components[1].should == 'production'
        components[2].should start_with(Time.now.utc.strftime('%Y%m%d%H%M'))
        components[3].should == sha[0, 8]
        file_name.should end_with('.jar')
      end

      it 'copies the artifact to the project\'s build directory, creating it if necessary' do
        environment_build_dir = File.join(project_dir, 'build', 'production')
        production_releaser.build_artifact
        file_system.should have_received(:mkdir_p).with(environment_build_dir)
        file_system.should have_received(:cp).with(/^build\/jara-.+\.jar$/, environment_build_dir)
      end

      it 'returns the path to the artifact' do
        environment_build_dir = File.join(project_dir, 'build', 'production')
        path = production_releaser.build_artifact
        path.should start_with(environment_build_dir)
        path.should match(/jara-.+\.jar$/)
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
            when /^git clone \S+ \. \&\& git checkout bdd18c1fce7213525a13d4d2d07fd42bc8f435b8$/
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
    end

    describe '#release' do

    end
  end
end
