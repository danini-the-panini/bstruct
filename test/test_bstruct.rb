# frozen_string_literal: true

require "test_helper"

class TestBStruct < Minitest::Test
  Foo = BStruct.define do
    long :id
    float :amount
    __ 2
    int :count
  end

  Bar = BStruct.define do
    long :id
    struct Foo, :foo
  end

  Vec = BStruct.define do
    float :e, 3
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

    foos = Foo[3].new(
      Foo.new(10, 1.0, 100),
      Foo.new(20, 2.0, 200),
      Foo.new(30, 3.0, 300)
    )
    assert_equal 3, foos.length
    assert_equal 10, foos[0].id
    assert_equal 20, foos[1].id
    assert_equal 30, foos[2].id
  end

  def test_array_member
    v = Vec.new([1.0, 2.0, 3.0])
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
  end

end
