require 'multi_json'

module Heroku
  class NewAPI < API
    def initialize(options={})
      options[:headers] ||= {}
      options[:headers]['Accept'] = 'application/vnd.heroku+json; version=3'
      super(options)
    end

    # POST /apps/:app/releases/:release
    def post_release(app, query={})
      request(
        :expects  => 201,
        :method   => :post,
        :path     => "/apps/#{app}/releases",
        :body     => MultiJson.dump(query)
      )
    end
  end
end
