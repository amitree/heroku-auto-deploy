require 'heroku-api'
require 'heroku/new_api'
require 'rendezvous'

class HerokuClient
  class Error < StandardError
  end

  def initialize(api_key, staging_app_name, production_app_name)
    @heroku = Heroku::API.new(:api_key => api_key)
    # We need to use the new API (not currently supported by the heroku-api gem) for deploy_to_production
    @heroku_new = Heroku::NewAPI.new(:api_key => api_key)
    @staging_app_name = staging_app_name
    @production_app_name = production_app_name
  end

  def current_production_release
    get_releases(@production_app_name)[-1]
  end

  def staging_release_name(production_release)
    unless production_release['descr'] =~ /Promote #{@staging_app_name} (v\d+)/
      raise Error.new "Production release was not promoted from staging: #{production_release['descr']}"
    end
    $1
  end

  def staging_releases_since(staging_release_name)
    staging_releases = get_releases(@staging_app_name)
    index = staging_releases.index { |release| release['name'] == staging_release_name }
    if index.nil?
      raise Error.new "Could not find staging release #{staging_release_name}"
    end
    staging_releases.slice(index+1, staging_releases.length)
  end

  def deploy_to_production(staging_release_name, options={})
    slug = staging_slug(staging_release_name)
    puts "Deploying slug to production: #{slug}"
    unless options[:dry_run]
      @heroku_new.post_release(@production_app_name, {'slug' => slug, 'description' => "Promote #{@staging_app_name} #{staging_release_name}"})
      db_migrate_on_production
    end
  end

  def staging_slug(staging_release_name)
    unless staging_release_name =~ /\Av(\d+)\z/
      raise Error.new "Unexpected release name: #{staging_release_name}"
    end
    result = @heroku_new.get_release(@staging_app_name, $1)
    result.body['slug']['id'] || raise(Error.new("Could not find slug in API response: #{result.inspect}"))
  end

  def db_migrate_on_production
    heroku_run(@production_app_name, 'rake db:migrate')
  end

private
  def get_releases(app_name)
    @heroku.get_releases(app_name).body
  end

  def heroku_run(app_name, command)
    puts "Running command on #{app_name}: #{command}..."
    data = @heroku.post_ps(app_name, command, { attach: true }).body
    read, write = IO.pipe
    Rendezvous.start(url: data['rendezvous_url'], input: read)
    read.close
    write.close
    puts "Done."
  end
end
