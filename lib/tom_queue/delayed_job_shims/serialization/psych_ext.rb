module TomQueue
  class PerformableMethod
    # serialize to YAML
    def encode_with(coder)
      coder.map = {
        'object' => object,
        'method_name' => method_name,
        'args' => args
      }
    end
  end
end

module Psych
  def self.load_dj(yaml)
    result = parse(yaml)
    result ? TomQueue::PsychExt::ToRuby.create.accept(result) : result
  end
end

module TomQueue
  module PsychExt
    class ToRuby < Psych::Visitors::ToRuby
      unless respond_to?(:create)
        def self.create
          new
        end
      end

      def visit_Psych_Nodes_Mapping(object) # rubocop:disable CyclomaticComplexity, MethodName, PerceivedComplexity
        return revive(Psych.load_tags[object.tag], object) if Psych.load_tags[object.tag]

        case object.tag
        when /^!ruby\/object/
          result = super
          if defined?(ActiveRecord::Base) && result.is_a?(ActiveRecord::Base)
            klass = result.class
            id = result[klass.primary_key]
            begin
              klass.find(id)
            rescue ActiveRecord::RecordNotFound => error # rubocop:disable BlockNesting
              raise TomQueue::DeserializationError, "ActiveRecord::RecordNotFound, class: #{klass}, primary key: #{id} (#{error.message})"
            end
          else
            result
          end
        when /^!ruby\/ActiveRecord:(.+)$/
          klass = resolve_class(Regexp.last_match[1])
          payload = Hash[*object.children.map { |c| accept c }]
          id = payload['attributes'][klass.primary_key]
          id = id.value if defined?(ActiveRecord::Attribute) && id.is_a?(ActiveRecord::Attribute)
          begin
            klass.unscoped.find(id)
          rescue ActiveRecord::RecordNotFound => error
            raise TomQueue::DeserializationError, "ActiveRecord::RecordNotFound, class: #{klass}, primary key: #{id} (#{error.message})"
          end
        when /^!ruby\/Mongoid:(.+)$/
          klass = resolve_class(Regexp.last_match[1])
          payload = Hash[*object.children.map { |c| accept c }]
          id = payload['attributes']['_id']
          begin
            klass.find(id)
          rescue Mongoid::Errors::DocumentNotFound => error
            raise TomQueue::DeserializationError, "Mongoid::Errors::DocumentNotFound, class: #{klass}, primary key: #{id} (#{error.message})"
          end
        when /^!ruby\/DataMapper:(.+)$/
          klass = resolve_class(Regexp.last_match[1])
          payload = Hash[*object.children.map { |c| accept c }]
          begin
            primary_keys = klass.properties.select(&:key?)
            key_names = primary_keys.map { |p| p.name.to_s }
            klass.get!(*key_names.map { |k| payload['attributes'][k] })
          rescue DataMapper::ObjectNotFoundError => error
            raise TomQueue::DeserializationError, "DataMapper::ObjectNotFoundError, class: #{klass} (#{error.message})"
          end
        else
          super
        end
      end

      def resolve_class(klass_name)
        return nil if !klass_name || klass_name.empty?
        klass_name.constantize
      rescue
        super
      end
    end
  end
end
