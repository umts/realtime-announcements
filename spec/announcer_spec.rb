# frozen_string_literal: true

require_relative '../announcer'

RSpec.describe Announcer do
  subject(:announcer) { Class.new { extend Announcer } }

  let!(:default_missing_file) { Announcer::MISSING_TEXT_FILE }
  let!(:default_present_file) { Announcer::PRESENT_TEXT_FILE }

  after do
    FileUtils.rm default_missing_file if File.file? default_missing_file
    FileUtils.rm default_present_file if File.file? default_present_file
  end

  describe 'cache_departures' do
    subject(:call) { announcer.cache_departures(input) }

    before do
      stub_const 'Announcer::DEPARTURES_CACHE_FILE', :cache_file
      allow(File).to receive(:open).with(:cache_file, 'w').and_yield file
      allow(file).to receive(:puts)
    end

    let(:input) { { key: :value } }
    let(:file) { double }

    it 'opens the cache file' do
      call
      expect(File).to have_received(:open).with(:cache_file, 'w')
    end

    it 'writes its input as JSON to the cache file' do
      call
      expect(file).to have_received(:puts).with input.to_json
    end
  end

  describe 'cached_departures' do
    subject(:call) { announcer.cached_departures }

    before do
      stub_const 'Announcer::DEPARTURES_CACHE_FILE', :cache_file
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(:cache_file).and_return file_present
    end

    context 'with a cached departures file' do
      before do
        allow(File).to receive(:read).with(:cache_file).and_return :file_json
        allow(JSON).to receive(:parse).with(:file_json).and_return :cache
      end

      let(:file_present) { true }

      it 'reads the cached departures file' do
        call
        expect(File).to have_received(:read).with(:cache_file)
      end

      it 'returns the file parsed as JSON' do
        expect(call).to eql :cache
      end
    end

    context 'with no cached departures file' do
      let(:file_present) { false }

      it 'returns an empty hash' do
        expect(call).to eq({})
      end
    end
  end

  # I could make this more exhaustive (9 cases total), but I
  # think the ones I didn't include here are really edge cases.
  describe 'departures_crossed_interval' do
    subject :call do
      announcer.departures_crossed_interval(new_departures, old_departures)
    end

    before { announcer.instance_variable_set(:@interval, 3) }

    let :departure do
      { route_id: 'route_id', headsign: 'sign', stop_id: :stop_id, interval: new_time }
    end
    let :new_departures do
      { stop_id: { %w[route_id sign] => { trip_id: new_time } } }
    end
    # The old departures array is un-stringified in the method.
    let :old_departures do
      { stop_id: { %w[route_id sign].to_s => { trip_id: old_time } } }
    end

    context 'when the departure was above interval' do
      let(:old_time) { 5 }

      context 'when the departure remains above interval' do
        let(:new_time) { 4 }

        it { is_expected.not_to include departure }
      end

      context 'when the departure is at interval' do
        let(:new_time) { 3 }
      end

      context 'when the departure is below interval' do
        let(:new_time) { 2 }

        it { is_expected.to include departure }
      end
    end

    context 'when a departure was at interval' do
      let(:old_time) { 3 }

      context 'when the departure is below interval' do
        let(:new_time) { 2 }

        it { is_expected.not_to include departure }
      end
    end

    context 'when a departure was below interval' do
      let(:old_time) { 2 }

      context 'when the departure remains below interval' do
        let(:new_time) { 1 }

        it { is_expected.not_to include departure }
      end
    end
  end

  describe 'make_announcement' do
    subject(:call) { announcer.make_announcement(args) }

    before do
      allow(announcer).to receive(:play)
      allow(announcer).to receive(:sleep)
    end

    let :base_args do
      { route_id: '20030', headsign: 'North Amherst', stop_id: '72', interval: 5 }
    end
    let(:args) { base_args }

    it 'plays the route fragment' do
      call
      expect(announcer).to have_received(:play).with(route: '20030')
    end

    it 'plays "toward"' do
      call
      expect(announcer).to have_received(:play).with(fragment: 'toward')
    end

    it 'plays the headsign fragment' do
      call
      expect(announcer).to have_received(:play)
        .with(headsign: 'North Amherst', route_id: '20030')
    end

    context 'when including the stop name' do
      it 'plays "will be leaving from"' do
        call
        expect(announcer).to have_received(:play)
          .with(fragment: 'will be leaving from')
      end

      it 'plays the stop fragment' do
        call
        expect(announcer).to have_received(:play).with(stop: '72')
      end
    end

    context 'when not including the stop name' do
      let(:args) { base_args.merge(options: { exclude_stop_name: true }) }

      it 'plays "will be leaving"' do
        call
        expect(announcer).to have_received(:play)
          .with(fragment: 'will be leaving')
      end

      it 'does not play the stop fragment' do
        call
        expect(announcer).not_to have_received(:play).with(stop: '72')
      end
    end

    context 'when the interval is less than one' do
      let(:args) { base_args.merge(interval: 0) }

      it 'plays the "now" fragment' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'now')
      end
    end

    context 'when the interval is 1 minute' do
      let(:args) { base_args.merge(interval: 1) }

      it 'plays the minute fragment' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'in 1 minute')
      end
    end

    context 'when interval is more than 1 minute, less than 60' do
      it 'plays the minutes fragment' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'in 5 minutes')
      end
    end

    context 'when interval is exactly 1 hour' do
      let(:args) { base_args.merge(interval: 60) }

      it 'plays the hour fragment' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'in 1 hour')
      end
    end

    context 'when interval is between 1 and 2 hours' do
      let(:args) { base_args.merge(interval: 65) }

      it 'plays the hour fragment' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'in 1 hour')
      end

      it 'plays the "and"' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'and')
      end

      it 'plays the minute fragment' do
        call
        expect(announcer).to have_received(:play).with(fragment: '5 minutes')
      end
    end

    context 'when interval is exactly 2 hours' do
      let(:args) { base_args.merge(interval: 120) }

      it 'plays the hour fragment' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'in 2 hours')
      end
    end

    context 'when interval is more than 2 hous' do
      let(:args) { base_args.merge(interval: 127) }

      it 'plays the hour fragment' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'in 2 hours')
      end

      it 'plays the "and"' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'and')
      end

      it 'plays the minute fragment' do
        call
        expect(announcer).to have_received(:play).with(fragment: '7 minutes')
      end
    end

    it 'pauses' do
      call
      expect(announcer).to have_received(:sleep).with(0.5)
    end
  end

  describe 'new_departures' do
    subject(:call) { announcer.new_departures }

    let(:time) { Time.now }
    # I would have route_id and headsign be symbols, but we encode as JSON.
    let :endpoint_response do
      [
        'RouteDirections' => [
          {
            'RouteId' => 'route_id',
            'Departures' => [
              {
                'EDT' => "/Date(#{time.to_i}000-0400)/",
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

    before do
      stub_const 'Announcer::PVTA_API_URL', 'http://example.com'
      announcer.instance_variable_set(:@query_stops, ['stop_id'])
      stub_request(:get, 'http://example.com/stopdepartures/get/stop_id')
        .to_return body: endpoint_response.to_json
    end

    around do |example|
      Timecop.freeze { example.run }
    end

    it { is_expected.to be_a Hash }

    it 'has an entry for the stop id' do
      expect(call.keys).to contain_exactly('stop_id')
    end

    it 'has an entry that is a Hash' do
      expect(call['stop_id']).to be_a Hash
    end

    it 'has an entry that has a route id/headsign pair' do
      expect(call['stop_id'].keys).to contain_exactly(%w[route_id headsign])
    end

    it 'has an entry that has a route id/headsign pair that is a Hash' do
      expect(call['stop_id'][%w[route_id headsign]]).to be_a Hash
    end

    it 'has an entry that has a route id/headsign pair that has a departure' do
      expect(call['stop_id'][%w[route_id headsign]].keys)
        .to contain_exactly('trip_id')
    end

    context 'EDT is right now' do
      it 'returns the correct data structure with the interval at 0' do
        expect(call['stop_id'][%w[route_id headsign]]['trip_id']).to be 0
      end
    end

    context 'EDT is in 5 minutes' do
      let(:time) { Time.now + 5 * 60 }

      it 'returns the correct data structure with the interval at 5' do
        expected_result = {
          'stop_id' => {
            %w[route_id headsign] => {
              'trip_id' => 5
            }
          }
        }
        expect(call).to eq expected_result
      end
    end
  end

  describe 'play' do
    subject(:call) { announcer.play fruit: 'banana' }

    let(:expected_path) { 'voice/fruits/banana.wav' }

    before do
      allow(announcer).to receive(:system)
      allow(announcer).to receive(:say)
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(expected_path).and_return(file_present)
    end

    context 'when the file exists at the expected path' do
      let(:file_present) { true }

      it 'plays the file' do
        call
        expect(announcer).to have_received(:system)
          .with(Announcer::AUDIO_COMMAND, expected_path)
      end
    end

    context 'file does not exist at the expected path' do
      let(:file_present) { false }

      context 'when another specifier is given' do
        let(:call) { announcer.play fruit: 'banana', color: 'yellow' }
        let(:new_expected_path) { 'voice/fruits/yellow/banana.wav' }

        before do
          allow(File).to receive(:file?).and_call_original
          allow(File).to receive(:file?).with(new_expected_path)
                                        .and_return(new_file_present)
        end

        context 'when a file exists in the directory matching the specifier value' do
          let(:new_file_present) { true }

          it 'plays the file' do
            call
            expect(announcer).to have_received(:system)
              .with(Announcer::AUDIO_COMMAND, new_expected_path)
          end
        end

        context 'when a file does not exist in that directory' do
          let(:new_file_present) { false }

          it 'says the text' do
            call
            expect(announcer).to have_received(:say).with('banana', any_args)
          end
        end
      end

      context 'when another specifier is not given' do
        it 'says the text' do
          call
          expect(announcer).to have_received(:say).with('banana', any_args)
        end
      end
    end
  end

  describe 'run' do
    subject(:call) { announcer.run }

    let(:departures_to_announce) { [] }

    before do
      %i[set_query_stops set_interval cache_departures play make_announcement
         update_github_issues!].each do |method|
        allow(announcer).to receive(method)
      end
      allow(announcer).to receive(:new_departures).and_return(:some_departures)
      allow(announcer).to receive(:cached_departures).and_return(:some_cached_departures)
      allow(announcer).to receive(:departures_crossed_interval)
        .and_return(departures_to_announce)
    end

    it 'sets the query stops' do
      call
      expect(announcer).to have_received(:set_query_stops)
    end

    it 'sets the interval' do
      call
      expect(announcer).to have_received(:set_interval)
    end

    it 'finds new departures' do
      call
      expect(announcer).to have_received(:new_departures)
    end

    it 'checks which departures to announce' do
      call
      expect(announcer).to have_received(:departures_crossed_interval)
        .with(:some_departures, :some_cached_departures)
    end

    it 'caches departures' do
      call
      expect(announcer).to have_received(:cache_departures).with(:some_departures)
    end

    context 'with no departures to announce' do
      it 'makes no announcements' do
        call
        expect(announcer).not_to have_received(:make_announcement)
      end
    end

    context 'with departures to announce' do
      let(:departures_to_announce) do
        [{
          route_id: 'someroute',
          headsign: 'somesign',
          stop_id: 'somestop',
          interval: 123
        }]
      end

      it 'dings' do
        call
        expect(announcer).to have_received(:play).with(fragment: 'ding')
      end

      it 'makes announcements' do
        call
        expect(announcer).to have_received(:make_announcement)
          .with(departures_to_announce[0])
      end

      it 'updates GitHub' do
        call
        expect(announcer).to have_received(:update_github_issues!)
      end
    end
  end

  describe 'set_interval' do
    subject(:call) { announcer.set_interval }

    def current_interval
      announcer.instance_variable_get(:@interval)
    end

    before do
      stub_const 'Announcer::CONFIG_FILE', :config_file
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(:config_file).and_return(file_present)
    end

    context 'with no config file' do
      let(:file_present) { false }

      it 'keeps the default interval' do
        expect { call }.not_to(change { current_interval })
      end
    end

    context 'with a config file' do
      let(:file_present) { true }

      before do
        allow(File).to receive(:read).with(:config_file).and_return(:json)
        allow(JSON).to receive(:parse).with(:json).and_return('interval' => 7)
      end

      it 'parses as JSON and reads the interval key' do
        call
        expect(current_interval).to be 7
      end
    end
  end

  describe 'say' do
    subject(:call) { announcer.say 'the text', :context }

    before do
      stub_const 'Announcer::SPEECH_COMMAND', :speech_command
      stub_const 'Announcer::MISSING_TEXT_FILE', :cache_file
      allow(announcer).to receive(:system)
      allow(announcer).to receive(:record_log_entry)
    end

    it 'calls out to the speach command' do
      call
      expect(announcer).to have_received(:system)
        .with(:speech_command, 'the text')
    end

    it 'records the missing announcement' do
      call
      expect(announcer).to have_received(:record_log_entry)
        .with(:cache_file, 'the text', :context)
    end
  end

  describe 'set_query_stops' do
    subject(:call) { announcer.set_query_stops }

    def current_stops
      announcer.instance_variable_get(:@query_stops)
    end

    before do
      stub_const 'Announcer::QUERY_STOPS_FILE', :stops_file
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(:stops_file).and_return(file_present)
    end

    context 'with no query stops file' do
      let(:file_present) { false }

      it 'keeps the default query stops' do
        expect { call }.not_to(change { current_stops })
      end
    end

    context 'with a query stops file' do
      let(:file_present) { true }
      let(:contents) { StringIO.new("STOP_ID     \n") }

      before do
        allow(File).to receive(:read).with(:stops_file).and_return(contents)
      end

      it 'reads the lines from the file to set the query stops' do
        call
        expect(current_stops).to contain_exactly('STOP_ID')
      end
    end
  end
end
