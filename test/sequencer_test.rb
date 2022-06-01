require "test_helper"

class SequencerTest < Minitest::Spec
  Imp = T.def_steps(:a, :b, :c, :d, :f, :g)

  let(:helper) { Activity::Railway }

  it "builds a Sequence" do
    options            = Activity::Path::DSL.OptionsForSequencer()
    normalizer_options = options.reject { |k, v| [:normalizers, :sequence].include?(k) }
    normalizers        = options[:normalizers]
    sequence           = options[:sequence]

    sequence = Activity::DSL::Linear::Sequencer.(:step, Imp.method(:a), {id: :a}, normalizer_options: normalizer_options, normalizers: normalizers, sequence: sequence)

    assert_process sequence, :success, %{
#<Start/:default>
 {Trailblazer::Activity::Right} => <*#<Method: SequencerTest::Imp.a>>
<*#<Method: SequencerTest::Imp.a>>
 {Trailblazer::Activity::Right} => #<End/:success>
#<End/:success>
}
  end

  it "Path() helper uses same options as outer Sequencer" do
    shared_options = {step_interface_builder: Fixtures.method(:circuit_interface_builder)}

    block = ->(*) do
      step Imp.method(:c), id: :c
    end

    options            = Activity::Path::DSL.OptionsForSequencer(**shared_options)
    normalizer_options = options.reject { |k, v| [:normalizers, :sequence].include?(k) }
    normalizers        = options[:normalizers]
    sequence           = options[:sequence]

    sequence = Activity::DSL::Linear::Sequencer.(:step, Imp.method(:a), {id: :a, helper.Output(:success) => helper.Path(end_id: "End.path", end_task: helper.End(:path))},
      normalizer_options: normalizer_options, normalizers: normalizers, sequence: sequence,
      &block
    )

    assert_process sequence, :success, :path, %{
#<Start/:default>
 {Trailblazer::Activity::Right} => #<Fixtures::CircuitInterface:0x @step=#<Method: SequencerTest::Imp.a>>
#<Fixtures::CircuitInterface:0x @step=#<Method: SequencerTest::Imp.a>>
 {Trailblazer::Activity::Right} => #<Fixtures::CircuitInterface:0x @step=#<Method: SequencerTest::Imp.c>>
#<Fixtures::CircuitInterface:0x @step=#<Method: SequencerTest::Imp.c>>
 {Trailblazer::Activity::Right} => #<End/:path>
#<End/:success>

#<End/:path>
}
  end
end
