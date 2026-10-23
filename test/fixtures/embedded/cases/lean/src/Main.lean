namespace Outer
namespace Inner
/-
@zil target=self
self#requires@assumption:natural_number.
module#located_in@file.
self#in@namespace.
project#owns@self.
revision#of@self.
declaration_kind#of@self.
source_span#of@self.
self#alias@my-self.
self#alias@self-two.
self#alias@p:a.self.b.
self#alias@a:self:b.
self#alias@a_self.
self#alias@file.
@endzil
-/
theorem identity (n : Nat) : n = n := rfl
end Inner
/- @zil target=custom:thing
custom:thing#kind@explicit.
@endzil -/
def Outer.qualified : Nat := 1
/-
@zil
self#kind@structure.
@endzil
-/
structure Point where
  x : Nat
end Outer
-- the block below follows a closed namespace
/-
@zil
self#kind@global.
@endzil
-/
opaque Standalone : Nat
/-
@zil
self#kind@dotted.
@endzil
-/
class Foo.Bar where
  v : Nat
