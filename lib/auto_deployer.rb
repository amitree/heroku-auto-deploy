require 'secrets'
require 'amitree/git_client'
require 'amitree/heroku_client'
require 'amitree/heroku_deployer'
require 'haml'
require 'mail'

class AutoDeployer
  RETRY_STATE_FILE = '/tmp/auto_deployer_retries.yml'

  def initialize(options={})
    @options = options

    @git = Amitree::GitClient.new GITHUB_REPO, GITHUB_USERNAME, GITHUB_TOKEN
    @heroku = Amitree::HerokuClient.new HEROKU_API_KEY, HEROKU_STAGING_APP, HEROKU_PRODUCTION_APP
    @deploy_helper = Amitree::HerokuDeployer.new(git: @git, heroku: @heroku, tracker_project_id: TRACKER_PROJECT_ID, tracker_token: TRACKER_TOKEN)
  end

  def release_to_deploy
    release_details = @deploy_helper.compute_release(verbose: true)
    unless release_details.production_promoted_from_staging?
      raise Error.new "Production release was not promoted from staging: #{release_details.production_release['descr']}"
    end

    return release_details.staging_release_to_deploy
  end

  def deploy
    old_release, release = with_error_handling('Exception caught while trying to determine release to deploy', retries: 3) do
      [@heroku.current_production_release, release_to_deploy]
    end

    if release.nil?
      puts "No new release to deploy"
    else
      with_error_handling('Exception caught during production deployment') do
        puts "Deploy #{release['name']} to production"
        @heroku.deploy_to_production(release['name'], @options)
        notify_team old_release, release
      end
    end
  end

  def with_error_handling(message, options={})
    yield
  rescue => e
    if options[:retries] && retry_attempts < options[:retries]
      puts "Exception encountered, will retry before sending alert"
      set_retry_attempts(retry_attempts + 1)
    else
      set_retry_attempts(0) if options[:retries]
      send_message :error_notification, message, exception: e
    end
    raise e
  end

  def retry_attempts
    YAML.load_file(RETRY_STATE_FILE)[:attempts]
  rescue => e
    0
  end

  def set_retry_attempts(attempts)
    with_error_handling('Failed to update retry attempt count') do
      File.open(RETRY_STATE_FILE, 'w') do |out|
        YAML.dump({attempts: attempts}, out)
      end
    end
  end

  def notify_team(old_release, new_release)
    git_commits = @git.commits_between(old_release['commit'], new_release['commit'])
    story_ids = @deploy_helper.stories_worked_on_between(old_release['commit'], new_release['commit']).map(&:id)
    send_message(:push_to_prod, 'New code deployed to production', git_commits: git_commits, story_ids: story_ids)
  end

  def send_message(template, subject, locals={})
    send_mail email_address_for(template), subject, Haml::Engine.new(File.read("views/#{template}.haml"), escape_html: true, escape_attrs: true).render(self, locals)
  end

  def email_address_for(template)
    case template
    when :error_notification
      @options[:errors_email] || @options[:notify_email]
    else
      @options[:notify_email]
    end
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
