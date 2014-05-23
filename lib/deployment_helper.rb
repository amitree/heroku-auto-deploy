class DeploymentHelper
  class ReleaseDetails
    attr_accessor :production_release, :staging_release_to_deploy, :stories
    attr_writer :production_promoted_from_staging

    def initialize
      @stories = []
    end

    def production_promoted_from_staging?
      @production_promoted_from_staging
    end

    class Story < DelegateClass(PivotalTracker::Story)
      attr_accessor :deliverable
      attr_reader :blocked_by

      def initialize(tracker_story)
        super(tracker_story)
        @deliverable = false
        @blocked_by = []
      end

      def blocked_by=(blocked_by)
        @blocked_by = blocked_by
        if @blocked_by.length > 0
          @deliverable = false
        else
          @deliverable = true
        end
      end
    end
  end

  def initialize(options={})
    @heroku = options[:heroku] || Amitree::HerokuClient.new(options[:heroku_api_key], options[:heroku_staging_app], options[:heroku_production_app])
    @git = options[:git] || Amitree::GitClient.new(options[:github_repo], options[:github_username], options[:github_password])
    PivotalTracker::Client.token = options[:tracker_token]
    @tracker_project = PivotalTracker::Project.find(options[:tracker_project_id])
    @tracker_cache = {}
  end

  def compute_release(options={})
    result = ReleaseDetails.new

    result.production_release = @heroku.last_promoted_production_release
    result.production_promoted_from_staging = @heroku.promoted_from_staging?(result.production_release)
    staging_releases = @heroku.staging_releases_since(@heroku.staging_release_name(result.production_release))

    prod_commit = result.production_release['commit']
    puts "Production release is #{prod_commit}" if options[:verbose]

    @git.stories_worked_on_between(prod_commit, 'HEAD').each do |story_id|
      result.stories << ReleaseDetails::Story.new(tracker_data(story_id))
    end

    staging_releases.reverse.each do |staging_release|
      staging_commit = staging_release['commit']
      story_ids = @git.stories_worked_on_between(prod_commit, staging_commit).map(&:to_i)
      stories = result.stories.select{|story| story_ids.include?(story.id)}

      puts "- Trying staging release #{staging_release['name']} with commit #{staging_commit}" if options[:verbose]
      puts "  - Stories: #{story_ids.inspect}" if options[:verbose]

      unaccepted_story_ids = story_ids.select { |story| get_tracker_status(story) != 'accepted' }
      stories.each do |story|
        story.blocked_by = unaccepted_story_ids
      end

      if unaccepted_story_ids.length > 0
        puts "    - Some stories are not yet accepted: #{unaccepted_story_ids.inspect}" if options[:verbose]
      else
        puts "    - This release is good to go!" if options[:verbose]
        result.staging_release_to_deploy = staging_release
        break
      end
    end

    return result
  end

  def get_tracker_status(story_id)
    tracker_data(story_id).current_state
  end

  def tracker_data(story_id)
    @tracker_cache[story_id] ||= @tracker_project.stories.find(story_id)
  end
end
