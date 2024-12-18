require "test_helper"

class RBS::Resolver::ConstantResolverTest < Test::Unit::TestCase
  include TestHelper
  include RBS

  def test_table
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
module M1
  class C1
    D: Integer

    ::M1::D: String
  end
end
EOF

      manager.build do |env|
        table = Resolver::ConstantResolver::Table.new(env)

        assert table.toplevel.key?(:M1)

        table.children(RBS::TypeName.parse("::M1")).tap do |children|
          assert_equal [:C1, :D], children.keys.sort

          assert_equal RBS::TypeName.parse("::M1::C1"), children[:C1].name
          assert_equal parse_type("singleton(::M1::C1)"), children[:C1].type

          assert_equal RBS::TypeName.parse("::M1::D"), children[:D].name
          assert_equal parse_type("::String"), children[:D].type
        end

        assert_equal [:D], table.children(RBS::TypeName.parse("::M1::C1")).keys

        assert_nil table.children(RBS::TypeName.parse("::M1::C1::D"))
      end
    end
  end

  def test_name_to_constant
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
Name: String
EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(:Object, context: nil).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Object", constant.name.to_s
          assert_equal "singleton(::Object)", constant.type.to_s
        end

        resolver.resolve(:Name, context: nil).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Name", constant.name.to_s
          assert_equal "::String", constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_context
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
end

Name: "::Name"
Foo::Name: "Foo::Name"
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)
        Namespace.parse("::Foo")

        resolver.resolve(:Name, context: [nil, RBS::TypeName.parse("::Foo")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Foo::Name", constant.name.to_s
          assert_equal '"Foo::Name"', constant.type.to_s
        end

        resolver.resolve(:Name, context: nil).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Name", constant.name.to_s
          assert_equal '"::Name"', constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_context_self
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
end

class Foo::Bar
end

class Bar
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(:Bar, context: [nil, RBS::TypeName.parse("::Foo")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Foo::Bar", constant.name.to_s
        end

        resolver.resolve(:Bar, context: [nil, RBS::TypeName.parse("::Foo::Bar")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Foo::Bar", constant.name.to_s
        end
      end
    end
  end

  def test_reference_constant_nested_context
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
end

class Foo::Bar
end

class Foo::Bar::Baz
end

Foo::Bar::X: "Foo::Bar::X"
X: "::X"
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(:X, context: [[nil, RBS::TypeName.parse("::Foo")], RBS::TypeName.parse("::Foo::Bar::Baz")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::X", constant.name.to_s
          assert_equal '"::X"', constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Parent
end

Parent::MAX: 10000

class Child < Parent
  include Mix
end

module Mix
end

Mix::MIN: 0
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(:MAX, context: [nil, RBS::TypeName.parse("::Child")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Parent::MAX", constant.name.to_s
          assert_equal "10000", constant.type.to_s
        end

        resolver.resolve(:MIN, context: [nil, RBS::TypeName.parse("::Child")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Mix::MIN", constant.name.to_s
          assert_equal '0', constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit_object
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Object
  FOO: String
end

class C
end

module M
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(:FOO, context: nil).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Object::FOO", constant.name.to_s
        end

        resolver.resolve(:FOO, context: [nil, RBS::TypeName.parse("::C")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Object::FOO", constant.name.to_s
        end

        resolver.resolve(:FOO, context: [nil, RBS::TypeName.parse("::M")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Object::FOO", constant.name.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit_module
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Set
end

module Baz
end
Baz::X: Integer

module Foo
end

module Foo::Bar
  include Baz
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(:Set, context: [[nil, RBS::TypeName.parse("::Foo")], RBS::TypeName.parse("::Foo::Bar")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Set", constant.name.to_s
          assert_equal 'singleton(::Set)', constant.type.to_s
        end

        resolver.resolve(:X, context: [[nil, RBS::TypeName.parse("::Foo")], RBS::TypeName.parse("::Foo::Bar")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Baz::X", constant.name.to_s
          assert_equal '::Integer', constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit_module_self
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
module Foo : _Bar, String
end

interface _Bar
end

BAZ: String
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(:BAZ, context: [nil, RBS::TypeName.parse("::Foo")]).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::BAZ", constant.name.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit2
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
end

Foo::Name: "Foo::Name"
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(
          :Foo,
          context: [nil, RBS::TypeName.parse("::Foo")],
        ).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Foo", constant.name.to_s
          assert_equal 'singleton(::Foo)', constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit3
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Stuff
end

ONE: 1
Object::TWO: 2
Kernel::THREE: 3
BasicObject::FOUR: 4
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve_child(RBS::TypeName.parse("::Stuff"), :ONE).tap do |constant|
          assert_nil constant
        end

        resolver.resolve_child(RBS::TypeName.parse("::Stuff"), :TWO).tap do |constant|
          assert_nil constant
        end

        resolver.resolve_child(RBS::TypeName.parse("::Stuff"), :THREE).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Kernel::THREE", constant.name.to_s
          assert_equal "3", constant.type.to_s
        end

        resolver.resolve_child(RBS::TypeName.parse("::Stuff"), :FOUR).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::BasicObject::FOUR", constant.name.to_s
          assert_equal "4", constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_toplevel
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
CONST: Integer

class Foo
  CONST: String
end

class Bar < Foo
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(:CONST, context: [nil, RBS::TypeName.parse("::Bar")]).tap do |constant|
          assert_equal "::Foo::CONST", constant.name.to_s
        end
      end
    end
  end

  def test_reference_constant_toplevel2
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
CONST: Integer

class BasicObject
  CONST: String
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.resolve(:CONST, context: [nil, RBS::TypeName.parse("::String")]).tap do |constant|
          assert_equal "::CONST", constant.name.to_s
        end
      end
    end
  end

  def test_alias_constants_toplevel
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<~EOF
        class Hello = Object
      EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.constants(nil).tap do |constants|
          assert constants.key?(:Hello)
        end
      end
    end
  end

  def test_alias_constants_context
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<~EOF
        module M
          class Hello = Object

          module M2
          end
        end
      EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.constants([[nil, RBS::TypeName.parse("::M")], RBS::TypeName.parse("::M::M2")]).tap do |constants|
          assert constants.key?(:Hello)
        end
      end
    end
  end

  def test_alias_constants_aliased_context
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<~EOF
        module M
          module M2
          end
        end

        module M3 = M
      EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        resolver = Resolver::ConstantResolver.new(builder: builder)

        resolver.constants([nil, RBS::TypeName.parse("::M3")]).tap do |constants|
          assert constants.key?(:M2)
        end

        resolver.constants([nil, RBS::TypeName.parse("::M3")]).tap do |constants|
          assert constants.key?(:M3)
        end
      end
    end
  end
end
