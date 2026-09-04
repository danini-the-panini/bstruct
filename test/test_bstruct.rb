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

  Baz = BStruct.define do
    long :id
    struct Foo[2], :foos
  end

  Vec = BStruct.define do
    float :e, 3
  end

  Color = BStruct.define do
    float :r
    float :g
    float :b
  end

  Mat = BStruct.define do
    float :e, 9
  end

  Foople = BStruct::Tuple(:long, :float, nil, nil, :u8)
  Barple = BStruct::Tuple(:long, 3, Foople)
  Arrayple = BStruct::Tuple(:long, BStruct::Int32[3], Foople[2])

  KitchenSink = BStruct.define do
    long :id
    float :floats, 3
    field BStruct::Int32, :int
    __ 3
    array BStruct::Int32[3][2], :ints
    struct Bar, :bar
    struct Foo[2], :foos
    tuple Barple, :barple
    tuple Foople[2], :fooples
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

  def test_tuple
    foo = Foople.new(1234, 2.0, 123)
    assert_equal 1234, foo[0]
    assert_equal 2.0, foo[1]
    assert_equal 123, foo[2]

    assert_equal([1234, 2.0, 123], foo.to_a)

    foo[0] = 2345
    foo[1] = 3.0
    foo[2] = 234
    assert_equal 2345, foo[0]
    assert_equal 3.0, foo[1]
    assert_equal 234, foo[2]
  end

  def test_nested_struct
    foo = Foo.new(12, 1.0, 3)
    bar = Bar.new(123, foo)
    assert_equal 12, bar.foo.id
    assert_equal foo, bar.foo

    bar.foo.id = 24
    assert_equal 24, bar.foo.id

    bar.foo = Foo.new(36, 2.0, 7)
    assert_equal 36, bar.foo.id
  end

  def test_nested_tuple
    foo = Foople.new(12, 1.0, 3)
    bar = Barple.new(1234, foo)

    assert_equal 12, bar[1][0]
    assert_equal foo, bar[1]

    assert_equal([1234, foo], bar.to_a)

    bar[1][0] = 24
    assert_equal 24, bar[1][0]
  end

  def test_array
    foos = Foo[34].new
    assert_equal 34, foos.length

    foos[12].id = 789
    assert_equal 789, foos[12].id

    foos = Foo[].new(
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
      Foo[].new(Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3)),
      Foo[2].new(Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3))
    )
    assert_equal(
      [Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3)],
      Foo[2].new(Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3))
    )
    assert_equal(
      Foo[].new(Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3)),
      Foo[Foo.new(1, 1.0, 2), Foo.new(2, 2.0, 3)]
    )
  end

  def test_array_of_tuples
    foos = Foople[34].new
    assert_equal 34, foos.length

    foos[12][0] = 789
    assert_equal 789, foos[12][0]

    foos = Foople[].new(
      Foople.new(10, 1.0, 100),
      Foople.new(20, 2.0, 200),
      Foople.new(30, 3.0, 300),
      Foople.new(40, 4.0, 400),
      Foople.new(50, 5.0, 500)
    )
    assert_equal 5, foos.length
    assert_equal 10, foos[0][0]
    assert_equal 20, foos[1][0]
    assert_equal 30, foos[2][0]
    assert_equal 40, foos[3][0]
    assert_equal 50, foos[4][0]

    assert_equal(50, foos[-1][0])
    assert_equal([20, 30, 40], foos[1, 3].map(&:first))
    assert_equal([20, 30, 40], foos[1..3].map(&:first))
    assert_equal([20, 30], foos[1...3].map(&:first))
    assert_equal([20, 30, 40], foos[1, 3].map(&:first))
    assert_equal([30, 40], foos[-3, 2].map(&:first))
    assert_equal([30, 40, 50], foos[-3..-1].map(&:first))

    assert_equal(
      Foople[].new(Foople.new(1, 1.0, 2), Foople.new(2, 2.0, 3)),
      Foople[2].new(Foople.new(1, 1.0, 2), Foople.new(2, 2.0, 3))
    )
    assert_equal(
      [Foople.new(1, 1.0, 2), Foople.new(2, 2.0, 3)],
      Foople[2].new(Foople.new(1, 1.0, 2), Foople.new(2, 2.0, 3))
    )
    assert_equal(
      Foople[].new(Foople.new(1, 1.0, 2), Foople.new(2, 2.0, 3)),
      Foople[Foople.new(1, 1.0, 2), Foople.new(2, 2.0, 3)]
    )
  end

  def test_array_of_arrays
    a = Vec[2][2].new(
      [Vec.new([1.0, 2.0, 3.0]), Vec.new([2.0, 3.0, 4.0])],
      [Vec.new([3.0, 4.0, 5.0]), Vec.new([4.0, 5.0, 6.0])]
    )

    assert_equal([Vec.new([1.0, 2.0, 3.0]), Vec.new([2.0, 3.0, 4.0])], a[0].to_a)
    assert_equal([Vec.new([3.0, 4.0, 5.0]), Vec.new([2.0, 4.0, 5.0])], a[1].to_a)
    assert_equal(Vec.new([1.0, 2.0, 3.0]), a[0][0])
    assert_equal(Vec.new([2.0, 3.0, 4.0]), a[0][1])
    assert_equal(Vec.new([3.0, 4.0, 5.0]), a[1][0])
    assert_equal(Vec.new([4.0, 5.0, 6.0]), a[1][1])

    a = Vec[2][].new(
      [Vec.new([1.0, 2.0, 3.0]), Vec.new([2.0, 3.0, 4.0])],
      [Vec.new([3.0, 4.0, 5.0]), Vec.new([4.0, 5.0, 6.0])]
    )

    assert_equal([Vec.new([1.0, 2.0, 3.0]), Vec.new([2.0, 3.0, 4.0])], a[0].to_a)
    assert_equal([Vec.new([3.0, 4.0, 5.0]), Vec.new([2.0, 4.0, 5.0])], a[1].to_a)
    assert_equal(Vec.new([1.0, 2.0, 3.0]), a[0][0])
    assert_equal(Vec.new([2.0, 3.0, 4.0]), a[0][1])
    assert_equal(Vec.new([3.0, 4.0, 5.0]), a[1][0])
    assert_equal(Vec.new([4.0, 5.0, 6.0]), a[1][1])

    a = Vec[][2].new(
      [Vec.new([1.0, 2.0, 3.0]), Vec.new([2.0, 3.0, 4.0])],
      [Vec.new([3.0, 4.0, 5.0]), Vec.new([4.0, 5.0, 6.0])]
    )

    assert_equal([Vec.new([1.0, 2.0, 3.0]), Vec.new([2.0, 3.0, 4.0])], a[0].to_a)
    assert_equal([Vec.new([3.0, 4.0, 5.0]), Vec.new([2.0, 4.0, 5.0])], a[1].to_a)
    assert_equal(Vec.new([1.0, 2.0, 3.0]), a[0][0])
    assert_equal(Vec.new([2.0, 3.0, 4.0]), a[0][1])
    assert_equal(Vec.new([3.0, 4.0, 5.0]), a[1][0])
    assert_equal(Vec.new([4.0, 5.0, 6.0]), a[1][1])

    a = Vec[][].new(
      [Vec.new([1.0, 2.0, 3.0]), Vec.new([2.0, 3.0, 4.0])],
      [Vec.new([3.0, 4.0, 5.0]), Vec.new([4.0, 5.0, 6.0])]
    )

    assert_equal([Vec.new([1.0, 2.0, 3.0]), Vec.new([2.0, 3.0, 4.0])], a[0].to_a)
    assert_equal([Vec.new([3.0, 4.0, 5.0]), Vec.new([2.0, 4.0, 5.0])], a[1].to_a)
    assert_equal(Vec.new([1.0, 2.0, 3.0]), a[0][0])
    assert_equal(Vec.new([2.0, 3.0, 4.0]), a[0][1])
    assert_equal(Vec.new([3.0, 4.0, 5.0]), a[1][0])
    assert_equal(Vec.new([4.0, 5.0, 6.0]), a[1][1])

    a = Vec[2][2][2].new(
      [
        [Vec.new([1.0, 2.0, 3.0]), Vec.new([2.0, 3.0, 4.0])],
        [Vec.new([3.0, 4.0, 5.0]), Vec.new([4.0, 5.0, 6.0])]
      ],
      [
        [Vec.new([5.0, 6.0, 7.0]), Vec.new([6.0, 7.0, 8.0])],
        [Vec.new([7.0, 8.0, 9.0]), Vec.new([8.0, 9.0, 0.0])]
      ]
    )
    assert_equal([
      1.0, 2.0, 3.0, 2.0, 3.0, 4.0, 3.0, 4.0, 5.0, 4.0, 5.0, 6.0,
      5.0, 6.0, 7.0, 6.0, 7.0, 8.0, 7.0, 8.0, 9.0, 8.0, 9.0, 0.0
    ], a.cast(:float).to_a)
  end

  def test_array_of_scalar_arrays
    a = BStruct::Int32[3][2].new(
      [1,2,3],
      [2,3,4]
    )
    assert_equal([1,2,3], a[0].to_a)
    assert_equal([2,3,4], a[1].to_a)

    a = BStruct::Int32Array[2].new(
      [1,2,3],
      [2,3,4]
    )
    assert_equal([1,2,3], a[0].to_a)
    assert_equal([2,3,4], a[1].to_a)

    a = BStruct::Int32Array[].new(
      [1,2,3],
      [2,3,4]
    )
    assert_equal([1,2,3], a[0].to_a)
    assert_equal([2,3,4], a[1].to_a)

    a = BStruct::Int32Array[2][2].new(
      [
        [1,2,3],
        [2,3,4]
      ],
      [
        [3,4,5],
        [4,5,6]
      ]
    )
    assert_equal([1,2,3,2,3,4,3,4,5,4,5,6], a.cast(:i32).to_a)
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

  def test_array_tuple_member
    a = Arrayple.new(123, [1,2,3], [Foople.new(1, 1.0, 2), Foople.new(2, 2.0, 3)])
    assert_equal([1,2,3], a[1].to_a)
    assert_equal([Foople.new(1, 1.0, 2), Foople.new(2, 2.0, 3)], a[2].to_a)
    assert_equal(Foople.new(1, 1.0, 2), a[2][0])

    a = Arrayple.new(123, [1,2,3], [[1, 1.0, 2], [2, 2.0, 3]])
    assert_equal([1,2,3], a[1].to_a)
    assert_equal([Foople.new(1, 1.0, 2), Foople.new(2, 2.0, 3)], a[2].to_a)
    assert_equal(Foople.new(1, 1.0, 2), a[2][0])
  end

  def test_cast_struct
    v = Vec.new([1.0, 2.0, 3.0])
    c = v.cast(Color)
    assert_equal 1.0, c.r
    assert_equal 2.0, c.g
    assert_equal 3.0, c.b

    a = v.cast(BStruct::Float32Array)
    assert_equal 3, a.length
    assert_equal([1.0, 2.0, 3.0], a.to_a)

    a = v.cast(:f32)
    assert_equal 3, a.length
    assert_equal([1.0, 2.0, 3.0], a.to_a)

    m = Mat.new([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0])
    a = m.cast(Vec[])
    assert_equal 3, a.length
    assert_equal([1.0, 2.0, 3.0], a[0].e.to_a)
    assert_equal([4.0, 5.0, 6.0], a[1].e.to_a)
    assert_equal([7.0, 8.0, 9.0], a[2].e.to_a)
  end

  def test_cast_scalar_array
    a = BStruct::Uint8Array.new([12, 34, 56, 78])

    a16 = a.cast(BStruct::Int16Array)
    assert_equal 2, a16.count
    assert_equal([12+(34<<8), 56+(78<<8)], a16.to_a)

    a16 = a.cast(:i16)
    assert_equal 2, a16.count
    assert_equal([12+(34<<8), 56+(78<<8)], a16.to_a)

    a = BStruct::Float32Array.new([1.0, 2.0, 3.0])
    v = a.cast(Vec)
    assert_equal([1.0, 2.0, 3.0], v.e.to_a)

    c = a.cast(Color)
    assert_equal 1.0, c.r
    assert_equal 2.0, c.g
    assert_equal 3.0, c.b

    a = BStruct::Float32Array.new([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0])
    va = a.cast(Vec[])
    assert_equal 3, va.length
    assert_equal([1.0, 2.0, 3.0], va[0].e.to_a)
    assert_equal([4.0, 5.0, 6.0], va[1].e.to_a)
    assert_equal([7.0, 8.0, 9.0], va[2].e.to_a)
  end

  def test_cast_struct_array
    a = Vec[].new(
      Vec.new([1.0, 2.0, 3.0]),
      Vec.new([4.0, 5.0, 6.0]),
      Vec.new([7.0, 8.0, 9.0])
    )

    a2 = a.cast(BStruct::Float32Array)
    assert_equal 9, a2.length
    assert_equal([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], a2.to_a)

    a2 = a.cast(:f32)
    assert_equal 9, a2.length
    assert_equal([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], a2.to_a)

    m = a.cast(Mat)
    assert_equal([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], m.e.to_a)

    a2 = a.cast(Color[])
    assert_equal 3, a2.length
    assert_equal 1.0, a2[0].r; assert_equal 2.0, a2[0].g; assert_equal 3.0, a2[0].b;
    assert_equal 4.0, a2[1].r; assert_equal 5.0, a2[1].g; assert_equal 6.0, a2[1].b;
    assert_equal 7.0, a2[2].r; assert_equal 8.0, a2[2].g; assert_equal 9.0, a2[2].b;
  end

  def test_kitchen_sink
    k = KitchenSink.new(
      id: 12345,
      int: 987,
      floats: [1.0, 2.0, 3.0],
      bar: Bar.new(2345, Foo.new(345, 2.0, 7)),
      ints: [
        [2,3,4],
        [5,6,7]
      ],
      barple: [4567, [123, 3.0, 2]],
      foos: [Foo.new(111, 1.0, 3), Foo.new(222, 2.0, 4)],
      fooples: [
        [1111, 1.0, 5],
        [2222, 2.0, 6],
      ]
    )

    assert_equal 12345, k.id
    assert_equal 1.0, k.floats[0]
    assert_equal 987, k.int
    assert_equal 2345, k.bar.id
    assert_equal 345, k.bar.foo.id
    assert_equal 2, k.ints[0][0]
    assert_equal 5, k.ints[1][0]
    assert_equal 4567, k.barple[0]
    assert_equal 111, k.foos[0].id
    assert_equal 222, k.foos[1].id
    assert_equal 1111, k.fooples[0][0]
    assert_equal 2222, k.fooples[1][0]
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
