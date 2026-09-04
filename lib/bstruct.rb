# frozen_string_literal: true

require_relative "bstruct/version"

class BStruct
  class Error < StandardError; end

  module Bufferlike
    def copy_to(buf, offset)
      buf.copy(buffer, offset, size)
    end

    def copy_from(buf, offset)
      buffer.copy(buf, 0, size, offset)
    end

    def cast(type)
      case type
      when Symbol
        return ::BStruct.ScalarArray(type, size/::BStruct.sizeof(type)).from_buf(buffer)
      when Class
        return type.from_buf(buffer) if type.respond_to?(:from_buf)
      end
      raise ::ArgumentError, "type must be a symbol, BStruct, or Array type, found #{type.inspect}"
    end
  end

  include Bufferlike

  Field = Data.define(:type, :size, :offset)

  SIZEOF = {
    U8:  1, S8:  1,
    u16: 2, U16: 2, s16: 2, S16: 2,
    u32: 4, U32: 4, s32: 4, S32: 4,
    u64: 8, U64: 8, s64: 8, S64: 8,
    f32: 4, F32: 4,
    f64: 8, F64: 8
  }.freeze

  ALIASES = {
    i8: :S8, I8: :S8, u8: :U8, s8: :S8, ubyte: :U8, byte: :S8, char: :S8, uchar: :u8,
    i16: :s16, I16: :S16, short: :s16, ushort: :u16,
    i32: :s32, I32: :S32, int: :s32, uint: :u32,
    i64: :s64, I64: :S64, long: :s64, ulong: :u64,
    float: :f32, float32: :f32,
    double: :f64, float64: :f64
  }

  NAMEOF = {
    U8:  "Uint8", S8:  "Int8",
    u16: "Uint16", U16: "Uint16BE", s16: "Int16", S16: "Int16BE",
    u32: "Uint32", U32: "Uint32BE", s32: "Int32", S32: "Int32BE",
    u64: "Uint64", U64: "Uint64BE", s64: "Int64", S64: "Int64BE",
    f32: "Float32", F32: "Float32BE",
    f64: "Float64", F64: "Float64BE"
  }

  def self.sizeof(type)
    case type
    when Symbol
      ty = ALIASES[type] || type
      if !SIZEOF.key?(ty)
        raise ::ArgumentError, "unknown type #{type.inspect}"
      end
      return SIZEOF[ty]
    when BStruct, Array, ScalarArray, Scalar, Tuple then type.size
    when Class
      if type < BStruct ||
         type < Scalar ||
         type < Tuple ||
         type < ScalarArray ||
         type < Array
        return type.size
      end
    end
    raise ::ArgumentError, "type must be on of Symbol, BStruct, or Array type, found #{type.inspect}"
  end

  def self.nameof(type)
    case type
    when Symbol
      ty = ALIASES[type] || type
      if !NAMEOF.key?(ty)
        raise ::ArgumentError, "unknown type #{type.inspect}"
      end
      return NAMEOF[ty]
    when BStruct, Array, ScalarArray, Scalar then type.class.to_s
    when Class
      type.to_s
    end
  end

  attr_reader :buffer

  def initialize(buffer = nil)
    if buffer
      if buffer.size != self.class.size
        raise ArgumentError, "incorrect buffer size (given #{buffer.size}, expected #{self.class.size})"
      end
      @buffer = buffer
    else
      @buffer = IO::Buffer.new(self.class.size)
    end
  end

  def to_buf = @buffer

  def size = self.class.size

  def self.from_buf(buffer)
    new(buffer)
  end

  def self.from_value(val)
    case val
    when self then val
    when ::Array then new(*val)
    when ::Hash then new(**val)
    when ::IO::Buffer then new(val)
    else raise ArgumentError, "cannot make BStruct from #{val.class}"
    end
  end

  def self.[](*args)
    case args
    in [] then @_array_type ||= Array(self)
    in [Integer => count] then Array(self, count)
    else Array(self, args.length).from_value(args)
    end
  end

  def self.define(&block)
    b = Builder.new
    if block.arity > 1
      yield b
    else
      b.instance_exec(&block)
    end
    b.build
  end

  def ==(other)
    return false unless other.is_a?(self.class)
    return @buffer <=> other.buffer
  end
  alias :eql? :==

  def hash
    [self.class.fields, @buffer.get_string].hash
  end

  class Array
    include Enumerable
    include Bufferlike

    attr_reader :buffer, :type

    @type = nil
    @count = nil

    def self.type = @type
    def self.count = @count
    def self.element_size = @type&.size

    def self.size
      return nil unless count && element_size
      element_size*count
    end

    def initialize(buffer = nil, type: self.class.type, count: self.class.count, &)
      if type.nil?
        raise ArgumentError, "cannot create an array without count"
      end
      if !self.class.matches_type?(type)
        raise ::ArgumentError, "tried to initialize typed array with incomplatible type (given #{type}, expected #{self.class.type})"
      end
      if buffer
        if count
          if buffer.size != count*type.size
            raise ArgumentError, "incorrect buffer size (given #{buffer.size}, expected #{count*type.count})"
          end
        else
          count = buffer.size / type.size
        end
        @buffer = buffer
      else
        if !count
          raise ::ArgumentError.new("cannot create an array without count")
        end
        if !type.size
          raise ::ArgumentError.new("cannot create an array of unsized type #{type}")
        end
        @buffer = ::IO::Buffer.new(type.size*count)
      end

      @type = type
      @count = count

      if block_given?
        @count.times do |i|
          type.from_value(yield(i)).copy_to(@buffer, i*type.size)
        end
      end
    end

    def to_buf = @buffer

    def self.from_buf(buffer, type: self.type)
      case type
      when Symbol
        ty = ALIASES[type] || type
        if !SIZEOF.key?(ty)
          raise ::ArgumentError, "unknown type #{type.inspect}"
        end
        return ScalarArray.from_buf(buffer, type: ty)
      when Class
        type[].new(buffer)
      end
      raise ::ArgumentError, "type must be a symbol, BStruct, or Array type, found #{type.inspect}"
    end

    def self.from_value(val)
      case val
      when Array then val
      when ::IO::Buffer then new(buffer)
      when ::Array
        if count && val.length != count
          raise ArgumentError, "array length mismatch (given #{val.length}, expected #{count})"
        end
        ::BStruct._infer_type_from_array(val, type:).new { val[it] }
      else
        raise ArgumentError, "cannot create Array from #{val.class}"
      end
    end

    def self.matches_type?(type)
      return true if self.type.nil?
      return true if type <= self.type
      [Array, ScalarArray].any? do |arrayclass|
        next unless self.type < arrayclass && type < arrayclass
        next unless self.type.matches_type?(type.type)
        !self.type.count || self.type.count == type.count
      end
    end

    def length
      @count
    end

    def size = @buffer.size

    def element_size = @type.size

    def each(&)
      return to_enum(:each) unless block_given?
      @count.times do |i|
        yield self[i]
      end
    end

    def to_a
      ::Array.new(@count) { |i| self[i] }
    end
    alias :to_ary :to_a

    def ==(other)
      case other
      when Array
        return self.type == other.type && @buffer <=> other.buffer
      when ::Array
        return to_a == other
      else false
      end
    end

    def eql?(other)
      return false unless other.is_a?(Array)
      return self.type == other.type && @buffer <=> other.buffer
    end

    def hash
      [self.class.type, @buffer.get_string].hash
    end

    def [](i, s = nil)
      if s
        i = @count + i if i.negative?
        @type[s].from_buf(@buffer.slice(i*@type.size, s*@type.size))
      elsif i.is_a?(Range)
        a, b = i.begin, i.end
        a = @count + a if a < 0
        b = @count + b if b < 0
        b += 1 unless i.exclude_end?
        self[a, b - a]
      else
        i = @count + i if i.negative?
        @type.from_buf(@buffer.slice(i*@type.size, @type.size))
      end
    end

    def []=(*args)
      case args.length
      when 2
        i, v = args
        if i.is_a?(Range)
          a, b = i.begin, i.end
          a = @count + a if a < 0
          b = @count + b if b < 0
          b += 1 unless i.exclude_end?
          self[a, b - a] = v
        else
          i = @count + i if i.negative?
          @type.from_value(v).copy_to(@buffer, i*@type.size)
        end
      when 3
        i, s, v = args
        i = @count + i if i.negative?
        @type[s].from_value(v).copy_to(@buffer, i*@type.size, count: s)
      else raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 2-3)"
      end
    end

    def self.[](count = nil)
      if count.nil?
        @_array_type ||=  ::BStruct.Array(self)
      else
        ::BStruct.Array(self, count)
      end
    end
  end

  def self.Array(type, count = nil)
    return ScalarArray(type, count) if type.is_a?(Symbol)
    return type[count] if type < Scalar

    Class.new(Array) do
      @type = type
      @count = count

      class << self
        def to_s
          return name if name
          if n = ::BStruct.nameof(type)
            "#{n}[#{count || ""}]"
          else
            "BStruct::Array[#{type}, #{count || "unsized"}]"
          end
        end
        alias :inspect :to_s
      end

      def initialize(*args, type: self.class.type, count: self.class.count, &)
        case args.length
        when 0
          if count.nil?
            raise ::ArgumentError, "cannot initialize array, count not specified"
          end
          super(type:, count:, &)
          return
        when 1
          arg = args.first
          case arg
          when Integer
            if count && arg != count
              raise ::ArgumentError, "tried to initialize sized array type with different size (given #{arg}, expected #{self.class.count})"
            end
            super(type:, count: arg, &)
            return
          when IO::Buffer
            super(arg, type:, count:)
            return
          when Array
            if arg.type != self.class.type
              raise ::ArgumentError, "array type mismatch (given #{arg.type}, expected #{self.class.type})"
            end
            if count && arg.length != count
              raise ::ArgumentError, "array length mismatch (given #{arg.length}, expected #{count})"
            end
            super(arg.buffer, type:, count: count || arg.length)
            return
          when ::Array
            if count && arg.length != count
              raise ::ArgumentError, "array length mismatch (given #{arg.length}, expected #{count})"
            end
            args = arg
          end
        else
          if count && args.length != count
            raise ::ArgumentError, "wrong number of arguments (given #{args.length}, expected 0, 1, or #{count})"
          end
        end
        if type.size.nil?
          type = ::BStruct._infer_type_from_array(args, type:).type
        end
        super(type: type, count: args.length) { args[it] }
      end

      def self.from_buf(buffer)
        new(buffer)
      end

      def to_s
        "#{::BStruct.nameof(self.class.type)}#{self.to_a.inspect}"
      end
      alias :inspect :to_s
    end
  end

  class ScalarArray
    include Enumerable
    include Bufferlike

    attr_reader :buffer, :type

    @type = nil
    @count = nil
    @endian = :little

    def self.type = @type
    def self.count = @count
    def self.endianness = @endian
    def self.element_size
      return nil unless type
      ::BStruct.sizeof(type)
    end

    def self.size
      return nil unless count && element_size
      count*element_size
    end

    def initialize(buffer = nil, type: self.class.type, count: self.class.count, endian: self.class.endianness, &)
      raise ArgumentError, "type must be a symbol, found #{type.class}" unless type.is_a?(Symbol)
      if !self.class.matches_type?(type)
        raise ::ArgumentError, "tried to initialize typed array with incomplatible type (given #{type}, expected #{self.class.type})"
      end
      @type = ALIASES[type] || type
      if endian == :big || endian == :network
        endian = :big
        @type = @type.to_s.upcase.to_sym
      elsif endian != :little
        raise ::ArgumentError, "unknown endianness #{endian}"
      end
      @size = ::BStruct.sizeof(@type)

      if buffer
        if count
          if buffer.size != count*@size
            raise ArgumentError, "incorrect buffer size (given #{buffer.size}, expected #{count*@size})"
          end
        else
          count = buffer.size / @size
        end
        @buffer = buffer
      else
        if !count
          raise ::ArgumentError.new("cannot create an array without count")
        end
        @buffer = ::IO::Buffer.new(count*@size)
      end

      @count = count

      if block_given?
        count.times do |i|
          @buffer.set_value(@type, i*@size, yield(i))
        end
      end
    end

    def to_buf = @buffer

    def self.from_buf(buffer, type: self.type)
      new(type, buffer.size / ::BStruct.sizeof(type), buffer)
    end

    def self.from_value(val)
      case val
      when ScalarArray then val
      when ::Array then new(count: self.count || val.length) { val[it] }
      else raise ArgumentError, "cannot create Array from #{val.class}"
      end
    end

    def self.matches_type?(type)
      return true if self.type.nil?
      type = ALIASES[type] || type
      styp = ALIASES[self.type] || self.type
      type == styp
    end

    def length
      @count
    end

    def size
      return nil if length.nil?
      return nil if element_size.nil?

      length * element_size
    end

    def element_size
      return nil unless @type
      ::BStruct.sizeof(@type)
    end

    def each(&)
      return to_enum(:each) unless block_given?
      @count.times do |i|
        yield @buffer.get_value(@type, i*@size)
      end
    end

    def to_a
      ::Array.new(@count) { |i| self[i] }
    end
    alias :to_ary :to_a

    def ==(other)
      case other
      when ScalarArray
        return self.type == other.type && @buffer <=> other.buffer
      when ::Array
        return to_a == other
      else false
      end
    end

    def eql?(other)
      return false unless other.is_a?(ScalarArray)
      return self.type == other.type && @buffer <=> other.buffer
    end

    def hash
      [self.class.type, @buffer.get_string].hash
    end

    def [](i, s = nil)
      if s
        i = @count + i if i.negative?
        ::BStruct.ScalarArray(@type, s).from_buf(@buffer.slice(i*@size, s*@size))
      elsif i.is_a?(Range)
        a, b = i.begin, i.end
        a = @count + a if a < 0
        b = @count + b if b < 0
        b += 1 unless i.exclude_end?
        self[a, b - a]
      else
        i = @count + i if i.negative?
        @buffer.get_value(@type, i*@size)
      end
    end

    def []=(*args)
      case args.length
      when 2
        i, v = args
        if i.is_a?(Range)
          a, b = i.begin, i.end
          a = count + a if a < 0
          b = count + b if b < 0
          b += 1 unless i.exclude_end?
          self[a, b - a] = v
        else
          i = count + i if i.negative?
          @buffer.set_value(@type, i*@size, v)
        end
      when 3
        i, s, v = args
        i = count + i if i.negative?
        type[s].from_value(v).copy_to(@buffer, i*self.class.element_size)
      else raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 2..3)"
      end
    end

    def self.[](count = nil)
      if count.nil?
        @_array_type ||= ::BStruct.Array(self)
      else
        ::BStruct.Array(self, count)
      end
    end
  end

  def self.ScalarArray(type, count = nil, endian: :little)
    raise ::ArgumentError, "type must be a symbol, found #{type.inspect}" unless type.is_a?(Symbol)
    ty = ALIASES[type] || type
    if !SIZEOF.key?(ty)
      raise ::ArgumentError, "unknown type #{type.inspect}"
    end
    if endian == :big || endian == :network
      endian = :big
      ty = ty.to_s.upcase.to_sym
    elsif endian != :little
      raise ::ArgumentError, "unknown endianness #{endian}"
    end
    if count.nil?
      @_scalar_array_types ||= {}
      return @_scalar_array_types[ty] if @_scalar_array_types[ty]
    end
    Class.new(ScalarArray) do
      @type = ty
      @endian = endian
      @count = count

      class << self
        def to_s
          return name if name
          if n = ::BStruct.nameof(@type)
            "#{n}[#{@count || ""}]"
          else
            "BStruct::ScalarArray[#{@type}, #{@count || "unsized"}]"
          end
        end
        alias :inspect :to_s
      end

      def initialize(arg = nil, type: self.class.count, count: self.class.count, endian: self.class.endianness, &)
        type = case endian
        when :little then self.class.type.to_s.downcase.to_sym
        when :big, :network then self.class.type.to_s.upcase.to_sym
        else raise ::ArgumentError, "unknown endianness #{endian}"
        end
        type = ALIASES[type] || type
        if arg
          case arg
          when Integer then super(type:, count: arg, &)
          when ::IO::Buffer then super(arg, type:, count:)
          when ScalarArray
            if arg.type != type
              raise ::ArgumentError, "array type mismatch (given #{arg.type}, expected #{type})"
            end
            super(arg.buffer, type:, count: arg.length)
          else
            arg = arg.to_a
            super(type:, count: arg.length) { arg[it] }
          end
        else
          super(type:, count:, endian:)
        end
      end

      def self.from_buf(buffer)
        new(buffer)
      end
    end.tap do |klass|
      @_scalar_array_types[ty] = klass if count.nil?
    end
  end

  class Scalar
    def initialize
      raise NotImplementedError, "cannot instantiate abstract class #{self.class}"
    end

    def ==(other)
      if other.is_a?(Scalar)
        value == other.value
      else
        value == other
      end
    end

    def to_i = value.to_i
    alias :to_int :to_i
    def to_f = value.to_f
    def to_s = value.to_s
    def inspect = "#{self.class.name}(#{value})"

    def self.from_buf(buffer, type: self.type)
      new(buffer.get_value(type, 0))
    end

    def self.from_value(value)
      new(value)
    end

    def copy_to(buf, offset)
      buf.set_value(self.class.type, offset, value)
    end

    def self.[](count = nil)
      if count.nil?
        @_array_type ||= ::BStruct::ScalarArray(type)
      else
        ::BStruct::ScalarArray(type, count)
      end
    end
  end

  def self.Scalar(type)
    ty = ALIASES[type] || type
    if !SIZEOF.key?(ty)
      raise ::ArgumentError, "unknown type #{type.inspect}"
    end

    Class.new(Scalar) do
      @type = ty
      @size = SIZEOF[ty]
      def self.type = @type
      def self.size = @size
      attr_accessor :value
      def initialize(value)
        @value = value
      end
      def type = self.class.type
      def size = self.class.size
    end
  end

  Uint8 = Scalar(:u8)
  Int8 = Scalar(:s8)
  Uint16 = Scalar(:u16)
  Int16 = Scalar(:s16)
  Uint32 = Scalar(:u32)
  Int32 = Scalar(:s32)
  Uint64 = Scalar(:u64)
  Int64 = Scalar(:s64)
  Float32 = Scalar(:f32)
  Float64 = Scalar(:f64)

  Uint8Array = Uint8[]
  Int8Array = Int8[]
  Uint16Array = Uint16[]
  Int16Array = Int16[]
  Uint32Array = Uint32[]
  Int32Array = Int32[]
  Uint64Array = Uint64[]
  Int64Array = Int64[]
  Float32Array = Float32[]
  Float64Array = Float64[]

  class Tuple
    include Enumerable
    include Bufferlike

    attr_accessor :buffer

    def initialize(*args)
      if self.class == Tuple
        raise ::NotImplementedError, "cannot instantiate abstract class Tuple"
      end

      if args.length == 1 && args.first.is_a?(::IO::Buffer)
        buf = args.first
        if buf.size != self.class.size
          raise ArgumentError, "incorrect buffer size (given #{buf.size}, expected #{self.class.size})"
        end
        @buffer = buf
      else
        @buffer = ::IO::Buffer.new(self.class.size)
        i = 0;
        args.zip(self.class.fields).each do |arg, field|
          case field.type
          when ::Symbol
            @buffer.set_value(field.type, field.offset, arg)
          else
            field.type.from_value(arg).copy_to(@buffer, field.offset)
          end
          i+=1
        end
      end
    end

    def to_buf = @buffer

    def self.from_buf(buffer)
      new(buffer)
    end

    def self.from_value(value)
      case value
      when self then value
      when ::Array then new(*value)
      when ::IO::Buffer then new(value)
      end
    end

    def length
      self.class.fields.length
    end

    def size = self.class.size

    def each(&)
      return to_enum(:each) unless block_given?
      self.class.fields.each_index do |i|
        yield self[i]
      end
    end

    def to_s
      "#{self.class.name}(#{self.class.fields.each_index.map { self[it].to_s }.join(", ")})"
    end

    def inspect
      "#<#{self.class.name} [#{self.class.fields.each_index.map { self[it].inspect }.join(", ")}]>"
    end

    def ==(other)
      return false unless other.is_a?(self.class)
      @buffer <=> other.buffer
    end
    alias :eql? :==

    def hash
      [self.class.fields, @buffer.get_string].hash
    end

    def [](i)
      field = self.class.fields[i]
      case field.type
      when ::Symbol
        @buffer.get_value(field.type, field.offset)
      else
        field.type.from_buf(@buffer.slice(field.offset, field.size))
      end
    end

    def []=(i, val)
      field = self.class.fields[i]
      case field.type
      when ::Symbol
        @buffer.set_value(field.type, field.offset, val)
      else
        field.type.from_value(val).copy_to(@buffer, field.offset)
      end
    end

    def self.[](*args)
      case args
      in [] then @_array_type ||= ::BStruct.Array(self)
      in [Integer => count] then ::BStruct.Array(self, count)
      else ::BStruct.Array(self, args.length).new(args)
      end
    end
  end

  def self.Tuple(*types)
    fields = []
    offset = 0

    types.each do |type|
      type ||= 1
      if type.is_a?(Integer)
        offset += type
      else
        type = type.type if type.kind_of?(Scalar)
        type = ALIASES[type] || type if type.is_a?(Symbol)
        size = ::BStruct.sizeof(type)
        if size.nil?
          raise ::ArgumentError, "cannot define tuple with unsized type #{type}"
        end
        fields << Field.new(size: ::BStruct.sizeof(type), type:, offset:)
        offset += size
      end
    end

    Class.new(Tuple) do
      @fields = fields
      @size = offset

      class << self
        def fields = @fields
        def size = @size
        def length = @fields.length
        def to_s
          return name if name
          "Tuple(#{@fields.map { ::BStruct.nameof(it) || it }.join(", ")})"
        end
        alias :inspect :to_s
      end
    end
  end

  def self._infer_type_from_array(arr, type: nil)
    if type.nil?
      if arr.empty?
        raise ArgumentError, "cannot infer type from empty array"
      end
      element = arr.first
      case element
      when BStruct, Array, ScalarArray, Scalar, Tuple
        element.class[arr.length]
      when ::Array
        _infer_type_from_array(element)[arr.length]
      else
        raise "cannot infer type from array of #{element.class}"
      end
    else
      if type.is_a?(Symbol)
        ty = ALIASES[type] || type
        if !SIZEOF.key?(ty)
          raise ::ArgumentError, "unknown type #{type.inspect}"
        end
        ScalarArray(type, arr.length)
      elsif type < BStruct || type < Tuple || type < Scalar
        type[arr.length]
      elsif type < Array || type < ScalarArray
        if type.size.nil?
          _infer_type_from_array(arr.first, type: type.type)[arr.length]
        else
          type[arr.length]
        end
      else
        raise "invalid type #{type.inspect}"
      end
    end
  end

  class Builder < BasicObject
    def initialize
      @endianness = :little
      @fields = {}
      @offset = 0
    end

    def little_endian!
      @endianness = :little
    end
    alias :little! :little_endian!

    def big_endian!
      @endianness = :big
    end
    alias :big! :big_endian!
    alias :network_endian! :big_endian!
    alias :network! :big_endian!

    def little_endian?
      @endianness == :little
    end
    alias :little? :little_endian?

    def big_endian?
      @endianness == :big
    end
    alias :big? :big_endian?
    alias :network_endian? :big_endian?
    alias :network? :big_endian?

    def u8 name, count = 1
      _add_field name, :U8, 1, count
    end
    alias :ubyte :u8
    alias :uchar :u8

    def s8 name, count = 1
      _add_field name, :S8, 1, count
    end
    alias :i8 :s8
    alias :byte :s8
    alias :char :s8

    def u16 name, count = 1, endian: @endianness
      _add_field name, :u16, 2, count, endian:
    end
    alias :ushort :u16

    def s16 name, count = 1, endian: @endianness
      _add_field name, :s16, 2, count, endian:
    end
    alias :i16 :s16
    alias :short :s16

    def u32 name, count = 1, endian: @endianness
      _add_field name, :u32, 4, count, endian:
    end
    alias :uint :u32

    def s32 name, count = 1, endian: @endianness
      _add_field name, :s32, 4, count, endian:
    end
    alias :i32 :s32
    alias :int :s32

    def u64 name, count = 1, endian: @endianness
      _add_field name, :u64, 8, count, endian:
    end
    alias :ulong :u64

    def s64 name, count = 1, endian: @endianness
      _add_field name, :s64, 8, count, endian:
    end
    alias :i64 :s64
    alias :long :s64

    def f32 name, count = 1, endian: @endianness
      _add_field name, :f32, 4, count, endian:
    end
    alias :float32 :f32
    alias :float :f32

    def f64 name, count = 1, endian: @endianness
      _add_field name, :f64, 8, count, endian:
    end
    alias :float64 :f64
    alias :double :f64

    def struct type, name, count = 1
      _add_struct_field name, type, count
    end
    alias :field :struct
    alias :array :struct
    alias :tuple :struct

    def padding(bytes = 1)
      @offset += bytes
    end
    alias :pad :padding
    alias :__ :padding

    def build
      fields = @fields
      size = @offset
      ::Class.new(::BStruct) do
        @fields = fields
        @size = size

        class << self
          def size = @size
          def fields = @fields

          def to_s
            return name if name
            "BStruct[#{@size}, #{@fields.length}]"
          end
          alias :inspect :to_s
        end

        def initialize(*args, **kwargs)
          return super if args.count == 1 && args.first.is_a?(::IO::Buffer)

          super()
          args_with_fields = if kwargs.empty? && !args.empty?
            if args.length > self.class.fields.count
              raise ::ArgumentError, "wrong number of argument (given #{args.length}, expected 0..#{self.class.fields.count})"
            end
            args.zip(self.class.fields.values)
          elsif args.empty? && !kwargs.empty?
            kwargs.map do |k, v|
              raise ::ArgumentError, "unknown keyword #{k.inspect}" unless self.class.fields.key?(k)
              [v, self.class.fields[k]]
            end
          elsif args.empty? && kwargs.empty?
            []
          else
            # TODO: maybe mix?
            raise ::ArgumentError, "cannot mix positional arguments and keyword arguments"
          end

          args_with_fields.each do |arg, field|
            case field.type
            when ::Symbol
              @buffer.set_value(field.type, field.offset, arg)
            else
              field.type.from_value(arg).copy_to(@buffer, field.offset)
            end
          end
        end

        def inspect
          "#<#{self.class} #{self.class.fields.map do |name, field|
            "@#{name}=#{
              if field.count == 1
                self.send(name).inspect
              else
                self.send(name).to_a.inspect
              end
            }"
          end.join(" ")}>"
        end
        alias :to_s :inspect

        fields.each do |name, field|
          case field.type
          when ::Symbol
            class_eval <<-RUBY, __FILE__, __LINE__+1
              def #{name}
                @buffer.get_value(:#{field.type}, #{field.offset})
              end
              def #{name}=(value)
                @buffer.set_value(:#{field.type}, #{field.offset}, value)
              end
            RUBY
          else
            class_eval <<-RUBY, __FILE__, __LINE__+1
              def #{name}
                self.class.fields[:#{name}].type
                  .from_buf(@buffer.slice(#{field.offset}, #{field.size}))
              end
              def #{name}=(value)
                self.class.fields[:#{name}].type
                  .from_value(value)
                  .copy_to(@buffer, #{field.offset})
              end
            RUBY
          end
        end
      end
    end

    private

      def _add_field(name, type, size, count, endian: @endianness)
        name = name.to_sym if name.is_a?(::String)
        unless name.is_a?(::Symbol)
          ::Kernel.raise ::ArgumentError, "name must be a String or Symbol, found #{name.class}"
        end
        type = type.to_s.upcase.to_sym if endian == :big || endian == :network
        if count > 1
          type = ::BStruct.ScalarArray(type, count)
          size = type.size
        end
        @fields[name] = Field.new(size:, type:, offset: @offset)
        @offset += size
      end

      def _add_struct_field(name, type, count)
        name = name.to_sym if name.is_a?(::String)
        unless name.is_a?(::Symbol)
          raise ::ArgumentError, "name must be a String or Symbol, found #{name.class}"
        end
        unless type < ::BStruct || type < ::BStruct::Array || type < ::BStruct::ScalarArray || type < ::BStruct::Tuple || type < ::BStruct::Scalar
          ::Kernel.raise ::ArgumentError, "struct type must be a BStruct, Tuple, Scalar, or Array type, given #{type.inspect}"
        end
        if count > 1
          type = type[count]
        end
        if type.size.nil?
          ::Kernel.raise ::ArgumentError, "cannot define struct with unsized type #{type}"
        end
        @fields[name] = Field.new(size: type.size, type:, offset: @offset)
        @offset += type.size*count
      end
      
  end
end
