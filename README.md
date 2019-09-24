# realtime-announcements
Automated announcements based on PVTA's realtime bus departure feed.

This is a Ruby script powered by a cron job which scans for departures leaving one or more stops within 5 minutes, and announces those departures.

Things I should come back to write about here:

+ Config file structure and what the defaults are
+ WAV file structure and what should be in each kind of file
+ How it all even works, maybe

## Installing on Ubuntu

### Install git
1. Open a Terminal window. It will stay open throughout these steps.
1. Run `sudo apt install git`. Enter your password and confirm as necessary.


### Clone GitHub repository
1. Find the Git HTTPS URL from this GitHub page. At the time of writing it is `https://github.com/umts/realtime-announcements.git`.
1. Run `git clone <URL HERE>`. This will create a `realtime-announcements` directory in the home directory.
1. Run `cd realtime-announcements` to move to the newly-created directory.

### Install Ruby
1. Run `sudo apt install ruby-build`. Enter your password and confirm as necessary.
1. Run `rbenv install` to install the version of Ruby that is specified in the `.ruby-version` file that was pulled down with the repository.
1. Run `echo 'eval "$(rbenv init -)"' >> ~/.bashrc` to add rbenv shims to your terminal setup.
1. Run `source ~/.bashrc` to execute the terminal setup.

### Bundle gems
1. Run `gem install bundler`.
1. Run `rbenv rehash` to shim the `bundle` executable to the project Ruby version.
1. Run `bundle install --without development`.

### Set up configuration values
There are four configuration files which end in `.example` within the repository when cloned from GitHub. These files must be copied to versions not ending in `.example` and configured according to the requirements of the specific installation. For instance `stop_ids.txt.example` should be copied to `stop_ids.txt` before configuring.
1. Create a `stop_ids.txt` containing new-line separated stop IDs for which announcements should be spoken. For instance you can run `echo <STOP NUMBER> >> stop_ids.txt` for each stop to add it to the file.
1. Create a `speech_command.txt` file containing the command which the announcer should use to do the text-to-speech conversion. At the time of writing, `espeak` is recommended and must be installed with `sudo apt install espeak`. For instance you can run `echo espeak > speech_command.txt` to set the configuration value.
1. Create a `config.json` file in which the value for the `interval` key should be set to how the threshold in minutes within which departures will be announced. For example, with a value of `5`, only departures estimated within the next 5 minutes will be announced. To simply configure the default value, run `cp config.json.example config.json`.
1. Create an `audio_command.txt` file contaiing the command which the announcer should use to play .wav files. At the time of writing `play` is recommended and must be installed with `sudo apt install sox`. For instance you can run `echo play > audio_command.txt`.

### Test announcements
1. Run `bundle exec rake announcer:announce_all` to test that announcements work properly.

### Set up scheduled jobs
1. Run `bundle exec whenever -w` which will set the cron jobs necessary to run announcements every minute.
