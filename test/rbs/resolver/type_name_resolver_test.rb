require "test_helper"

class RBS::Resolver::TypeNameResolverTest < Test::Unit::TestCase
  include TestHelper
  include RBS

  def test_resolve
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
  class Bar
    class Baz
    end
  end
end

class Bar
end
EOF
      manager.build do |env|
        resolver = Resolver::TypeNameResolver.new(env)

        assert_equal type_name("::Foo"),
                     resolver.resolve(type_name("::Foo"), context: nil)

        assert_equal type_name("::Foo"),
                     resolver.resolve(type_name("Foo"), context: nil)
        assert_equal type_name("::Bar"),
                     resolver.resolve(type_name("Bar"), context: nil)
        assert_nil resolver.resolve(type_name("Baz"), context: nil)

        assert_equal type_name("::Foo"),
                     resolver.resolve(type_name("Foo"), context: [nil, RBS::TypeName.parse("::Foo")])
        assert_equal type_name("::Foo::Bar"),
                     resolver.resolve(type_name("Bar"), context: [nil, RBS::TypeName.parse("::Foo")])
        assert_equal type_name("::Foo::Bar::Baz"),
                     resolver.resolve(type_name("Bar::Baz"), context: [nil, RBS::TypeName.parse("::Foo")])

        assert_equal type_name("::Bar"),
                     resolver.resolve(type_name("Bar"), context: [nil, RBS::TypeName.parse("::Foo::Bar::Baz")])
      end
    end
  end

  def test_resolve_failure
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
  class Foo
  end

  class Bar
  end
end
EOF
      manager.build do |env|
        resolver = Resolver::TypeNameResolver.new(env)

        assert_nil resolver.resolve(type_name("Foo::Bar"), context: [[nil, RBS::TypeName.parse("::Foo")], RBS::TypeName.parse("::Foo::Foo")])
      end
    end
  end


  def test_duplicated_resolve
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class X
  class X
  end
end
EOF
      manager.build do |env|
        resolver = Resolver::TypeNameResolver.new(env)

        assert_equal type_name("::X::X"),
                     resolver.resolve(type_name("X"), context: [nil, RBS::TypeName.parse("::X")])
      end
    end
  end

  def test_top_resolve
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class X
  class Y
    class Z
    end

    class Y
    end
  end
end
EOF
      manager.build do |env|
        resolver = Resolver::TypeNameResolver.new(env)

        assert_equal type_name("::X::Y::Y"),
                     resolver.resolve(type_name("Y"),
                                      context: [[nil, RBS::TypeName.parse("::X::Y")], RBS::TypeName.parse("::X::Y::Z")])

        assert_nil resolver.resolve(type_name("Y::Z"),
                                    context: [[nil, RBS::TypeName.parse("::X::Y")], RBS::TypeName.parse("::X::Y::Z")])

        assert_equal type_name("::X::Y::Z"),
                     resolver.resolve(type_name("Y::Z"),
                                      context: [[nil, RBS::TypeName.parse("::X")], RBS::TypeName.parse("::X::Y::Z")])
      end
    end
  end

  def test_object_name
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class MyObject
  type name2 = ::Symbol
end

type MyObject::name = ::String
EOF
      manager.build do |env|
        resolver = Resolver::TypeNameResolver.new(env)

        assert_equal type_name("::MyObject::name"),
                     resolver.resolve(type_name("name"), context: [nil, RBS::TypeName.parse("::MyObject")])
        assert_equal type_name("::MyObject::name2"),
                     resolver.resolve(type_name("name2"), context: [nil, RBS::TypeName.parse("::MyObject")])
      end
    end
  end

  def test_module_alias
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class MyObject
  type name2 = ::Symbol
end

class Alias = MyObject

type foo = Alias::name2
EOF
      manager.build do |env|
        resolver = Resolver::TypeNameResolver.new(env)

        assert_equal type_name("::Alias::name2"),
                     resolver.resolve(type_name("Alias::name2"), context: nil)
      end
    end
  end
end
