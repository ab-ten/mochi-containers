#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

module GitTriggers
  class Worker
    LOCK_FILE = "/var/git_lock/git-triggers-worker.lock"
    PENDING_DIR = "/var/git_triggers/pending"
    PROCESSING_DIR = "/var/git_triggers/processing"
    RUN_BATCH_SCRIPT = "/usr/local/lib/git_triggers/run_batch.rb"
    RAILS_ROOT = "/usr/src/redmine"
    PAUSE_SECONDS = 30

    def initialize(argv)
      @argv = argv
      @verbose_level = 0
      @pause_only = false
    end

    def run
      parse_options!
      validate_directories!

      File.open(LOCK_FILE, File::RDWR | File::CREAT, 0o600) do |lock_io|
        unless lock_io.flock(File::LOCK_EX | File::LOCK_NB)
          error("another worker is already running: #{LOCK_FILE}")
          return 1
        end

        info("acquired lock: #{LOCK_FILE}")

        if @pause_only
          info("pause mode enabled; sleeping #{PAUSE_SECONDS} seconds")
          sleep(PAUSE_SECONDS)
          return 0
        end

        claimed = claim_pending_entries
        if claimed.empty?
          debug("no pending repositories found")
          return 0
        end

        repo_names = claimed.map { |entry| entry[:repo_name] }.uniq
        info("starting batch refresh for #{repo_names.size} repositories: #{repo_names.join(', ')}")

        runner_ok = run_batch(repo_names)
        cleanup_ok = cleanup_processing_entries(claimed)

        runner_ok && cleanup_ok ? 0 : 1
      end
    rescue StandardError => e
      error("#{e.class}: #{e.message}")
      1
    end

    private

    def parse_options!
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: worker.rb [-v|-vv|-p]"

        opts.on("-v", "Show progress logs") do
          @verbose_level += 1
        end

        opts.on("-p", "Acquire lock, sleep 30 seconds, and exit") do
          @pause_only = true
        end
      end

      parser.parse!(@argv)
    rescue OptionParser::ParseError => e
      error(e.message)
      error(parser.to_s)
      raise SystemExit, 1
    end

    def validate_directories!
      [PENDING_DIR, PROCESSING_DIR, RAILS_ROOT].each do |path|
        next if Dir.exist?(path)

        raise "required directory is missing: #{path}"
      end
    end

    def claim_pending_entries
      claimed = []

      pending_entries.each do |entry_name|
        repo_name = entry_name
        pending_path = File.join(PENDING_DIR, entry_name)
        processing_path = File.join(PROCESSING_DIR, entry_name)

        begin
          File.rename(pending_path, processing_path)
          info("claimed queue: #{repo_name}")
          claimed << { repo_name: repo_name, processing_path: processing_path }
        rescue Errno::ENOENT
          debug("skip missing pending entry: #{pending_path}")
        rescue SystemCallError => e
          error("failed to move queue #{repo_name} to processing: #{e.class}: #{e.message}")
        end
      end

      claimed
    end

    def pending_entries
      entries = Dir.children(PENDING_DIR).sort.select do |entry_name|
        path = File.join(PENDING_DIR, entry_name)
        keep = File.file?(path)
        debug("inspect pending entry: #{path} keep=#{keep}")
        keep
      end

      debug("pending entries: #{entries.join(', ')}") unless entries.empty?
      entries
    end

    def run_batch(repo_names)
      env = {
        "RAILS_ENV" => ENV.fetch("RAILS_ENV", "production"),
        "GIT_TRIGGERS_VERBOSE_LEVEL" => @verbose_level.to_s
      }

      command = ["bin/rails", "runner", "-e", env["RAILS_ENV"], RUN_BATCH_SCRIPT, *repo_names]
      info("running batch command: #{command.join(' ')}")

      return true if system(env, *command, chdir: RAILS_ROOT)

      error("batch command failed with status #{$?.exitstatus}") if $?
      false
    end

    def cleanup_processing_entries(claimed)
      ok = true

      claimed.each do |entry|
        path = entry[:processing_path]
        next unless File.exist?(path)

        File.delete(path)
        info("removed processed queue: #{entry[:repo_name]}")
      rescue SystemCallError => e
        ok = false
        error("failed to delete processing queue #{path}: #{e.class}: #{e.message}")
      end

      ok
    end

    def info(message)
      return if @verbose_level.zero?

      log("INFO", message)
    end

    def debug(message)
      return if @verbose_level < 2

      log("DEBUG", message)
    end

    def error(message)
      log("ERROR", message)
    end

    def log(level, message)
      warn("git-triggers-worker #{level}: #{message}")
    end
  end
end

exit GitTriggers::Worker.new(ARGV).run
