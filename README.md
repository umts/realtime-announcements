# realtime-announcements
Automated announcements based on PVTA's realtime bus departure feed.

This is a Ruby script powered by a cron job which scans for departures leaving one or more stops within 5 minutes, and announces those departures.

Things I should come back to write about here:

+ Config file contains one file, schedule.rb (whenever expects this file to be in config/ as opposed to the project directory). The cron job contained in this file runs from 5:00am until 2:59am the next day. There's no need for it to run between 3:00am-4:59am since no buses operate during those hours.

+ WAV file structure:
  + headsigns/ contains the destination headsigns (e.g. "Bus Garage via Computer Science")
  + fragments/ contains sentence fragments to join routes, destinations, and stops into an announcement sentence (e.g. towards, via, will be leaving, in, minutes)
  + routes/ contains route names in the format "route [number]"
  + stops/ contains audio files with the names of stops where the announcements can be played.

+ Dependencies: If bundling fails to install `ruby-audio -v '1.6.1'`, you may be missing libsndfile. Run `brew install libsndfile --universal` to install it if this is the case. (Note: sometimes `ruby-audio -v '1.6.1'` fails to install upon bundling even if libsndfile is present. Run `brew uninstall libsndfile` and then `brew install libsndfile --universal` in this case.) Then run `sudo gem install ruby-audio` and bundle.
In the event you receive the error "Could not open library 'portaudio'", run `locate libc.dylib` to conform that the database doesn't exist. In that case, you are missing ffi-portaudio. Run `brew install portaudio portmidi`. (Note: You should not have to worry about installing the corresponding gem, as it is already in the Gemfile.lock)
Now you can run `ruby announcer.rb --test` to her the test audio.
