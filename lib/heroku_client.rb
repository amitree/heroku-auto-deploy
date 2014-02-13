require 'heroku-api'

class HerokuClient
  class Error < StandardError
  end

  def initialize(api_key, staging_app_name, production_app_name)
    @heroku = Heroku::API.new(:api_key => api_key)
    @staging_app_name = staging_app_name
    @production_app_name = production_app_name
  end

  def current_production_release
    get_releases(@production_app_name)[-1]
  end

  def staging_release_name(production_release)
    unless production_release['descr'] =~ /Promote #{@staging_app_name} (v\d+) /
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

private
  def get_releases(app_name)
    @heroku.get_releases(app_name).body
  end
end
