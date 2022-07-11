module Trailblazer
  class Activity
    module DSL
      module Linear
        module VariableMapping
          # Code invoked through the normalizer, building runtime structures.
          # Naming
          #   Option: Tuple => user filter
          #   Tuple: #<In ...>
          module DSL
            module_function

            # Compute pipeline for {:input} option.
            def pipe_for_mono_input(input: [], inject: [], in_filters: [], output: [], **)
              has_input              = Array(input).any?
              has_mono_options       = has_input || Array(inject).any? || Array(output).any? # :input, :inject and :output are "mono options".
              has_composable_options = in_filters.any? # DISCUSS: why are we not testing Inject()?

              if has_mono_options && has_composable_options
                warn "[Trailblazer] You are mixing `:input` and `In() => ...`. `In()` and Inject () options are ignored and `:input` wins: #{input} #{inject} #{output} <> #{in_filters} / "
              end

              pipeline = initial_input_pipeline(add_default_ctx: !has_input)
              pipeline = add_steps_for_input_option(pipeline, input: input)
              pipeline = add_steps_for_inject_option(pipeline, inject: inject)

              return pipeline, has_mono_options, has_composable_options
            end

            # Compute pipeline for In() and Inject().
            # We allow to inject {:initial_input_pipeline} here in order to skip creating a new input pipeline and instead
            # use the inherit one.
            def pipe_for_composable_input(in_filters: [], inject_filters: [], initial_input_pipeline: initial_input_pipeline_for(in_filters), **)
              inject_filters = DSL::Inject.filters_for_injects(inject_filters) # {Inject() => ...} the pure user input gets translated into AddVariable aggregate steps.
              in_filters     = DSL::Tuple.filters_from_options(in_filters)

              # With only injections defined, we do not filter out anything, we use the original ctx
              # and _add_ defaulting for injected variables.
              pipeline = add_filter_steps(initial_input_pipeline, in_filters)
              pipeline = add_filter_steps(pipeline, inject_filters)
            end

            # initial pipleline depending on whether or not we got any In() filters.
            def initial_input_pipeline_for(in_filters)
              is_inject_only = Array(in_filters).empty?

              initial_input_pipeline(add_default_ctx: is_inject_only)
            end


            # Adds the default_ctx step as per option {:add_default_ctx}
            def initial_input_pipeline(add_default_ctx: false)
              # No In() or {:input}. Use default ctx, which is the original ctxx.
              # When using Inject without In/:input, we also need a {default_input} ctx.
              default_ctx_row =
                add_default_ctx ? Activity::TaskWrap::Pipeline.Row(*default_input_ctx_config) : nil

              pipe = Activity::TaskWrap::Pipeline.new(
                [
                  Activity::TaskWrap::Pipeline.Row("input.init_hash", VariableMapping.method(:initial_aggregate)), # very first step
                  default_ctx_row,
                  Activity::TaskWrap::Pipeline.Row("input.scope",     VariableMapping.method(:scope)), # last step
                ].compact
              )
            end

            def default_input_ctx_config # almost a Row.
              ["input.default_input", VariableMapping.method(:default_input_ctx)]
            end

              # Handle {:input} and {:inject} option, the "old" interface.
            def add_steps_for_input_option(pipeline, input:)
              tuple         = DSL.In(name: ":input") # simulate {In() => input}
              input_filter  = DSL::Tuple.filters_from_options([[tuple, input]])

              add_filter_steps(pipeline, input_filter)
            end


            def pipe_for_mono_output(output_with_outer_ctx: false, output: [], out_filters: [], **)
              # No Out(), no {:output} will result in a default_output_ctx step.
              has_output             = Array(output).any?
              has_mono_options       = has_output
              has_composable_options = Array(out_filters).any?

              if has_mono_options && has_composable_options
                warn "[Trailblazer] You are mixing `:output` and `Out() => ...`. `Out()` options are ignored and `:output` wins."
              end

              pipeline = initial_output_pipeline(add_default_ctx: !has_output)
              pipeline = add_steps_for_output_option(pipeline, output: output, output_with_outer_ctx: output_with_outer_ctx)

              return pipeline, has_mono_options, has_composable_options
            end

            def add_steps_for_output_option(pipeline, output:, output_with_outer_ctx:)
              tuple         = DSL.Out(name: ":output", with_outer_ctx: output_with_outer_ctx) # simulate {Out() => output}
              output_filter = DSL::Tuple.filters_from_options([[tuple, output]])

              add_filter_steps(pipeline, output_filter, prepend_to: "output.merge_with_original")
            end

            def pipe_for_composable_output(out_filters: [], initial_output_pipeline: initial_output_pipeline(add_default_ctx: Array(out_filters).empty?), **)
              out_filters = DSL::Tuple.filters_from_options(out_filters)

              add_filter_steps(initial_output_pipeline, out_filters, prepend_to: "output.merge_with_original")
            end

            def initial_output_pipeline(add_default_ctx: false)
              default_ctx_row =
                add_default_ctx ? Activity::TaskWrap::Pipeline.Row(*default_output_ctx_config) : nil

              Activity::TaskWrap::Pipeline.new(
                [
                  Activity::TaskWrap::Pipeline.Row("output.init_hash", VariableMapping.method(:initial_aggregate)), # very first step
                  default_ctx_row,
                  Activity::TaskWrap::Pipeline.Row("output.merge_with_original", VariableMapping.method(:merge_with_original)), # last step
                ].compact
              )
            end

            def default_output_ctx_config # almost a Row.
              ["output.default_output", VariableMapping.method(:default_output_ctx)]
            end

            def add_steps_for_inject_option(pipeline, inject:)
              injects = inject.collect { |name| name.is_a?(Symbol) ? [DSL.Inject(), [name]] : [DSL.Inject(), name] }

              tuples  = DSL::Inject.filters_for_injects(injects) # DISCUSS: should we add passthrough/defaulting here at Inject()-time?

              add_filter_steps(pipeline, tuples)
            end

            def add_filter_steps(pipeline, rows, prepend_to: "input.scope") # FIXME: do we need all this?
              rows = add_variables_steps_for_filters(rows)

              adds = Activity::Adds::FriendlyInterface.adds_for(
                rows.collect { |row| [row[1], id: row[0], prepend: prepend_to] }
              )

              Activity::Adds.apply_adds(pipeline, adds)
            end

                      # Returns array of step rows ("sequence").
            # @param filters [Array] List of {Filter} objects
            def add_variables_steps_for_filters(filters) # FIXME: allow output too!
              filters.collect do |filter|
                ["input.add_variables.#{filter.name}", filter.aggregate_step] # FIXME: config name sucks, of course, if we want to allow inserting etc.
              end
            end


          # Filter code
            # Converting user options to callable filters.

            # @param [Array, Hash, Proc] User option coming from the DSL, like {[:model]}
            #
            # Returns a "filter interface" callable that's invoked in {AddVariables}:
            #   filter.(new_ctx, ..., keyword_arguments: new_ctx.to_hash, **circuit_options)
            def self.build_filter(user_filter)
              Trailblazer::Option(filter_for(user_filter))
            end

            # Convert a user option such as {[:model]} to a filter.
            #
            # Returns a filter proc to be called in an Option.
            # @private
            def self.filter_for(filter)
              if filter.is_a?(::Array) || filter.is_a?(::Hash)
                filter_from_dsl(filter)
              else
                filter
              end
            end

            # The returned filter compiles a new hash for Scoped/Unscoped that only contains
            # the desired i/o variables.
            #
            # Filter expects a "filter interface" {(ctx, **)}.
            def self.filter_from_dsl(map)
              hsh = DSL.hash_for(map)

              ->(incoming_ctx, **kwargs) { Hash[hsh.collect { |from_name, to_name| [to_name, incoming_ctx[from_name]] }] }
            end

            def self.hash_for(ary)
              return ary if ary.instance_of?(::Hash)
              Hash[ary.collect { |name| [name, name] }]
            end

            # Keeps user's DSL configuration for a particular io-pipe step.
            # Implements the interface for the actual I/O code and is DSL code happening in the normalizer.
            # The actual I/O code expects {DSL::In} and {DSL::Out} objects to generate the two io-pipes.
            #
            # If a user needs to inject their own private iop step they can create this data structure with desired values here.
            # This is also the reason why a lot of options computation such as {:with_outer_ctx} happens here and not in the IO code.

            class Tuple < Struct.new(:name, :add_variables_class, :filter_builder, :insert_args)
              def self.filters_from_options(tuples_to_user_filters)
                tuples_to_user_filters.collect { |tuple, user_filter| tuple.(user_filter) }
              end


              # @return [Filter] Filter instance that keeps {name} and {aggregate_step}.
              def call(user_filter)
                filter         = filter_builder.(user_filter)
                aggregate_step = add_variables_class.new(filter, user_filter)

                VariableMapping::Filter.new(aggregate_step, filter, name, add_variables_class)
              end
            end # TODO: implement {:insert_args}

            # In, Out and Inject are objects instantiated when using the DSL, for instance {In() => [:model]}.
            class In < Tuple; end
            class Out < Tuple; end

            def self.In(name: rand, add_variables_class: AddVariables, filter_builder: method(:build_filter))
              In.new(name, add_variables_class, filter_builder)
            end

            # Builder for a DSL Output() object.
            def self.Out(name: rand, add_variables_class: AddVariables::Output, with_outer_ctx: false, delete: false, filter_builder: method(:build_filter), read_from_aggregate: false)
              add_variables_class = AddVariables::Output::WithOuterContext  if with_outer_ctx
              add_variables_class = AddVariables::Output::Delete            if delete
              filter_builder      = ->(user_filter) { user_filter }         if delete
              add_variables_class = AddVariables::ReadFromAggregate         if read_from_aggregate

              Out.new(name, add_variables_class, filter_builder)
            end

            def self.Inject()
              Inject.new
            end

            # This class is supposed to hold configuration options for Inject().
            class Inject
            # Translate the raw input of the user to {In} tuples
              # @return Array of VariableMapping::Filter
              def self.filters_for_injects(injects)
                injects.collect do |inject, user_filter| # iterate all {Inject() => user_filter} calls
                  DSL::Inject.compute_filters_for_inject(inject, user_filter)
                end.flatten(1)
              end

              # Compute {In} tuples from the user's DSL input.
              # We simply use AddVariables but use our own {inject_filter} which checks if the particular
              # variable is already present in the incoming ctx.
              def self.compute_filters_for_inject(inject, user_filter) # {user_filter} either [:current_user, :model] or {model: ->{}}
                return filters_for_array(inject, user_filter) if user_filter.is_a?(Array)
                filters_for_hash_of_callables(inject, user_filter)
              end

              # [:model, :current_user]
              def self.filters_for_array(inject, user_filter)
                user_filter.collect do |name|
                  inject_filter = ->(original_ctx, **) { original_ctx.key?(name) ? {name => original_ctx[name]} : {} } # FIXME: make me an {Inject::} method.

                  filter_for(inject, inject_filter, name, "passthrough")
                end
              end

              # {model: ->(*) { snippet }}
              def self.filters_for_hash_of_callables(inject, user_filter)
                user_filter.collect do |name, defaulting_filter|
                  inject_filter = ->(original_ctx, **kws) { original_ctx.key?(name) ? {name => original_ctx[name]} : {name => defaulting_filter.(original_ctx, **kws)} }

                  filter_for(inject, inject_filter, name, "defaulting_callable")
                end
              end

              def self.filter_for(inject, inject_filter, name, type)
                DSL.In(name: "inject.#{type}.#{name.inspect}", add_variables_class: AddVariables).(inject_filter)
              end
            end

          end # DSL
        end
      end
    end
  end
end