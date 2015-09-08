require 'json'
require 'yaml'
require 'deep_merge/core'
require 'transproc/all'

require 'pry-nav'

include Transproc::Composer

module TraverseTransformations
  extend Transproc::Registry

  def self.traverse(object, pattern)
    pattern.split('/').inject(object) do |ret, path|
      next nil unless ret
      case ret
        when Array then ret[path.to_i]
        when Hash then ret[path]
      end
    end
  end
end

module DeepTransformations
  def self.deep_symbolize_keys(hash)
    hash.each_with_object({}) do |(key, value), output|
      new_key = if key =~ /\d+/
        key.to_i
      else
        key.to_sym
      end

      output[new_key] =
        case value
        when Hash
          deep_symbolize_keys(value)
        when Array
          value.map { |item|
            item.is_a?(Hash) ? deep_symbolize_keys(item) : item
          }
        else
          value
        end
    end
  end
end

module HashTransformations
  def self.nest_hash(hash, keys)
    Array(keys).reverse_each.inject(hash) do |ret, key|
      { key => ret }
    end
  end
end

module Functions
  extend Transproc::Registry
  import Transproc::HashTransformations
  import TraverseTransformations
  import DeepTransformations
  import HashTransformations
end

def t(*args)
  Functions[*args]
end

sub_hashes = [
  compose do |fns|
    fns << t(:traverse, 'main/en/dates')
    fns << t(:nest_hash, 'en')
    fns << t(:deep_symbolize_keys)
  end,

  compose do |fns|
    fns << t(:traverse, 'main/en/dates/calendars/gregorian/dateTimeFormats/availableFormats')
    fns << t(:nest_hash, %w(en calendars gregorian additional_formats))
    fns << t(:deep_symbolize_keys)
  end
]

def get_keys(object)
  calculate_keys(object).map do |key_set|
    key_set.join('|')
  end
end

def calculate_keys(object)
  case object
    when Array
      object.each_with_index.flat_map do |elem, idx|
        calculate_keys(elem).map do |key_set|
          [idx] + key_set
        end
      end

    when Hash
      object.each_pair.flat_map do |key, value|
        calculate_keys(value).map do |key_set|
          [key] + key_set
        end
      end

    else
      [[]]
  end
end

data = JSON.parse(File.read('./cldr-dates-full-27.0.3/main/en/ca-gregorian.json'))

result = sub_hashes.inject(nil) do |ret, fn|
  if ret
    DeepMerge.deep_merge!(ret, fn.call(data))
  else
    fn.call(data)
  end
end

puts result.inspect

new_keys = get_keys(result)
old_keys = get_keys(YAML.load(File.read('/Users/cameron.dutro/workspace/twitter-cldr-rb/resources/locales/en/calendars.yml')))
puts "Missing keys:"
(old_keys - new_keys).each { |key| puts key }
puts ''
puts "Extra keys:"
(new_keys - old_keys).each { |key| puts key }
