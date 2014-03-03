#!/bin/bash -e

function cleanup()
{
	rm -f bin/deploy_to_heroku.tmp
}

trap cleanup EXIT

dir=$(cd $(dirname "$0"); pwd)
sudo touch /var/log/deploy_to_heroku.log
sudo chmod 0666 /var/log/deploy_to_heroku.log
sudo mkdir -p /usr/local/bin
sudo sed -e "s,__DIR__,${dir},g" <bin/deploy_to_heroku_wrapper >bin/deploy_to_heroku.tmp
chmod 0755 bin/deploy_to_heroku.tmp
sudo cp bin/deploy_to_heroku.tmp /usr/local/bin/deploy_to_heroku
sudo chmod 0755 /usr/local/bin/deploy_to_heroku

sudo cp launchd/com.amitree.herokuAutoDeploy.plist /Library/LaunchDaemons
sudo launchctl unload -w /Library/LaunchDaemons/com.amitree.herokuAutoDeploy.plist || true
sudo launchctl load -w /Library/LaunchDaemons/com.amitree.herokuAutoDeploy.plist
echo "Installed."
