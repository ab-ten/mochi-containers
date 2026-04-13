# frozen_string_literal: true

require_relative "failure_notifier"
require_relative "redmine_repo_tools"

module GitTriggers
  class BatchRunner
    REPO_ROOT = "/var/git/repos"

    def initialize(repo_names)
      @repo_names = repo_names.uniq
      @verbose_level = ENV.fetch("GIT_TRIGGERS_VERBOSE_LEVEL", "0").to_i
      @had_error = false
    end

    def run
      info("batch repositories: #{@repo_names.join(', ')}")

      @repo_names.each do |repo_name|
        process_repository(repo_name)
      end

      @had_error ? 1 : 0
    end

    private

    def process_repository(repo_name)
      repo_path = File.join(REPO_ROOT, "#{repo_name}.git")
      info("refresh repository: #{repo_name} path=#{repo_path}")

      ids = RedmineRepoTools.find_project_and_repository_ids_by_git_full_path(repo_path)
      debug("repository mapping: #{ids.inspect}")

      result = RedmineRepoTools.refresh_repository_changesets(ids[:project_id], ids[:repository_id])
      info("refreshed repository: #{repo_name} project_id=#{result[:project_id]} repository_id=#{result[:repository_id]} changesets_count=#{result[:changesets_count]}")
      debug("refresh result: #{result.inspect}")
    rescue StandardError => e
      @had_error = true
      error("failed repository #{repo_name}: #{e.class}: #{e.message}")
      debug("backtrace for #{repo_name}: #{Array(e.backtrace).join(' | ')}")
      GitTriggers::FailureNotifier.notify(
        repo_name: repo_name,
        repo_path: repo_path,
        error_message: e.message,
        error_class: e.class,
        logger: method(:log_notifier)
      )
    end

    def info(message)
      return if @verbose_level.zero?

      warn("git-triggers-runner INFO: #{message}")
    end

    def debug(message)
      return if @verbose_level < 2

      warn("git-triggers-runner DEBUG: #{message}")
    end

    def error(message)
      warn("git-triggers-runner ERROR: #{message}")
    end

    def log_notifier(level, message)
      case level
      when :debug
        debug(message)
      else
        error(message)
      end
    end
  end
end

exit GitTriggers::BatchRunner.new(ARGV).run
