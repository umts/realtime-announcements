require 'audio-playback'
require 'json'
require 'net/http'
require 'optparse'

PVTA_API_URL = 'http://bustracker.pvta.com/InfoPoint/rest'
CONFIG_FILE = 'config.json'
MISSING_TEXT_FILE = 'missing_text.log'
QUERY_STOPS_FILE = 'stops.txt'

DEPARTURES_CACHE_FILE = 'cached_departures.json'

@interval = 5
@query_stops = %w[71 72 73]

def cache_departures(departures)
  File.open DEPARTURES_CACHE_FILE, 'w' do |file|
    file.puts departures.to_json
  end
end

def cached_departures
  if File.file? DEPARTURES_CACHE_FILE
    JSON.parse File.read(DEPARTURES_CACHE_FILE)
  else {}
  end
end

def define_interval
  if File.file? CONFIG_FILE
    config = JSON.parse File.read(CONFIG_FILE)
    if config.key? 'interval'
      @interval = config.fetch('interval')
    end
  end
end

def define_query_stops
  if File.file? QUERY_STOPS_FILE
    @query_stops = File.read(QUERY_STOPS_FILE).lines.map(&:strip)
  end
end

def departures_crossed_interval(new_departures, old_departures)
  departures = []
  old_departures.each_pair do |stop_id, route_directions|
    route_directions.each_pair do |route_dir_data, trips|
      route_id, headsign = route_dir_data.match(/\A\["(.*)", "(.*)"\]\z/).captures
      trips.each_pair do |trip_id, old_interval|
        stop_departures = new_departures[stop_id]
        route_dir_departures = stop_departures[[route_id, headsign]] if stop_departures
        new_interval = new_departures[stop_id][[route_id, headsign]][trip_id] if route_dir_departures
        if new_interval && old_interval > @interval && new_interval <= @interval
          departures << { route_id: route_id, headsign: headsign,
                          stop_id: stop_id, interval: new_interval }
        end
      end
    end
  end
  departures
end

def get_routes_cache
  routes = {}
  routes_uri = URI("#{PVTA_API_URL}/Routes/GetVisibleRoutes")
  route_data = JSON.parse(Net::HTTP.get(routes_uri))
  route_data.each do |route|
    id = route.fetch('RouteId')
    name = route.fetch('RouteAbbreviation')
    routes[id] = name
  end
  File.open ROUTES_CACHE_FILE, 'w' do |file|
    file.puts routes.to_json
  end
end

def get_stops_cache
  stops = {}
  stops_uri = URI("#{PVTA_API_URL}/Stops/GetAllStops")
  stop_data = JSON.parse(Net::HTTP.get(stops_uri))
  stop_data.each do |stop|
    id = stop.fetch('StopId')
    name = stop.fetch('Description')
    stops[id] = name
  end
  File.open STOPS_CACHE_FILE, 'w' do |file|
    file.puts stops.to_json
  end
end

def make_announcement(route_id:, headsign:, stop_id:, interval:)
  play route:    route_id
  play fragment: 'towards'
  play headsign: headsign, route_id: route_id
  play fragment: 'leaving'
  play stop:     stop_id
  play number:   interval
  sleep 0.5
end

def new_departures
  departures = {}
  @query_stops.each do |stop_id|
    departures[stop_id] = {}
    departure_uri = URI("#{PVTA_API_URL}/stopdepartures/get/#{stop_id}")
    departure_data = JSON.parse Net::HTTP.get(departure_uri)
    route_directions = departure_data.first.fetch 'RouteDirections'
    route_directions.each do |route_dir|
      route_id = route_dir.fetch('RouteId').to_s
      route_dir_data = route_dir.fetch 'Departures'
      route_dir_data.each do |departure|
        trip = departure.fetch 'Trip'
        headsign = trip.fetch 'InternetServiceDesc'
        trip_id = trip.fetch('TripId').to_s
        timestamp = departure.fetch 'EDT'
        match_data = timestamp.match %r{/Date\((\d+)000-0[45]00\)/}
        timestamp = match_data.captures.first.to_i
        edt = Time.at(timestamp)
        interval_seconds = edt - Time.now
        interval = interval_seconds.floor / 60
        departures[stop_id][[route_id, headsign]] ||= {}
        departures[stop_id][[route_id, headsign]][trip_id] = interval
      end
    end
  end
  departures
end

def play(file_data, specifiers = {})
  dir, name = file_data.to_a.first
  file_path = "voice/#{dir}s/#{name}.wav"
  if File.file? file_path
    AudioPlayback.play(file_path).block
  else
    if file_data.to_a[1]
      _, route_id = file_data.to_a[1]
      file_path = "voice/#{dir}s/#{route_id}/#{name.tr '/', '-'}.wav"
      if File.file? file_path
        AudioPlayback.play(file_path).block
      else say(name)
      end
    else say(name)
    end
  end
end

def say(text)
  system 'say', text
  File.open MISSING_TEXT_FILE, 'a' do |file|
    file.puts text
  end
end

options = {}

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby announcer.rb [options]'
  opts.on '-t', '--test', 'Test the announcement functionality without querying the API' do
    options[:test] = true
  end
end.parse!

if options[:test]
  make_announcement route_id: '20033', headsign: 'Big Y / Stop and Shop',
                    stop_id: '71', interval: '5'
else
  define_query_stops
  define_interval
  departures = new_departures
  announcements = departures_crossed_interval(departures, cached_departures)
  announcements.each(&method(:make_announcement)) if announcements.length > 0
  cache_departures(departures)
end
