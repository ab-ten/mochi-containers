# frozen_string_literal: true

module RedmineRepoTools
  module_function

  def normalize_repo_path(path)
    raise ArgumentError, "path is blank" if path.nil? || path.to_s.strip.empty?

    expanded = File.expand_path(path.to_s.strip)

    begin
      real = File.realpath(expanded)
    rescue StandardError
      real = expanded
    end

    real.sub(%r{/+\z}, "")
  end

  def repository_paths(repository)
    candidates = []

    if repository.url.present?
      begin
        candidates << normalize_repo_path(repository.url)
      rescue StandardError
      end
    end

    candidates.compact.uniq
  end

  def repository_match_details(matches, target)
    details = matches.map do |repo|
      "repository_id=#{repo.id}, project_id=#{repo.project_id}, url=#{repo.url.inspect}"
    end.join(" | ")

    "multiple repositories matched path #{target}: #{details}"
  end

  def find_project_and_repository_ids_by_git_full_path(git_full_path)
    target = normalize_repo_path(git_full_path)
    exact_matches = Repository.includes(:project).where(url: target).to_a

    if exact_matches.size > 1
      raise RuntimeError, repository_match_details(exact_matches, target)
    end

    repo = exact_matches.first

    if repo.nil?
      matches = Repository.includes(:project).where.not(url: [nil, ""]).select do |candidate|
        repository_paths(candidate).include?(target)
      end

      if matches.empty?
        raise ActiveRecord::RecordNotFound, "repository not found for path: #{target}"
      end

      if matches.size > 1
        raise RuntimeError, repository_match_details(matches, target)
      end

      repo = matches.first
    end

    {
      project_id: repo.project_id,
      repository_id: repo.id,
      project_identifier: repo.project&.identifier,
      repository_identifier: repo.identifier,
      repository_url: repo.url
    }
  end

  def refresh_repository_changesets(project_id, repository_id)
    project = Project.find(project_id)
    repository = Repository.find(repository_id)

    if repository.project_id != project.id
      raise RuntimeError, "repository_id=#{repository.id} does not belong to project_id=#{project.id}"
    end

    raise RuntimeError, "project_id=#{project.id} is not active" unless project.active?

    repository.fetch_changesets

    {
      project_id: project.id,
      repository_id: repository.id,
      fetched: true,
      changesets_count: repository.changesets.count
    }
  rescue Redmine::Scm::Adapters::CommandFailed => e
    raise RuntimeError, "failed to fetch changesets for repository_id=#{repository_id}: #{e.message}"
  end
end
