require 'secrets'
require 'git'
require 'heroku_client'
require 'pivotal-tracker'

class AutoDeployer
  def initialize
    @git = Git.new GITHUB_REPO, GITHUB_USERNAME, GITHUB_TOKEN
    @heroku = HerokuClient.new HEROKU_API_KEY, HEROKU_STAGING_APP, HEROKU_PRODUCTION_APP
    PivotalTracker::Client.token = TRACKER_TOKEN
    @tracker_cached_status = {}
  end

  def release_to_deploy
    production_release = @heroku.current_production_release
    staging_releases = @heroku.staging_releases_since(@heroku.staging_release_name(production_release))
    prod_commit = production_release['commit']

    puts "Production release is #{prod_commit}"

    staging_releases.reverse.each do |staging_release|
      staging_commit = staging_release['commit']
      stories = @git.stories_worked_on_between(prod_commit, staging_commit)
      puts "- Trying staging release #{staging_release['name']} with commit #{staging_commit}"
      puts "  - Stories: #{stories.inspect}"
      unaccepted_stories = stories.select { |story| get_tracker_status(story) != 'accepted' }
      if unaccepted_stories.length > 0
        puts "    - Some stories are not yet accepted: #{unaccepted_stories.inspect}"
      else
        puts "    - This release is good to go!"
        return staging_release
      end
    end

    return nil
  end

  def deploy
    release = release_to_deploy
    puts "Deploy #{release['name']} to production"
  end

  def get_tracker_status(story_id)
    @tracker_cached_status[story_id] ||= PivotalTracker::Project.find(TRACKER_PROJECT_ID).stories.find(story_id).current_state
  end
end
