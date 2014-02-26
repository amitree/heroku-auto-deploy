require 'secrets'
require 'git'
require 'heroku_client'
require 'pivotal-tracker'
require 'cgi'
require 'mail'

class AutoDeployer
  def initialize(options={})
    @git = Git.new GITHUB_REPO, GITHUB_USERNAME, GITHUB_TOKEN
    @heroku = HerokuClient.new HEROKU_API_KEY, HEROKU_STAGING_APP, HEROKU_PRODUCTION_APP
    PivotalTracker::Client.token = TRACKER_TOKEN
    @tracker_cache = {}
    @options = options
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
    old_release = @heroku.current_production_release
    release = release_to_deploy
    if release.nil?
      puts "No new release to deploy"
    else
      puts "Deploy #{release['name']} to production"
      @heroku.deploy_to_production(release['name'], @options)
      notify_team(@options[:notify_email], old_release, release) if @options[:notify_email]
    end
  end

  def get_tracker_status(story_id)
    tracker_data(story_id).current_state
  end

  def tracker_data(story_id)
    @tracker_cache[story_id] ||= PivotalTracker::Project.find(TRACKER_PROJECT_ID).stories.find(story_id)
  end

  def notify_team(email, old_release, new_release)
    git_commits = @git.commits_between(old_release['commit'], new_release['commit'])
    story_ids = @git.stories_worked_on_between(old_release, new_release)

    message = "<h2>Pushing new code to production</h2>"
    message += "<h3>Git commit log</h3>"
    message += "<ul>"
    git_commits.each do |commit|
      message += %(<li><a href="#{@git.link_to commit.sha}">#{CGI.escapeHTML commit.commit.message}</a></li>)
    end
    message += "</ul>"

    message += "<h3>Stories delivered</h3>"
    message += "<ul>"
    story_ids.each do |story_id|
      story = tracker_data(story_id)
      message += %(<li><a href="#{story.url}">##{story_id} #{CGI.escapeHTML story.name}</a></li>)
    end
    message += "</ul>"

    send_mail(email, message)
  end

  def send_mail(to_address, message)
    mail = Mail.new do
      to to_address
      from NOTIFY_EMAIL_FROM
      subject 'New code deployed to production'
      html_part do
        content_type 'text/html'
        body message
      end
    end

    mail.delivery_method :sendmail
    mail.deliver
  end
end
