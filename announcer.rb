require 'json'
require 'net/http'
require 'optparse'
require 'pry-byebug' # TODO: remove

PVTA_API_URL = 'http://bustracker.pvta.com/InfoPoint/rest'
CONFIG_FILE = 'config.json'
QUERY_STOPS_FILE = 'stops.txt'

ROUTES_CACHE_FILE = 'cached_routes.json'
STOPS_CACHE_FILE = 'cached_stops.json'
DEPARTURES_CACHE_FILE = 'cached_departures.json'

@route_names = {}
@stop_names = {}
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

def define_route_names
  @route_names = JSON.parse File.read(ROUTES_CACHE_FILE)
end

def define_stop_names
  @stop_names = JSON.parse File.read(STOPS_CACHE_FILE)
end

def departures_crossed_interval(new_departures, old_departures)
  departures = []
  old_departures.each_pair do |stop_name, route_directions|
    route_directions.each_pair do |route_dir_data, trips|
      route_name, headsign = route_dir_data.match(/\A\["(.*)", "(.*)"\]\z/).captures
      trips.each_pair do |trip_id, old_interval|
        stop_departures = new_departures[stop_name]
        route_dir_departures = stop_departures[[route_name, headsign]] if stop_departures
        new_interval = new_departures[stop_name][[route_name, headsign]][trip_id] if route_dir_departures
        if new_interval && old_interval > @interval && new_interval <= @interval
          departures << { route_name: route_name, headsign: headsign,
                          stop_name: stop_name, interval: interval }
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

def make_announcements(departures)
  departures.each do |departure|
    system 'say', <<~MESSAGE
      Route #{departure.fetch :route_name}
      departing for #{departure.fetch :headsign}
      will be leaving from #{departure.fetch :stop_name}
      in #{departure.fetch :interval} minutes.
    MESSAGE
  end
end

def new_departures
  departures = {}
  @query_stops.each do |stop_id|
    stop_name = @stop_names[stop_id]
    departures[stop_name] = {}
    departure_uri = URI("#{PVTA_API_URL}/stopdepartures/get/#{stop_id}")
    departure_data = JSON.parse Net::HTTP.get(departure_uri)
    route_directions = departure_data.first.fetch 'RouteDirections'
    route_directions.each do |route_dir|
      route_id = route_dir.fetch('RouteId').to_s
      route_name = @route_names[route_id]
      route_dir_data = route_dir.fetch 'Departures'
      route_dir_data.each do |departure|
        trip = departure.fetch 'Trip'
        trip_id = trip.fetch('TripId').to_s
        headsign = trip.fetch 'InternetServiceDesc'
        timestamp = departure.fetch 'EDT'
        match_data = timestamp.match %r{/Date\((\d+)000-0[45]00\)/}
        timestamp = match_data.captures.first.to_i
        edt = Time.at(timestamp)
        interval_seconds = edt - Time.now
        interval = interval_seconds.floor / 60
        departures[stop_name][[route_name, headsign]] ||= {}
        departures[stop_name][[route_name, headsign]][trip_id] = interval
      end
    end
  end
  departures
end

options = {}

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby announcer.rb [options]'
  opts.on '-t', '--test', 'Test the announcement functionality without querying the API' do
    options[:test] = true
  end
end.parse!

if options[:test]
  make_announcements([
    { route_name: '30', headsign: 'Old Belchertown Road', stop_name: 'Fine Arts Center', interval: '5' },
    { route_name: 'B43', headsign: 'Northampton Center', stop_name: 'Haigis Mall', interval: '4' }
  ])
else
  get_routes_cache unless File.file? ROUTES_CACHE_FILE
  get_stops_cache unless File.file? STOPS_CACHE_FILE
  define_route_names
  define_stop_names
  define_query_stops
  define_interval
  departures = new_departures
  announcements = departures_crossed_interval(departures, cached_departures)
  make_announcements(announcements) if announcements.length > 0
  cache_departures(departures)
end
