require 'spec_helper'

describe Chewy::Search::Response, :orm do
  before { Chewy.massacre }

  before do
    stub_model(:city)
    stub_model(:country)

    stub_index(:cities) do
      index_scope City
      field :name
      field :rating, type: 'integer'
    end
    stub_index(:countries) do
      index_scope Country
      field :name
      field :rating, type: 'integer'
    end
  end

  before do
    CitiesIndex.import!(cities: cities)
    CountriesIndex.import!(countries)
  end

  let(:cities) { Array.new(2) { |i| City.create!(rating: i, name: "city #{i}") } }
  let(:countries) { Array.new(2) { |i| Country.create!(rating: i + 2, name: "country #{i}") } }

  let(:request) { Chewy::Search::Request.new(CitiesIndex, CountriesIndex).order(:rating) }
  let(:raw_response) { request.send(:perform) }
  let(:load_options) { {} }
  let(:loader) { Chewy::Search::Loader.new(indexes: [CitiesIndex, CountriesIndex], **load_options) }
  subject { described_class.new(raw_response, loader) }

  describe '#hits' do
    specify { expect(subject.hits).to be_a(Array) }
    specify { expect(subject.hits).to have(4).items }
    specify { expect(subject.hits).to all be_a(Hash) }
    specify do
      expect(subject.hits.flat_map(&:keys).uniq)
        .to match_array(%w[_id _index _score _source sort])
    end

    context do
      let(:raw_response) { {} }
      specify { expect(subject.hits).to eq([]) }
    end
  end

  describe '#total' do
    specify { expect(subject.total).to eq(4) }

    context do
      let(:raw_response) { {} }
      specify { expect(subject.total).to eq(0) }
    end
  end

  describe '#max_score' do
    specify { expect(subject.max_score).to be_nil }

    context do
      let(:request) { Chewy::Search::Request.new(CitiesIndex).query(range: {rating: {lte: 42}}) }
      specify { expect(subject.max_score).to eq(1.0) }
    end
  end

  describe '#suggest' do
    specify { expect(subject.suggest).to eq({}) }

    context do
      let(:request) do
        Chewy::Search::Request.new(CitiesIndex).suggest(
          my_suggestion: {
            text: 'city country',
            term: {
              field: 'name'
            }
          }
        )
      end
      specify do
        expect(subject.suggest).to eq(
          'my_suggestion' => [
            {'text' => 'city', 'offset' => 0, 'length' => 4, 'options' => []},
            {'text' => 'country', 'offset' => 5, 'length' => 7, 'options' => []}
          ]
        )
      end
    end
  end

  describe '#aggs' do
    specify { expect(subject.aggs).to eq({}) }

    context do
      let(:request) do
        Chewy::Search::Request.new(CitiesIndex, CountriesIndex).aggs(avg_rating: {avg: {field: :rating}})
      end
      specify { expect(subject.aggs).to eq('avg_rating' => {'value' => 1.5}) }
    end
  end

  describe '#wrappers' do
    specify { expect(subject.wrappers).to be_a(Array) }
    specify { expect(subject.wrappers).to have(4).items }
    specify do
      expect(subject.wrappers.map(&:class).uniq)
        .to contain_exactly(CitiesIndex, CountriesIndex)
    end
    specify { expect(subject.wrappers.map(&:_data)).to eq(subject.hits) }

    context do
      let(:raw_response) { {} }
      specify { expect(subject.wrappers).to eq([]) }
    end

    context do
      let(:raw_response) { {'hits' => {}} }
      specify { expect(subject.wrappers).to eq([]) }
    end

    context do
      let(:raw_response) { {'hits' => {'hits' => []}} }
      specify { expect(subject.wrappers).to eq([]) }
    end

    context do
      let(:raw_response) do
        {'hits' => {'hits' => [
          {'_index' => 'cities',
           '_type' => 'city',
           '_id' => '1',
           '_score' => 1.3,
           '_source' => {'id' => 2, 'rating' => 0}}
        ]}}
      end
      specify { expect(subject.wrappers.first).to be_a(CitiesIndex) }
      specify { expect(subject.wrappers.first.id).to eq(2) }
      specify { expect(subject.wrappers.first.rating).to eq(0) }
      specify { expect(subject.wrappers.first._score).to eq(1.3) }
      specify { expect(subject.wrappers.first._explanation).to be_nil }
    end

    context do
      let(:raw_response) do
        {'hits' => {'hits' => [
          {'_index' => 'countries',
           '_type' => 'country',
           '_id' => '2',
           '_score' => 1.2,
           '_explanation' => {foo: 'bar'}}
        ]}}
      end
      specify { expect(subject.wrappers.first).to be_a(CountriesIndex) }
      specify { expect(subject.wrappers.first.id).to eq('2') }
      specify { expect(subject.wrappers.first.rating).to be_nil }
      specify { expect(subject.wrappers.first._score).to eq(1.2) }
      specify { expect(subject.wrappers.first._explanation).to eq(foo: 'bar') }
    end
  end

  describe '#objects' do
    specify { expect(subject.objects).to eq([*cities, *countries]) }
  end

  describe '#object_hash' do
    specify { expect(subject.object_hash.keys).to eq(subject.wrappers) }
    specify { expect(subject.object_hash.values).to eq(subject.objects) }
  end
end
