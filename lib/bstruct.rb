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

  def initialize(buffer = IO::Buffer.new(self.class.size))
    @buffer = buffer
  end

  def self.[](count)
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

  class Array
    include Enumerable

    attr_reader :buffer

    def initialize(type, count, buffer = IO::Buffer.new(type.size*count), &)
      @type = type
      @count = count
      @buffer = buffer
      if block_given?
        count.times do |i|
          buffer.copy(yield(i).buffer, i*type.size, type.size)
        end
      end
    end

    def self.[](type, count)
      Class.new(Array) do
        @type = type
        @count = count

        class << self
          def type = @type
          def count = @count

          def to_s
            "BStruct::Array[#{type}, #{count}]"
          end
          alias :inspect :to_s
        end

        def initialize(*args)
          case args.length
          when 0 then super(self.class.type, self.class.count)
          when 1
            arg = args.first
            case arg
            when IO::Buffer then super(self.class.type, self.class.count, arg)
            when Array then super(self.class.type, self.class.count, arg.buffer)
            when ::Array
              if arg.length != self.class.count
                raise ::ArgumentError, "array length mismatch (given #{arg.length}, expected #{self.class.count})"
              end
              super(self.class.type, self.class.count) { arg[it] }
            end
          when self.class.count then super(self.class.type, self.class.count) { args[it] }
          else raise ::ArgumentError, "wrong number of arguments (given #{args.length}, expected 0, 1, 2, or #{self.class.count})"
          end
        end
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

    def [](i, s = nil)
      if s
        # TODO: handle negative size
        Array.new(@type, s, @buffer.slice(i*@type.size, s*@type.size))
      elsif i.is_a?(Range)
        self[i, i.size]
      else
        @type.new(@buffer.slice(i*@type.size, @type.size))
      end
    end

    def []=(*args)
      case args.length
      when 2
        i, v = args
        if i.is_a?(Range)
          self[i.begin, i.size] = v
        else
          @buffer.copy(v.buffer, i*@type.size, @type.size)
        end
      when 3
        i, s, v = args
        @buffer.copy(v, i*@size, s*@size)
      else raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 2-3)"
      end
    end
  end

  class ScalarArray
    include Enumerable

    attr_reader :buffer

    def initialize(type, count, buffer = IO::Buffer.new(SIZEOF[type]*count), &)
      @type = type
      @size = SIZEOF[type]
      @buffer = buffer
      if block_given?
        count.times do |i|
          buffer.set_value(type, i*@size, yield(i))
        end
      end
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

    def [](i, s = nil)
      if s
        # TODO: handle negative size
        ScalarArray.new(@type, @size, s, @buffer.slice(i*@size, s*@size))
      elsif i.is_a?(Range)
        self[i.begin, i.size]
      else
        @buffer.get_value(@type, i*@size)
      end
    end

    def []=(*args)
      case args.length
      when 2
        i, v = args
        if i.is_a?(Range)
          self[i.begin, i.size] = v
        else
          @buffer.set_value(@type, i*@size, v)
        end
      when 3
        i, s, v = args
        @buffer.copy(v, i*@size, s*@size)
      else raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 2-3)"
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

    def little_endian?
      @endianness == :little
    end
    alias :little? :little_endian?

    def big_endian?
      @endianness == :big
    end
    alias :big? :big_endian?

    def u8 name, count = 1
      _add_field name, :u8, 1, count
    end
    alias :ubyte :u8
    alias :uchar :u8

    def s8 name, count = 1
      _add_field name, :s8, 1, count
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
                arg = ::BStruct::ScalarArray.new(field.type, field.count) { arg[it] } unless arg.is_a?(ScalarArray)
                # TODO: check size
                @buffer.copy(arg.buffer, field.offset, field.count*field.size)
              end
            else
              if field.count == 1
                @buffer.copy(arg.buffer, field.offset, field.size)
              else
                arg = ::BStruct::Array.new(field.type, field.count) { arg[it] } unless arg.is_a?(ScalarArray)
                # TODO: check size
                @buffer.copy(arg.buffer, field.offset, field.count*field.size)
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
              class_eval <<-RUBY
                def #{name}
                  @buffer.get_value(:#{field.type}, #{field.offset})
                end
                def #{name}=(value)
                  @buffer.set_value(:#{field.type}, #{field.offset}, value)
                end
              RUBY
            else
              class_eval <<-RUBY
                def #{name}
                  ScalarArray.new(:#{field.type}, #{field.count}, @buffer.slice(#{field.offset}, #{field.count*field.size}))
                end
                def #{name}=(value)
                  buf = case value
                  when ::IO::Buffer then value
                  when ::BStruct::ScalarArray then value.buffer
                  else
                    ary = value.to_ary
                    ::BStruct::ScalarArray.new(:#{field.type}, #{field.count}) { ary[it] }.buffer
                  end
                  @buffer.copy(buf, #{field.offset}, #{field.count*field.size})
                end
              RUBY
            end
          else
            if field.count == 1
              class_eval <<-RUBY
                def #{name}
                  self.class.fields[:#{name}].type.new(@buffer.slice(#{field.offset}, #{field.size}))
                end
                def #{name}=(value)
                  @buffer.copy(value.buffer, #{field.offset}, #{field.size})
                end
              RUBY
            else
              class_eval <<-RUBY
                def #{name}
                  ::BStruct::Array.new(self.class.fields[:#{name}], #{field.count}, @buffer.slice(#{field.offset}, #{field.count*field.size}))
                end
                def #{name}=(value)
                  buf = case value
                  when ::IO::Buffer then value
                  when ::BStruct::Array then value.buffer
                  else
                    ary = value.to_ary
                    ::BStruct::Array.new(self.class.fields[:#{name}], #{field.count}) { ary[it] }.buffer
                  end
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
