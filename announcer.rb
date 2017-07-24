require 'json'
require 'net/http'
require 'pry-byebug' # TODO: remove

PVTA_API_URL = 'http://bustracker.pvta.com/InfoPoint/rest'
ROUTES_CACHE_FILE = 'cached_routes.json'
STOPS_CACHE_FILE = 'cached_stops.json'
CACHE_FILE = 'cached_departures.json'

get_routes_cache unless File.file? ROUTES_CACHE_FILE
get_stops_cache unless File.file? STOPS_CACHE_FILE
define_routes_cache
define_stops_cache
define_interval
define_stop_ids
announcements = departures_crossed_interval(new_departures, cached_departures)
make_announcements(announcements)
