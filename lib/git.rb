require 'octokit'

class Git
  def initialize(repository, username, password)
    @repository = repository
    @client = Octokit::Client.new login: username, password: password
  end

  def commit_messages_between(rev1, rev2)
    result = @client.compare @repository, rev1, rev2
    result.commits.map(&:commit).map(&:message)
  end

  def stories_worked_on_between(rev1, rev2)
    messages = commit_messages_between(rev1, rev2)
    messages.map{|msg| msg.scan /(?<=#)\d+/}.flatten.uniq
  end
end
