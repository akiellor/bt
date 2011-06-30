require 'yaml'
require 'grit'
require 'forwardable'

module Project
  module RSpec
    def self.included base
      base.extend ClassMethods
    end

    module ClassMethods
      def project &block
        let!(:project) { Model.at(Dir.mktmpdir, &block) }

        subject { project }
      end

      def results_for_stage name, &block
       it { should have_bt_ref name, subject.head }

       describe "the result for #{name.inspect}" do
          define_method(:subject) do
            super().bt_ref(name, super().head)
          end

          instance_eval &block
        end
      end
    end
  end

  class Model
    class Ref < Grit::Ref
      extend Forwardable

      def_delegator :commit, :tree

      def self.prefix
        "refs/bt"
      end
    end

    DEFAULT_STAGE_DEFINITION = {'run' => 'exit 0', 'needs' => [], 'results' => []}

    def self.at dir, &block
      FileUtils.cd(dir) do |dir|
        return new(dir, &block)
      end
    end

    attr_reader :repo

    def initialize dir, &block
      @repo = Grit::Repo.init(dir)
      yield self
      @repo.commit_all("Initial commit")
    end

    def stage name, stage_config
      FileUtils.makedirs("#{@repo.working_dir}/stages")
      File.open("#{@repo.working_dir}/stages/#{name.to_s}", 'w') do |f|
        f.write(stage_config)
      end
      @repo.add "stages/#{name.to_s}"
    end

    def failing_stage name, overrides = {}
      stage name, YAML.dump(DEFAULT_STAGE_DEFINITION.merge('run' => 'exit 1').merge(overrides))
    end

    def head
      repo.commits.first
    end

    def passing_stage name, overrides = {}
      stage name, YAML.dump(DEFAULT_STAGE_DEFINITION.merge(overrides))
    end

    def stage_generator name, generator_config
      stage(name, generator_config)
      File.chmod(0755, "#{@repo.working_dir}/stages/#{name.to_s}")
    end

    def bt_ref stage, commit
      Ref.find_all(self.repo).detect { |r| r.name == "#{commit.sha}/#{stage}" }
    end

    def build
      output = %x{bt-go --once --debug --directory #{repo.working_dir} 2>&1}
      raise output unless $?.exitstatus.zero?
    end

    def results
      output = %x{bt-results --debug --uri #{repo.working_dir} 2>&1}
      raise output unless $?.exitstatus.zero?
      output
    end

    def definition
      output = %x{bt-stages #{repo.working_dir}}
      raise output unless $?.exitstatus.zero?
      output
    end

    def ready?
      output = %x{bt-ready #{repo.working_dir}}
      raise output unless $?.exitstatus.zero?
      !output.empty?
    end
  end
end

RSpec::Matchers.define :have_bt_ref do |stage, commit|
  match do |project|
    project.bt_ref(stage, commit)
  end
end

RSpec::Matchers.define :have_file_content do |name, content|
  match do |tree|
    (tree / name).data == content
  end

  failure_message_for_should do |tree|
    "Expected #{name.inspect} to have content #{content.inspect} but had #{(tree / name).data.inspect}"
  end
end

RSpec::Matchers.define :have_file_content_in_tree do |name, content|
  match do |commit|
    (commit.tree / name).data == content
  end

  failure_message_for_should do |commit|
    "Expected #{name.inspect} to have content #{content.inspect} but had #{(commit.tree / name).data.inspect}"
  end
end

RSpec::Matchers.define :have_results do |results|
  match do |project|
    result_string = project.results
    results.all? do |stage, result_commit|
      result_string.index /^#{stage.to_s}: (PASS|FAIL) bt loves you \(#{result_commit.sha}\)$/
    end
  end
end

