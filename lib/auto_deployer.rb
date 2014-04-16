require 'secrets'
require 'git'
require 'heroku_client'
require 'pivotal-tracker'
require 'haml'
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
      notify_team old_release, release
    end
  rescue => e
    send_message :error_notification, 'Exception caught during production deployment', exception: e
    raise e
  end

  def get_tracker_status(story_id)
    tracker_data(story_id).current_state
  end

  def tracker_data(story_id)
    @tracker_cache[story_id] ||= PivotalTracker::Project.find(TRACKER_PROJECT_ID).stories.find(story_id)
  end

  def notify_team(old_release, new_release)
    git_commits = @git.commits_between(old_release['commit'], new_release['commit'])
    story_ids = @git.stories_worked_on_between(old_release['commit'], new_release['commit'])
    send_message(:push_to_prod, 'New code deployed to production', git_commits: git_commits, story_ids: story_ids)
  end

  def send_message(template, subject, locals={})
    send_mail @options[:notify_email], subject, Haml::Engine.new(File.read("views/#{template}.haml"), escape_html: true, escape_attrs: true).render(self, locals)
  end

  def send_mail(to_address, subject, message)
    return unless to_address
    puts "Sending email to '#{to_address}' with subject '#{subject}'"
    mail = Mail.new do
      to to_address
      from NOTIFY_EMAIL_FROM
      subject subject
      html_part do
        content_type 'text/html'
        body message
      end
    end

    mail.delivery_method :sendmail
    mail.deliver
  end
end
