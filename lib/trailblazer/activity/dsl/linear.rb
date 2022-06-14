require "trailblazer-activity"
require "trailblazer/declarative"

class Trailblazer::Activity
  module DSL
    # Implementing a specific DSL, simplified version of the {Magnetic DSL} from 2017.
    #
    # Produces {Implementation} and {Intermediate}.
    module Linear
      module_function

      # {Sequence} consists of rows.
      # {Sequence row} consisting of {[magnetic_to, task, connections_searches, data]}.
      # Complies with the Adds interface (#to_a).
      class Sequence < Array
        # Row interface is part of the ADDs specification.
        class Row < Array
          def id
            self[3][:id]
          end
        end

        # Return {Sequence row} consisting of {[magnetic_to, task, connections_searches, data]}.
        def self.create_row(task:, magnetic_to:, wirings:, **options)
          Row[
            magnetic_to,
            task,
            wirings,
            options # {id: "Start.success"}
          ]
        end
      end

      # Sequence
      # Search strategies are part of the {wirings}, they find the next step
      # for an output.
      module Search
        module_function

        # From this task onwards, find the next task that's "magnetic to" {target_color}.
        # Note that we only go forward, no back-references are done here.
        def Forward(output, target_color)
          ->(sequence, me) do
            target_seq_row = find_in_range(sequence[sequence.index(me)+1..-1], target_color)

            return output, target_seq_row
          end
        end

        # Tries to find a track colored step by doing a Forward-search, first, then wraps around going
        # through all steps from sequence start to self.
        def WrapAround(output, target_color)
          ->(sequence, me) do
            my_index      = sequence.index(me)
            # First, try all elements after me, then go through the elements preceding myself.
            wrapped_range = sequence[my_index+1..-1] + sequence[0..my_index-1]

            target_seq_row = find_in_range(wrapped_range, target_color)

            return output, target_seq_row
          end
        end

        def Noop(output)
          ->(sequence, me) do
            return output, [nil,nil,nil,{}] # FIXME
          end
        end

        # Find the seq_row with {id} and connect the current node to it.
        def ById(output, id)
          ->(sequence, me) do
            index          = Adds::Insert.find_index(sequence, id) or return output, sequence[0] # FIXME # or raise "Couldn't find {#{id}}"
            target_seq_row = sequence[index]

            return output, target_seq_row
          end
        end

        # @private
        def find_in_range(range, target_color)
          _target_seq_row = range.find { |seq_row| seq_row[0] == target_color }
        end
      end # Search

      # TODO: remove this deprecation for 1.1.
      module Insert
        def self.method(name)
          warn "[Trailblazer] Using `Trailblazer::Activity::DSL::Linear::Insert.method(:#{name})` is deprecated.
  Please use `Trailblazer::Activity::Adds::Insert.method(:#{name})`."

          Trailblazer::Activity::Adds::Insert.method(name)
        end
      end
    end # Linear
  end
end

require "trailblazer/activity/dsl/linear/helper"
require "trailblazer/activity/dsl/linear/normalizer"
require "trailblazer/activity/dsl/linear/normalizer/terminus"
require "trailblazer/activity/dsl/linear/helper/path"
require "trailblazer/activity/dsl/linear/sequencer"
require "trailblazer/activity/dsl/linear/compiler"
require "trailblazer/activity/dsl/linear/strategy"
require "trailblazer/activity/path"
require "trailblazer/activity/railway"
require "trailblazer/activity/fast_track"
require "trailblazer/activity/dsl/linear/variable_mapping"
