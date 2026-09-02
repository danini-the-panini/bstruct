# frozen_string_literal: true

require "test_helper"

class TestBStruct < Minitest::Test
  Foo = BStruct.define do
    long :id
    float :amount
    __
    __
    int :count
  end

  Bar = BStruct.define do
    long :id
    __ 3
    struct Foo, :foo
  end

  Vec = BStruct.define do
    float :e, 3
  end

  Mat = BStruct.define do
    float :e, 9
  end

  def test_that_it_has_a_version_number
    refute_nil ::BStruct::VERSION
  end

  def test_struct
    foo = Foo.new(id: 123456, count: 17, amount: 2.0)

    assert_equal 123456, foo.id
    assert_equal 2.0, foo.amount
    assert_equal 17, foo.count

    foo.id = 234567
    foo.amount = 3.0
    foo.count = 42

    assert_equal 234567, foo.id
    assert_equal 3.0, foo.amount
    assert_equal 42, foo.count

    assert_equal Foo.new(1, 1.0, 2), Foo.new(1, 1.0, 2)
  end

  def test_nested_struct
    foo = Foo.new(12, 1.0, 3)
    bar = Bar.new(123, foo)
    assert_equal 12, bar.foo.id

    bar.foo.id = 24
    assert_equal 24, bar.foo.id

    bar.foo = Foo.new(36, 2.0, 7)
    assert_equal 36, bar.foo.id
  end

  def test_array
    foos = Foo[34].new
    assert_equal 34, foos.length

    foos[12].id = 789
    assert_equal 789, foos[12].id

    foos = Foo[5].new(
      Foo.new(10, 1.0, 100),
      Foo.new(20, 2.0, 200),
      Foo.new(30, 3.0, 300),
      Foo.new(40, 4.0, 400),
      Foo.new(50, 5.0, 500)
    )
    assert_equal 5, foos.length
    assert_equal 10, foos[0].id
    assert_equal 20, foos[1].id
    assert_equal 30, foos[2].id
    assert_equal 40, foos[3].id
    assert_equal 50, foos[4].id

    assert_equal(50, foos[-1].id)
    assert_equal([20, 30, 40], foos[1, 3].map(&:id))
    assert_equal([20, 30, 40], foos[1..3].map(&:id))
    assert_equal([20, 30], foos[1...3].map(&:id))
    assert_equal([20, 30, 40], foos[1, 3].map(&:id))
    assert_equal([30, 40], foos[-3, 2].map(&:id))
    assert_equal([30, 40, 50], foos[-3..-1].map(&:id))

    assert_equal(
      Foo[2].new(Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3)),
      Foo[2].new(Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3))
    )
    assert_equal(
      [Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3)],
      Foo[2].new(Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3))
    )
  end

  def test_array_member
    v = Vec.new([1.0, 2.0, 3.0])
    assert_equal 3, v.e.length
    assert_equal 1.0, v.e[0]
    assert_equal 2.0, v.e[1]
    assert_equal 3.0, v.e[2]

    v.e = [2.0, 3.0, 4.0]
    assert_equal 2.0, v.e[0]
    assert_equal 3.0, v.e[1]
    assert_equal 4.0, v.e[2]

    v.e[0] = 3.0
    v.e[1] = 4.0
    v.e[2] = 5.0
    assert_equal 3.0, v.e[0]
    assert_equal 4.0, v.e[1]
    assert_equal 5.0, v.e[2]

    assert_equal(
      Vec.new([1.0, 2.0, 3.0]).e,
      Vec.new([1.0, 2.0, 3.0]).e,
    )

    assert_equal(
      [1.0, 2.0, 3.0],
      Vec.new([1.0, 2.0, 3.0]).e
    )

    m = Mat.new([
      1.0, 2.0, 3.0,
      4.0, 5.0, 6.0,
      7.0, 8.0, 9.0
    ])

    assert_equal(9.0, m.e[-1])
    assert_equal([4.0, 5.0, 6.0], m.e[3, 3].to_a)
    assert_equal([2.0, 3.0, 4.0], m.e[1..3].to_a)
    assert_equal([2.0, 3.0], m.e[1...3].to_a)
    assert_equal([2.0, 3.0, 4.0], m.e[1, 3].to_a)
    assert_equal([7.0, 8.0], m.e[-3, 2].to_a)
    assert_equal([7.0, 8.0, 9.0], m.e[-3..-1].to_a)
  end

  def test_uint8_array
    a = BStruct::Uint8Array.new(10)
    assert_equal 10, a.length

    a = BStruct::Uint8Array.new([4,5,255])
    assert_equal 3, a.length
    assert_equal 4, a[0]
    assert_equal 5, a[1]
    assert_equal 255, a[2]
  end

  def test_int8_array
    a = BStruct::Int8Array.new(10)
    assert_equal 10, a.length

    a = BStruct::Int8Array.new([-127,5,127])
    assert_equal 3, a.length
    assert_equal(-127, a[0])
    assert_equal(5, a[1])
    assert_equal(127, a[2])
  end

  def test_uint16_array
    a = BStruct::Uint16Array.new(10)
    assert_equal 10, a.length

    a = BStruct::Uint16Array.new([4,5,65535])
    assert_equal 3, a.length
    assert_equal 4, a[0]
    assert_equal 5, a[1]
    assert_equal 65535, a[2]
  end

  def test_int16_array
    a = BStruct::Int16Array.new(10)
    assert_equal 10, a.length

    a = BStruct::Int16Array.new([-32767,5,32767])
    assert_equal 3, a.length
    assert_equal(-32767, a[0])
    assert_equal(5, a[1])
    assert_equal(32767, a[2])
  end

  def test_uint32_array
    a = BStruct::Uint32Array.new(10)
    assert_equal 10, a.length

    a = BStruct::Uint32Array.new([4,5,2**32-1])
    assert_equal 3, a.length
    assert_equal 4, a[0]
    assert_equal 5, a[1]
    assert_equal 2**32-1, a[2]
  end

  def test_int32_array
    a = BStruct::Int32Array.new(10)
    assert_equal 10, a.length

    max = (2**32)/2
    a = BStruct::Int32Array.new([-max+1,5,max-1])
    assert_equal 3, a.length
    assert_equal(-max+1, a[0])
    assert_equal(5, a[1])
    assert_equal(max-1, a[2])
  end

  def test_uint64_array
    a = BStruct::Uint64Array.new(10)
    assert_equal 10, a.length

    a = BStruct::Uint64Array.new([4,5,2**64-1])
    assert_equal 3, a.length
    assert_equal 4, a[0]
    assert_equal 5, a[1]
    assert_equal 2**64-1, a[2]
  end

  def test_int64_array
    a = BStruct::Int64Array.new(10)
    assert_equal 10, a.length

    max = (2**64)/2
    a = BStruct::Int64Array.new([-max+1,5,max-1])
    assert_equal 3, a.length
    assert_equal(-max+1, a[0])
    assert_equal(5, a[1])
    assert_equal(max-1, a[2])
  end

  def test_float32_array
    a = BStruct::Float32Array.new(10)
    assert_equal 10, a.length

    a = BStruct::Float32Array.new([1.1920928955078125e-07, -Float::INFINITY, Float::INFINITY])
    assert_equal 3, a.length
    assert_equal(1.1920928955078125e-07, a[0])
    assert_equal(-Float::INFINITY, a[1])
    assert_equal(Float::INFINITY, a[2])
  end

  def test_float64_array
    a = BStruct::Float64Array.new(10)
    assert_equal 10, a.length

    a = BStruct::Float64Array.new([0.0.next_float, -Float::INFINITY, Float::INFINITY])
    assert_equal 3, a.length
    assert_equal(0.0.next_float, a[0])
    assert_equal(-Float::INFINITY, a[1])
    assert_equal(Float::INFINITY, a[2])
  end

end
