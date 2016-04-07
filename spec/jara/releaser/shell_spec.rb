# encoding: utf-8

require 'spec_helper'

module Jara
  class Releaser
    describe Shell do
      let :shell do
        described_class.new
      end

      around do |example|
        Dir.mktmpdir do |path|
          Dir.chdir(path) do
            example.call
          end
        end
      end

      describe '#exec' do
        it 'executes the specified command' do
          shell.exec('touch foobar')
          expect(File.exist?('foobar')).to be_truthy
        end

        context 'when the command fails' do
          it 'raises an error' do
            expect { shell.exec('false') }.to raise_error(ExecError)
          end

          it 'includes the command string in the error message' do
            expect { shell.exec('false') }.to raise_error(ExecError, /Command `false` failed/)
          end

          it 'inclues the command output in the error message' do
            expect { shell.exec('echo "bork" && false') }.to raise_error(ExecError, /failed with output: "bork\\n"/)
          end

          it 'does not include the stderr output in the error message' do
            expect { shell.exec('echo "bork" 1>&2 && false') }.to raise_error(ExecError, /failed with output: ""/)
          end
        end

        context 'when the command does not exist' do
          it 'raises an error', pending: 'Not sure this is how it works anymore' do
            expect { shell.exec('foo') }.to raise_error(ExecError, /Command `foo` failed:/)
          end
        end
      end
    end
  end
end
