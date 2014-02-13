heroku-auto-deploy
==================

Automatically deploy code from staging to production on Heroku when stories are
accepted in Pivotal Tracker.

Usage
-----

1. `git clone https://github.com/amitree/heroku-auto-deploy.git`
1. Copy `lib/secrets.rb.template` to `lib/secrets.rb` and fill in the necessary information.
1. On Mac OS X, run `./install.sh`.  This will set up a launchd process that runs every 15 minutes, with output being logged to `/var/log/deploy_to_heroku.log`.
