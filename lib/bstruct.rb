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
    when Symbol
      if !SIZEOF.key?(type)
        raise ::ArgumentError, "unknown type #{type.inspect}"
      end
      ScalarArray.new(type, self.class.size/SIZEOF[type], @buffer)
    when Class
      if type < BStruct
        type.from_buf(@buffer, *, **)
      elsif type < ScalarArray
        type.from_buf(@buffer, *, **)
      elsif type < Array
        type.from_buf(@buffer, self.class, *, **)
      end
    else
      raise ::ArgumentError, "type must be a symbol, BStruct, or Array type, found #{type.inspect}"
    end
  end

  def self.[](count = nil)
    Array[self, count]
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
        @buffer = ::IO::Buffer.new(type.size*count)
      end

      @type = type
      @count = count

      if block_given?
        count.times do |i|
          @buffer.copy(yield(i).buffer, i*type.size, type.size)
        end
      end
    end

    def to_buf = @buffer

    def self.from_buf(buffer, type = :u8, *, **)
      case type
      when Symbol
        if !SIZEOF.key?(type)
          raise ::ArgumentError, "unknown type #{type.inspect}"
        end
        return ScalarArray.from_buf(buffer, type, *, **)
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
      when Symbol
        if !SIZEOF.key?(type)
          raise ::ArgumentError, "cannot cast to #{type.inspect}"
        end
        ScalarArray.new(type, @buffer.size/SIZEOF[type], @buffer)
      when Class then type.from_buf(@buffer, *, **)
      else raise ::ArgumentError, "cannot cast to #{type.inspect}"
      end
    end

    def length
      @count
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
        @type.new(@buffer.slice(i*@type.size, @type.size))
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
          @buffer.copy(v.buffer, i*@type.size, @type.size)
        end
      when 3
        i, s, v = args
        i = @count + i if i.negative?
        @buffer.copy(v, i*@size, s*@size)
      else raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 2-3)"
      end
    end

    def self.[](type, count = nil)
      Class.new(Array) do
        @type = type
        @count = count

        class << self
          def type = @type
          def count = @count

          def to_s
            "BStruct::Array[#{type}, #{count || "unsized"}]"
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
            if self.class.count
              if args.length != self.class.count
                raise ::ArgumentError, "wrong number of arguments (given #{args.length}, expected 0, 1, or #{self.class.count})"
              end
              super(self.class.type, self.class.count) { args[it] }
            else
              super(self.class.type, args.count) { args[it] }
            end
          end
        end

        def self.from_buf(buffer, *, **)
          new(buffer)
        end
      end
    end
  end

  class ScalarArray
    include Enumerable

    attr_reader :buffer, :type

    def initialize(type, count, buffer = nil, &)
      if !SIZEOF.key?(type)
        raise ::ArgumentError, "unknown type #{type.inspect}"
      end

      @size = SIZEOF[type]

      if buffer
        if buffer.size != count*@size
          raise ArgumentError, "incorrect buffer size (given #{buffer.size}, expected #{@size*count})"
        end
        @buffer = buffer
      else
        @buffer = ::IO::Buffer.new(@size*count)
      end

      @type = type
      @count = count

      if block_given?
        count.times do |i|
          @buffer.set_value(type, i*@size, yield(i))
        end
      end
    end

    def to_buf = @buffer

    def self.from_buf(buffer, type = :u8, *, **)
      new(type, buffer.size / SIZEOF[type], buffer)
    end

    def cast(type, *, **)
      case type
      when Symbol
        if !SIZEOF.key?(type)
          raise ::ArgumentError, "unknown type #{type.inspect}"
        end
        return ScalarArray.new(type, @buffer.size/SIZEOF[type], @buffer)
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
        @buffer.copy(v, i*@size, s*@size)
      else raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 2..3)"
      end
    end
  end

  class Uint8Array < ScalarArray
    TYPE = :U8

    def initialize(arg)
      case arg
      when Integer then super(TYPE, arg)
      when ::IO::Buffer then super(TYPE, buf.size, arg)
      when ScalarArray
        if arg.type != TYPE
          raise ::ArgumentError, "array type mismatch (given #{arg.type}, expected #{TYPE})"
        end
        super(TYPE, arg.length, arg.buffer)
      else
        arg = arg.to_a
        super(TYPE, arg.length) { arg[it] }
      end
    end

    def self.from_buf(buffer, *, **)
      new(buffer)
    end
  end

  class Int8Array < ScalarArray
    TYPE = :S8

    def initialize(arg)
      case arg
      when Integer then super(TYPE, arg)
      when ::IO::Buffer then super(TYPE, buf.size, arg)
      when ScalarArray
        if arg.type != TYPE
          raise ::ArgumentError, "array type mismatch (given #{arg.type}, expected #{TYPE})"
        end
        super(TYPE, arg.length, arg.buffer)
      else
        arg = arg.to_a
        super(TYPE, arg.length) { arg[it] }
      end
    end

    def self.from_buf(buffer, *, **)
      new(buffer)
    end
  end

  {
    u16: "Uint16",
    s16: "Int16",
    u32: "Uint32",
    s32: "Int32",
    u64: "Uint64",
    s64: "Int64",
    f32: "Float32",
    f64: "Float64"
  }.each do |type, name|
    class_eval <<~RUBY, __FILE__, __LINE__+1
      class #{name}Array < ScalarArray
        TYPE = :#{type}

        def initialize(arg, endian: :little)
          type = case endian
          when :little then TYPE
          when :big, :network then TYPE.to_s.upcase.to_sym
          else raise ::ArgumentError, "unknown endianness \#{endian}"
          end
          size = SIZEOF[type]
          case arg
          when Integer then super(type, arg)
          when ::IO::Buffer then super(type, arg.size/size, arg)
          when ScalarArray
            if arg.type != type
              raise ::ArgumentError, "array type mismatch (given \#{arg.type}, expected \#{type})"
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
      end
    RUBY
  end

  def self._check_to_buf_generic(val, type, size, count, array_class)
    total_size = size*count
    case val
    when ::IO::Buffer
      if val.size != total_size
        raise ::ArgumentError, "buffer size mismatch (given #{val.size}, excepted #{total_size})"
      end
      val
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

  def self._check_to_scalar_buf(val, type, count)
    _check_to_buf_generic(val, type, SIZEOF[type], count, ScalarArray)
  end

  def self._check_to_struct_buf(val, type, count)
    _check_to_buf_generic(val, type, type.size, count, Array)
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

    def little_endian?
      @endianness == :little
    end
    alias :little? :little_endian?

    def big_endian?
      @endianness == :big
    end
    alias :big? :big_endian?

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

    def u16 name, count = 1
      _add_field name, :u16, 2, count
    end
    alias :ushort :u16

    def s16 name, count = 1
      _add_field name, :s16, 2, count
    end
    alias :i16 :s16
    alias :short :s16

    def u32 name, count = 1
      _add_field name, :u32, 4, count
    end
    alias :uint :u32

    def s32 name, count = 1
      _add_field name, :s32, 4, count
    end
    alias :i32 :s32
    alias :int :s32

    def u64 name, count = 1
      _add_field name, :u64, 8, count
    end
    alias :ulong :u64

    def s64 name, count = 1
      _add_field name, :s64, 8, count
    end
    alias :i64 :s64
    alias :long :s64

    def f32 name, count = 1
      _add_field name, :f32, 4, count
    end
    alias :float32 :f32
    alias :float :f32

    def f64 name, count = 1
      _add_field name, :f64, 8, count
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
            "#{name || 'BStruct'}[#{@size}, #{@fields.length}]"
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
                buf = ::BStruct._check_to_scalar_buf(arg, field.type, field.count)
                @buffer.copy(buf, field.offset, field.count*field.size)
              end
            else
              if field.count == 1
                @buffer.copy(arg.buffer, field.offset, field.size)
              else
                buf = ::BStruct._check_to_struct_buf(arg, field.type, field.count)
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
                  buf = ::BStruct._check_to_scalar_buf(value, :#{field.type}, #{field.count})
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
                  buf = ::BStruct._check_to_struct_buf(arg, self.class.fields[:#{name}].type, #{field.count})
                  @buffer.copy(buf, #{field.offset}, #{field.count*field.size})
                end
              RUBY
            end
          end
        end
      end
    end

    private

      def _add_field(name, type, size, count)
        type = type.to_s.upcase.to_sym if big_endian?
        @fields[name] = Field.new(size:, type:, offset: @offset, count:)
        @offset += size*count
      end

      def _add_struct_field(name, type, count)
        @fields[name] = Field.new(size: type.size, type:, offset: @offset, count:)
        @offset += type.size*count
      end
      
  end
end
