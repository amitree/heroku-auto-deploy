require 'heroku_client'

describe HerokuClient do
  before do
    @client = HerokuClient.new('api_key', 'my-staging-app', 'my-prod-app')
  end

  describe '#staging_release_name' do
    it "should return the name of the staging release if production was promoted from staging" do
      @client.staging_release_name({'descr' => 'Promote my-staging-app v123 deadbeef'}).should eq 'v123'
    end

    it "should raise an error if production was not promoted from staging" do
      expect {
        @client.staging_release_name({'descr' => 'Add newrelic:wayne add-on'})
      }.to raise_error(HerokuClient::Error)
    end
  end

  describe '#staging_releases_since' do
    before do
      expect(@client).to receive(:get_releases).with('my-staging-app').and_return([{'name' => 'v100'}, {'name' => 'v101'}, {'name' => 'v102'}, {'name' => 'v103'}])
    end

    it "should return all releases since the specified release" do
      @client.staging_releases_since('v101').should match_array [{'name' => 'v102'}, {'name' => 'v103'}]
    end

    it "should raise an error if the specified release cannot be found" do
      expect {
        @client.staging_releases_since('v104')
        }.to raise_error(HerokuClient::Error)
    end

    it "should return an empty array if the specified release is the last one" do
      @client.staging_releases_since('v103').should match_array []
    end
  end
end
