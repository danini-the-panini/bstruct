# frozen_string_literal: true

require_relative "bstruct/version"

class BStruct
  class Error < StandardError; end

  Field = Data.define(:type, :size, :offset, :count)

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
    when BStruct, Array, ScalarArray, Scalar then type.size
    when Class
      if type < BStruct || type < Scalar
        return type.size
      elsif type < Array
        return nil if type.count.nil?
        return nil if type.type_size.nil?
        return type.type_size * type.count
      elsif type < ScalarArray
        return nil if type.count.nil?
        return nil if type.type_size.nil?
        return type.type_size * type.count
      end
    when Array
      type.sum { sizeof(it) }
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

  def self.from_buf(buffer, *, **)
    new(buffer)
  end

  def cast(type, *, **)
    case type
    when Symbol then return ScalarArray.new(type, self.class.size/::BStruct.sizeof(type), @buffer)
    when Class
      if type < BStruct
        return type.from_buf(@buffer, *, **)
      elsif type < ScalarArray
        return type.from_buf(@buffer, *, **)
      elsif type < Array
        return type.from_buf(@buffer, self.class, *, **)
      end
    end
    raise ::ArgumentError, "type must be a symbol, BStruct, or Array type, found #{type.inspect}"
  end

  def self.[](*args)
    case args
    in [] then @_array_type ||= Array(self)
    in [Integer => count] then Array(self, count)
    else Array(self, args.length).new(args)
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

    attr_reader :buffer, :type

    def initialize(type, count, buffer = nil, &)
      if buffer
        if buffer.size != count*type.size
          raise ArgumentError, "incorrect buffer size (given #{buffer.size}, expected #{count*type.count})"
        end
        @buffer = buffer
      else
        tsize = type.size
        if !tsize
          raise ::ArgumentError.new("cannot create an array of unsized type")
        end
        @buffer = ::IO::Buffer.new(type.size*count)
      end

      @type = type
      @count = count

      if block_given?
        if type < Array || type < ScalarArray
          count.times do |i|
            @buffer.copy(::BStruct.to_buf(yield(i), type.type, type.count), i*type.size, type.size)
          end
        else
          count.times do |i|
            @buffer.copy(::BStruct.to_buf(yield(i), type), i*type.size, type.size)
          end
        end
      end
    end

    def to_buf = @buffer

    def self.from_buf(buffer, type = :u8, *, **)
      case type
      when Symbol
        ty = ALIASES[type] || type
        if !SIZEOF.key?(ty)
          raise ::ArgumentError, "unknown type #{type.inspect}"
        end
        return ScalarArray.from_buf(buffer, ty, *, **)
      when Class
        if type < BStruct
          return Array.new(type, buffer.size / type.size, buffer)
        elsif type < Array
          type.from_buf(buffer, type, *, **)
        end
      end
      raise ::ArgumentError, "type must be a symbol, BStruct, or Array type, found #{type.inspect}"
    end

    def cast(type, *, **)
      case type
      when Symbol then ScalarArray.new(type, @buffer.size/::BStruct.sizeof(type), @buffer)
      when Class then type.from_buf(@buffer, *, **)
      else raise ::ArgumentError, "cannot cast to #{type.inspect}"
      end
    end

    def length
      @count
    end

    def size
      @buffer.size
    end

    def type_size
      @type.size
    end

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
        Array.new(@type, s, @buffer.slice(i*@type.size, s*@type.size))
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
          @buffer.copy(::BStruct.to_buf(v), i*@type.size, @type.size)
        end
      when 3
        i, s, v = args
        i = @count + i if i.negative?
        @buffer.copy(::BStruct.to_buf(v), i*@size, s*@size)
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

    def self.of_length(count)
      Class.new(self) do
        @count = count
        class << self
          def count = @count
          def to_s
            if n = ::BStruct.nameof(type)
              "#{n}[#{count}]"
            else
              "BStruct::Array[#{type || 'untyped'}, #{count}]"
            end
          end
          alias :inspect :to_s
        end
        def initialize(type, buffer = nil)
          super(type, self.class.count, buffer)
        end
      end
    end
  end

  def self.Array(type, count = nil)
    return ScalarArray(type, count) if type.is_a?(Symbol)

    Class.new(Array) do
      @type = type
      @count = count

      class << self
        def type = @type
        def count = @count

        def size
          return nil if @count.nil?

          @type.size * @count
        end

        def type_size
          @type.size
        end

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

      def initialize(*args)
        case args.length
        when 0
          if self.class.count.nil?
            raise ::ArgumentError, "cannot initialize array, count not specified"
          end
          super(self.class.type, self.class.count)
        when 1
          arg = args.first
          case arg
          when Integer
            if self.class.count && arg != self.class.count
              raise ::ArgumentError, "tried to initialize sized array type with different size (given #{arg}, expected #{self.class.count})"
            end
            super(self.class.type, arg)
          when IO::Buffer then super(self.class.type, self.class.count || arg.size/self.class.type.size, arg)
          when Array
            if arg.type != self.class.type
              raise ::ArgumentError, "array type mismatch (given #{arg.type}, expected #{self.class.type})"
            end
            if self.class.count && arg.length != self.class.count
              raise ::ArgumentError, "array length mismatch (given #{arg.length}, expected #{self.class.count})"
            end
            super(self.class.type, self.class.count || arg.length, arg.buffer)
          when ::Array
            if self.class.count && arg.length != self.class.count
              raise ::ArgumentError, "array length mismatch (given #{arg.length}, expected #{self.class.count})"
            end
            super(self.class.type, self.class.count || arg.length) { arg[it] }
          end
        else
          if self.class.count && args.length != self.class.count
            raise ::ArgumentError, "wrong number of arguments (given #{args.length}, expected 0, 1, or #{self.class.count})"
          end
          type, size = ::BStruct._type_size_from_array(self.class.type, args)
          super(type, args.count) { args[it] }
        end
      end

      def self.from_buf(buffer, *, **)
        new(buffer)
      end

      def self.of_length(count)
        return self if count == @count
        ::BStruct.Array(@type, count)
      end

      def self.of_type(type)
        return self if type == @type
        ::BStruct.Array(type, count)
      end

      def to_s
        "#{::BStruct.nameof(self.class.type)}#{self.to_a.inspect}"
      end
      alias :inspect :to_s
    end
  end

  class ScalarArray
    include Enumerable

    attr_reader :buffer, :type

    def initialize(type, count, buffer = nil, &)
      @size = ::BStruct.sizeof(type)

      if buffer
        if buffer.size != count*@size
          raise ArgumentError, "incorrect buffer size (given #{buffer.size}, expected #{@size*count})"
        end
        @buffer = buffer
      else
        @buffer = ::IO::Buffer.new(@size*count)
      end

      @type = ALIASES[type] || type
      @count = count

      if block_given?
        count.times do |i|
          @buffer.set_value(@type, i*@size, yield(i))
        end
      end
    end

    def to_buf = @buffer

    def self.from_buf(buffer, type = :u8, *, **)
      new(type, buffer.size / ::BStruct.sizeof(type), buffer)
    end

    def cast(type, *, **)
      case type
      when Symbol
        return ScalarArray.new(type, @buffer.size/::BStruct.sizeof(type), @buffer)
      when Class
        if type < BStruct
          return type.from_buf(@buffer)
        elsif type < ScalarArray
          return type.from_buf(@buffer, *, **)
        elsif type < Array
          return type.from_buf(@buffer, *, **)
        end
      end
      raise ::ArgumentError, "type must be a symbol, BStruct, or Array type, found #{type.inspect}"
    end

    def length
      @count
    end

    def size
      @buffer.size
    end

    def type_size
      @type.size
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
        ScalarArray.new(@type, s, @buffer.slice(i*@size, s*@size))
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
          a = @count + a if a < 0
          b = @count + b if b < 0
          b += 1 unless i.exclude_end?
          self[a, b - a] = v
        else
          i = @count + i if i.negative?
          @buffer.set_value(@type, i*@size, v)
        end
      when 3
        i, s, v = args
        i = @count + i if i.negative?
        @buffer.copy(::BStruct.to_buf(v), i*@size, s*@size)
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

    def self.of_length(count)
      Class.new(self) do
        @count = count
        class << self
          def count = @count
          def to_s
            if n = ::BStruct.nameof(type)
              "#{n}[#{count}]"
            else
              "BStruct::Array[#{type || 'untyped'}, #{count}]"
            end
          end
          alias :inspect :to_s
        end
        def initialize(type, buffer = nil)
          super(type, self.class.count, buffer)
        end
      end
    end

    def self.of_type(type)
      Class.new(self) do
        @type = type
        class << self
          def type = @count
          def to_s
            if n = ::BStruct.nameof(type)
              "#{n}[#{count || ""}]"
            else
              "BStruct::Array[#{type}, #{count || "unsized"}]"
            end
          end
          alias :inspect :to_s
        end
        def initialize(count, buffer = nil)
          super(self.class.type, count, buffer)
        end
      end
    end
  end

  def self.ScalarArray(type, count = nil, endian: :little)
    if !type.is_a?(Symbol)
      raise ::ArgumentError, "type must be a symbol, found #{type.inspect}"
    end
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

    Class.new(ScalarArray) do
      @type = ty
      @endian = endian
      @count = count

      class << self
        def type = @type
        def endianness = @endian
        def count = @count
        def type_size = @type.size

        def size
          return nil unless @count

          ::BStruct.sizeof(@type) * @count
        end

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

      def initialize(arg, endian: self.class.endianness)
        type = case endian
        when :little then self.class.type.to_s.downcase.to_sym
        when :big, :network then self.class.type.to_s.upcase.to_sym
        else raise ::ArgumentError, "unknown endianness #{endian}"
        end
        type = ALIASES[type] || type
        size = ::BStruct.sizeof(type)
        case arg
        when Integer then super(type, arg)
        when ::IO::Buffer then super(type, arg.size/size, arg)
        when ScalarArray
          if arg.type != type
            raise ::ArgumentError, "array type mismatch (given #{arg.type}, expected #{type})"
          end
          super(type, arg.length, arg.buffer)
        else
          arg = arg.to_a
          super(type, arg.length) { arg[it] }
        end
      end

      def self.from_buf(buffer, *, **)
        new(buffer, **)
      end

      def self.of_length(count)
        return self if count == @count
        ::BStruct.ScalarArray(@type, count)
      end

      def self.of_type(type)
        return self if type == @type
        ::BStruct::ScalarArray(type, @count)
      end
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
      def initialize(val)
        @val = val
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

  def self.to_buf(val, type = :U8, count = 1)
    size = sizeof(type)
    total_size = size*count
    array_class = type.is_a?(Symbol) ? ScalarArray : Array

    case val
    when ::IO::Buffer
      if val.size != total_size
        raise ::ArgumentError, "buffer size mismatch (given #{val.size}, excepted #{total_size})"
      end
      val
    when ::BStruct
      val.buffer
    when array_class
      if val.type != type
        raise ::ArgumentError, "array type mismatch (given #{val.type}, expected #{type})"
      end
      if val.length != count
        raise ::ArgumentError, "array length mismatch (given #{val.length}, expected #{count}})"
      end
      val.buffer
    else
      val = val.to_ary
      if val.length != count
        raise ::ArgumentError, "array length mismatch (given #{val.length}, expected #{count}})"
      end
      array_class.new(type, count) { val[it] }.buffer
    end
  end

  def self._type_size_from_array(type, arr)
    size = ::BStruct.sizeof(type)
    if size.nil?
      subtype = type.type
      subsize = type.type_size
      if subsize.nil?
        subtype, subsize = _type_size_from_array(subtype, arr.first)
      end
      count = arr.map(&:length).max
      type = type.of_type(subtype).of_length(count)
    end
    return [type, size]
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
              if field.count == 1
                @buffer.set_value(field.type, field.offset, arg)
              else
                buf = ::BStruct.to_buf(arg, field.type, field.count)
                @buffer.copy(buf, field.offset, field.count*field.size)
              end
            else
              if field.count == 1
                @buffer.copy(arg.buffer, field.offset, field.size)
              else
                buf = ::BStruct.to_buf(arg, field.type, field.count)
                @buffer.copy(buf, field.offset, field.count*field.size)
              end
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
            if field.count == 1
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
                  ScalarArray.new(:#{field.type}, #{field.count}, @buffer.slice(#{field.offset}, #{field.count*field.size}))
                end
                def #{name}=(value)
                  buf = ::BStruct.to_buf(value, :#{field.type}, #{field.count})
                  @buffer.copy(buf, #{field.offset}, #{field.count*field.size})
                end
              RUBY
            end
          else
            if field.count == 1
              class_eval <<-RUBY, __FILE__, __LINE__+1
                def #{name}
                  self.class.fields[:#{name}].type.new(@buffer.slice(#{field.offset}, #{field.size}))
                end
                def #{name}=(value)
                  @buffer.copy(value.buffer, #{field.offset}, #{field.size})
                end
              RUBY
            else
              class_eval <<-RUBY, __FILE__, __LINE__+1
                def #{name}
                  ::BStruct::Array.new(self.class.fields[:#{name}].type, #{field.count}, @buffer.slice(#{field.offset}, #{field.count*field.size}))
                end
                def #{name}=(value)
                  buf = ::BStruct.to_buf(arg, self.class.fields[:#{name}].type, #{field.count})
                  @buffer.copy(buf, #{field.offset}, #{field.count*field.size})
                end
              RUBY
            end
          end
        end
      end
    end

    private

      def _add_field(name, type, size, count, endian: @endianness)
        type = type.to_s.upcase.to_sym if endian == :big || endian == :network
        @fields[name] = Field.new(size:, type:, offset: @offset, count:)
        @offset += size*count
      end

      def _add_struct_field(name, type, count)
        unless type < ::BStruct
          ::Kernel.raise ::ArgumentError, "struct type must be a BStruct, given #{type.inspect}"
        end
        @fields[name] = Field.new(size: type.size, type:, offset: @offset, count:)
        @offset += type.size*count
      end
      
  end
end
