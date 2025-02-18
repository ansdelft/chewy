require 'spec_helper'

if defined?(Sidekiq)
  require 'sidekiq/testing'
  require 'mock_redis'

  describe Chewy::Strategy::DelayedSidekiq do
    around do |example|
      Chewy.strategy(:bypass) { example.run }
    end

    before do
      redis = MockRedis.new
      allow(Sidekiq).to receive(:redis).and_yield(redis)
      Sidekiq::Worker.clear_all
    end

    before do
      stub_model(:city) do
        update_index('cities') { self }
      end

      stub_index(:cities) do
        index_scope City
      end
    end

    let(:city) { City.create!(name: 'hello') }
    let(:other_city) { City.create!(name: 'world') }

    it 'does not trigger immediate reindex due to it`s async nature' do
      expect { [city, other_city].map(&:save!) }
        .not_to update_index(CitiesIndex, strategy: :delayed_sidekiq)
    end

    it "respects 'refresh: false' options" do
      allow(Chewy).to receive(:disable_refresh_async).and_return(true)
      expect(CitiesIndex).to receive(:import!).with([city.id, other_city.id], refresh: false)
      scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [city.id, other_city.id])
      scheduler.postpone
      Chewy::Strategy::DelayedSidekiq::Worker.drain
    end

    context 'with default config' do
      it 'does schedule a job that triggers reindex with default options' do
        Timecop.freeze do
          expect(Sidekiq::Client).to receive(:push).with(
            {
              'queue' => 'chewy',
              'at' => (Time.current.to_i.ceil(-1) + 2.seconds).to_i,
              'class' => Chewy::Strategy::DelayedSidekiq::Worker,
              'args' => ['CitiesIndex', an_instance_of(Integer)]
            }
          ).and_call_original

          expect($stdout).not_to receive(:puts)

          Sidekiq::Testing.inline! do
            expect { [city, other_city].map(&:save!) }
              .to update_index(CitiesIndex, strategy: :delayed_sidekiq)
              .and_reindex(city, other_city).only
          end
        end
      end
    end

    context 'with custom config' do
      before do
        CitiesIndex.strategy_config(
          delayed_sidekiq: {
            reindex_wrapper: lambda { |&reindex|
              puts 'hello'
              reindex.call
            },
            margin: 5,
            latency: 60
          }
        )
      end

      it 'respects :strategy_config options' do
        Timecop.freeze do
          expect(Sidekiq::Client).to receive(:push).with(
            hash_including(
              'queue' => 'chewy',
              'at' => (60.seconds.from_now.change(sec: 0) + 5.seconds).to_i,
              'class' => Chewy::Strategy::DelayedSidekiq::Worker,
              'args' => ['CitiesIndex', an_instance_of(Integer)]
            )
          ).and_call_original

          expect($stdout).to receive(:puts).with('hello') # check that reindex_wrapper works

          Sidekiq::Testing.inline! do
            expect { [city, other_city].map(&:save!) }
              .to update_index(CitiesIndex, strategy: :delayed_sidekiq)
              .and_reindex(city, other_city).only
          end
        end
      end
    end

    context 'two reindex call within the timewindow' do
      it 'accumulates all ids does the reindex one time' do
        Timecop.freeze do
          expect(CitiesIndex).to receive(:import!).with([other_city.id, city.id]).once
          scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [city.id])
          scheduler.postpone
          scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [other_city.id])
          scheduler.postpone
          Chewy::Strategy::DelayedSidekiq::Worker.drain
        end
      end

      context 'one call with update_fields another one without update_fields' do
        it 'does reindex of all fields' do
          Timecop.freeze do
            expect(CitiesIndex).to receive(:import!).with([other_city.id, city.id]).once
            scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [city.id], update_fields: ['name'])
            scheduler.postpone
            scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [other_city.id])
            scheduler.postpone
            Chewy::Strategy::DelayedSidekiq::Worker.drain
          end
        end
      end

      context 'both calls with different update fields' do
        it 'deos reindex with union of fields' do
          Timecop.freeze do
            expect(CitiesIndex).to receive(:import!).with([other_city.id, city.id], update_fields: %w[description name]).once
            scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [city.id], update_fields: ['name'])
            scheduler.postpone
            scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [other_city.id], update_fields: ['description'])
            scheduler.postpone
            Chewy::Strategy::DelayedSidekiq::Worker.drain
          end
        end
      end
    end

    context 'two calls within different timewindows' do
      it 'does two separate reindexes' do
        Timecop.freeze do
          expect(CitiesIndex).to receive(:import!).with([city.id]).once
          expect(CitiesIndex).to receive(:import!).with([other_city.id]).once
          Timecop.travel(20.seconds.ago) do
            scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [city.id])
            scheduler.postpone
          end
          scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [other_city.id])
          scheduler.postpone
          Chewy::Strategy::DelayedSidekiq::Worker.drain
        end
      end
    end

    context 'first call has update_fields' do
      it 'does first reindex with the expected update_fields and second without update_fields' do
        Timecop.freeze do
          expect(CitiesIndex).to receive(:import!).with([city.id], update_fields: ['name']).once
          expect(CitiesIndex).to receive(:import!).with([other_city.id]).once
          Timecop.travel(20.seconds.ago) do
            scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [city.id], update_fields: ['name'])
            scheduler.postpone
          end
          scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [other_city.id])
          scheduler.postpone
          Chewy::Strategy::DelayedSidekiq::Worker.drain
        end
      end
    end

    context 'both calls have update_fields option' do
      it 'does both reindexes with their expected update_fields option' do
        Timecop.freeze do
          expect(CitiesIndex).to receive(:import!).with([city.id], update_fields: ['name']).once
          expect(CitiesIndex).to receive(:import!).with([other_city.id], update_fields: ['description']).once
          Timecop.travel(20.seconds.ago) do
            scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [city.id], update_fields: ['name'])
            scheduler.postpone
          end
          scheduler = Chewy::Strategy::DelayedSidekiq::Scheduler.new(CitiesIndex, [other_city.id], update_fields: ['description'])
          scheduler.postpone
          Chewy::Strategy::DelayedSidekiq::Worker.drain
        end
      end
    end

    describe '#clear_delayed_sidekiq_timechunks test helper' do
      it 'clears redis from the timechunk sorted sets to avoid leak between tests' do
        timechunks_set = -> { Sidekiq.redis { |redis| redis.zrange('chewy:delayed_sidekiq:CitiesIndex:timechunks', 0, -1) } }

        expect { CitiesIndex.import!([1], strategy: :delayed_sidekiq) }
          .to change { timechunks_set.call.size }.by(1)

        expect { Chewy::Strategy::DelayedSidekiq.clear_timechunks! }
          .to change { timechunks_set.call.size }.to(0)
      end
    end
  end
end
