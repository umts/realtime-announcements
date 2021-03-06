# frozen_string_literal: true

require 'spec_helper'

include Announcer

describe Announcer do
  describe 'cache_departures' do
    before :each do
      stub_const 'Announcer::DEPARTURES_CACHE_FILE', :cache_file
    end
    it 'writes its input as JSON to the cache file' do
      input = { key: :value }
      file = double
      expect(File).to receive(:open).with(:cache_file, 'w').and_yield file
      expect(file).to receive(:puts).with input.to_json
      cache_departures(input)
    end
  end

  describe 'cached_departures' do
    before :each do
      stub_const 'Announcer::DEPARTURES_CACHE_FILE', :cache_file
      expect(File).to receive(:file?).with(:cache_file).and_return file_present
    end
    context 'with a cached departures file' do
      let(:file_present) { true }
      it 'returns the file parsed as JSON' do
        expect(File).to receive(:read).with(:cache_file).and_return :file_json
        expect(JSON).to receive(:parse).with(:file_json).and_return :cache
        expect(cached_departures).to eql :cache
      end
    end
    context 'with no cached departures file' do
      let(:file_present) { false }
      it 'returns an empty hash' do
        expect(cached_departures).to eql Hash.new
      end
    end
  end

  # I could make this more exhaustive (9 cases total), but I
  # think the ones I didn't include here are really edge cases.
  describe 'departures_crossed_interval' do
    before :each do
      @interval = 3
      # Expected return value
      @departure = {
        route_id: 'route_id', headsign: 'sign',
        stop_id: :stop_id, interval: new_time
      }
    end
    let :new_departures do
      { stop_id: { %w[route_id sign] => { trip_id: new_time } } }
    end
    # The old departures array is un-stringified in the method.
    let :old_departures do
      { stop_id: { %w[route_id sign].to_s => { trip_id: old_time } } }
    end
    subject { departures_crossed_interval new_departures, old_departures }
    context 'departure was above interval' do
      let(:old_time) { 5 }
      context 'departure remains above interval' do
        let(:new_time) { 4 }
        it { is_expected.not_to include @departure }
      end
      context 'departure is at interval' do
        let(:new_time) { 3 }
      end
      context 'departure is below interval' do
        let(:new_time) { 2 }
        it { is_expected.to include @departure }
      end
    end
    context 'departure was at interval' do
      let(:old_time) { 3 }
      context 'departure is below interval' do
        let(:new_time) { 2 }
        it { is_expected.not_to include @departure }
      end
    end
    context 'departure was below interval' do
      let(:old_time) { 2 }
      context 'departure remains below interval' do
        let(:new_time) { 1 }
        it { is_expected.not_to include @departure }
      end
    end
  end

  describe 'make_announcement' do
    let :announce do
      make_announcement route_id: '20030', headsign: 'North Amherst',
                        stop_id: '72', interval: interval
    end
    # What we expect to be played
    before :each do
      expect_any_instance_of(Announcer).to receive(:play)
        .with route: '20030'
      expect_any_instance_of(Announcer).to receive(:play)
        .with fragment: 'toward'
      expect_any_instance_of(Announcer).to receive(:play)
        .with headsign: 'North Amherst', route_id: '20030'
      expect_any_instance_of(Announcer).to receive(:play)
        .with fragment: 'will be leaving'
      expect_any_instance_of(Announcer).to receive(:play)
        .with stop: '72'
      expect_any_instance_of(Announcer).to receive(:sleep).with 0.5
    end
    let(:interval) { 5 }
    it 'plays the expected files' do
      expect_any_instance_of(Announcer).to receive(:play)
        .with fragment: 'in 5 minutes'
      announce
    end
    context 'interval is 0 or less' do
      let(:interval) { 0 }
      it 'says the bus leaves now' do
        expect_any_instance_of(Announcer).to receive(:play)
          .with fragment: 'now'
        announce
      end
    end
    context 'interval is 1' do
      let(:interval) { 1 }
      it 'says the bus in 1 minute' do
        expect_any_instance_of(Announcer).to receive(:play)
          .with fragment: 'in 1 minute'
        announce
      end
    end
    context 'interval is 2 or more' do
      let(:interval) { 2 }
      it 'says the bus in # minutes' do
        expect_any_instance_of(Announcer).to receive(:play)
          .with fragment: 'in 2 minutes'
        announce
      end
    end
  end

  describe 'new_departures' do
    # I would have route_id and headsign be symbols, but we encode as JSON.
    let :endpoint_response do
      [
        'RouteDirections' => [
          {
            'RouteId' => 'route_id',
            'Departures' => [
                { 'EDT' => edt,
                  'Trip' => {
                  'InternetServiceDesc' => 'headsign',
                  'TripId' => 'trip_id'
                } # trip
              } # first departure
            ] # departures
          } # first route direction
        ] # route directions
      ] # response array
    end
    let(:edt) { "/Date(#{time.to_i}000-0400)/" }
    before :each do 
      # Freeze so that time comparison works correctly.
      # Otherwise, we set Time.now in the test, and then compare to
      # Time.now in the code possibly during the next second.
      Timecop.freeze
      @query_stops = ['stop_id']
      stub_const 'Announcer::PVTA_API_URL', 'http://example.com'
      stub_request(:get, 'http://example.com/stopdepartures/get/stop_id')
        .to_return body: endpoint_response.to_json
    end
    after(:each) { Timecop.return }
    context 'EDT is right now' do
      let(:time) { Time.now }
      it 'returns the correct data structure with the interval at 0' do
        result = new_departures
        # Break it down into clearer atomic tests, so that if something's wrong
        # it's easier to debug precisely what it is.
        expect(result).to be_a Hash
        expect(result.keys).to eql @query_stops

        expect(result['stop_id']).to be_a Hash
        expect(result['stop_id'].keys).to eql [%w(route_id headsign)]

        expect(result['stop_id'][['route_id', 'headsign']]).to be_a Hash
        expect(result['stop_id'][['route_id', 'headsign']].keys)
          .to eql ['trip_id']

        expect(result['stop_id'][['route_id', 'headsign']]['trip_id'])
          .to be 0

        # Wrapping it all up
        expected_result = {
          'stop_id' => {
            ['route_id', 'headsign'] => {
              'trip_id' => 0
            }
          }
        }
        expect(result).to eql expected_result
      end
    end
    context 'EDT is in 5 minutes' do
      let(:time) { Time.now + 5 * 60 }
      it 'returns the correct data structure with the interval at 5' do
        expected_result = {
          'stop_id' => {
            ['route_id', 'headsign'] => {
              'trip_id' => 5
            }
          }
        }
        expect(new_departures).to eql expected_result
      end
    end
  end

  describe 'play' do
    let(:call) { play fruit: 'banana' }
    let(:expected_path) { 'voice/fruits/banana.wav' }
    before :each do
      expect(File).to receive(:file?).with(expected_path)
        .and_return file_present
    end
    context 'file exists at the expected path' do
      let(:file_present) { true }
      it 'plays the file' do
        expect(AudioPlayback).to receive(:play).with(expected_path)
          .and_return double block: true
        call
      end
    end
    context 'file does not exist at the expected path' do
      let(:file_present) { false }
      context 'another specifier is given' do
        let(:call) { play fruit: 'banana', color: 'yellow' }
        let(:new_expected_path) { 'voice/fruits/yellow/banana.wav' }
        before :each do
          expect(File).to receive(:file?).with(new_expected_path)
            .and_return new_file_present
        end
        context 'file exists in the directory matching the specifier value' do
          let(:new_file_present) { true }
          it 'plays the file' do
            expect(AudioPlayback).to receive(:play).with(new_expected_path)
              .and_return double block: true
            call
          end
        end
        context 'file does not exist in that directory' do
          let(:new_file_present) { false }
          it 'says the text' do
            expect_any_instance_of(Announcer).to receive(:say).with 'banana'
            call
          end
        end
      end
      context 'another specifier is not given' do
        it 'says the text' do
          expect_any_instance_of(Announcer).to receive(:say).with 'banana'
          call
        end
      end
    end
  end

  describe 'run' do
    before :each do
      expect_any_instance_of(Announcer).to receive(:set_query_stops)
      expect_any_instance_of(Announcer).to receive(:set_interval)
      expect_any_instance_of(Announcer).to receive(:new_departures)
        .and_return :departures
      expect_any_instance_of(Announcer).to receive(:cached_departures)
        .and_return :cached_departures
      expect_any_instance_of(Announcer)
        .to receive(:departures_crossed_interval)
        .with(:departures, :cached_departures)
        .and_return departures_to_announce
      expect_any_instance_of(Announcer).to receive(:cache_departures)
        .with :departures
    end
    context 'with departures to announce' do
      let(:departures_to_announce) { [:departure_to_announce] }
      it 'makes announcements' do
        expect_any_instance_of(Announcer).to receive(:make_announcement)
          .with(:departure_to_announce)
        run
      end
    end
    context 'with no departures to announce' do
      let(:departures_to_announce){ [] }
      it 'makes no announcements' do
        expect_any_instance_of(Announcer).not_to receive(:make_announcement)
        run
      end
    end
  end

  describe 'set_interval' do
    before :each do
      stub_const 'Announcer::CONFIG_FILE', :config_file
      expect(File).to receive(:file?).with(:config_file)
        .and_return file_present
      @interval = :default_interval
    end
    context 'with no config file' do
      let(:file_present) { false }
      it 'keeps the default interval' do
        set_interval
        expect(@interval).to be :default_interval
      end
    end
    context 'with a config file' do
      let(:file_present) { true }
      it 'parses as JSON and reads the interval key' do
        expect(File).to receive(:read).with(:config_file).and_return :json
        expect(JSON).to receive(:parse).with(:json).and_return 'interval' => 7
        set_interval
        expect(@interval).to be 7
      end
    end
  end

  describe 'say' do
    before :each do
      stub_const 'Announcer::MISSING_TEXT_FILE', :cache_file
      expect(File).to receive(:file?).with(:cache_file).and_return file_present
      expect_any_instance_of(Announcer).to receive(:system)
        .with('say', 'grapes')
    end
    context 'missing text file does not exist' do
      let(:file_present) { false }
      it 'says the message and writes it to the missing text file' do
        file = double
        expect(File).to receive(:open).with(:cache_file, 'w').and_yield file
        expect(file).to receive(:puts).with %w[grapes]
        say 'grapes'
      end
    end
    context 'missing text file exists' do
      let(:file_present) { true }
      before :each do
        expect(File).to receive(:read).with(:cache_file)
          .and_return double lines: message_lines
      end
      context 'message already exists in missing text file' do
        let(:message_lines) { %w[apples bananas grapes] }
        it 'says the message but does not write it to the file' do
          expect(File).not_to receive(:open)
          say 'grapes'
        end
      end
      context 'message does not already exist in missing text file' do
        let(:message_lines) { %w[apples pears] }
        it 'says the message and writes it (sorted) to the missing text file' do
          file = double
          expect(File).to receive(:open).with(:cache_file, 'w').and_yield file
          expect(file).to receive(:puts).with %w[apples grapes pears]
          say 'grapes'
        end
      end
    end
  end

  describe 'set_query_stops' do
    before :each do
      stub_const 'Announcer::QUERY_STOPS_FILE', :stops_file
      expect(File).to receive(:file?).with(:stops_file).and_return file_present
      @query_stops = :default_stops
    end
    context 'with no query stops file' do
      let(:file_present) { false }
      it 'keeps the default query stops' do
        set_query_stops
        expect(@query_stops).to be :default_stops
      end
    end
    context 'with a query stops file' do
      let(:file_present) { true }
      let(:lines) { ['STOP_ID     '] }
      before :each do
        expect(File).to receive(:read).with(:stops_file)
          .and_return double lines: lines
      end
      it 'reads the lines from the file to set the query stops' do
        set_query_stops
        expect(@query_stops).to include 'STOP_ID'
      end
    end
  end
end
