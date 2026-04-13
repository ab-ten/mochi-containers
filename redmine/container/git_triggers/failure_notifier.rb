# frozen_string_literal: true

module GitTriggers
  module FailureNotifier
    module_function

    def notify(repo_name:, repo_path:, error_message:, error_class:, logger: nil)
      failure_hook = ENV.fetch("GIT_TRIGGERS_FAILURE_HOOK", "").strip
      if failure_hook.empty?
        logger&.call(:debug, "failure hook skipped for #{repo_name}: GIT_TRIGGERS_FAILURE_HOOK is empty")
        return true
      end

      env = {
        "GIT_TRIGGERS_REPO_NAME" => repo_name,
        "GIT_TRIGGERS_REPO_PATH" => repo_path,
        "GIT_TRIGGERS_ERROR_MESSAGE" => error_message.to_s,
        "GIT_TRIGGERS_ERROR_CLASS" => error_class.to_s
      }

      return true if system(env, failure_hook, repo_name, error_message.to_s)

      logger&.call(:error, "failure hook failed for #{repo_name}: #{failure_hook}")
      false
    rescue StandardError => e
      logger&.call(:error, "failure hook raised for #{repo_name}: #{e.class}: #{e.message}")
      false
    end
  end
end
