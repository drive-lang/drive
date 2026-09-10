require 'minitest/autorun'
require_relative '../backend/backend'
require_relative 'base_test'

class Composition_Test < Base_Test
	def test_union_viewer_has_read_permissions
		out = Backend.interp "
		@load 'examples/compositions.prog'
		v := Viewer()
		(v.can_view, v.can_list, v.user_type)"

		assert_equal [true, true, 'viewer'], out.values
	end

	def test_union_viewer_does_not_have_write_permissions
		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			v := Viewer()
			v.can_create"
		end
	end

	def test_union_editor_has_read_and_write_permissions
		out = Backend.interp "
		@load 'examples/compositions.prog'
		e := Editor()
		(e.can_view, e.can_list, e.can_create, e.can_update, e.can_delete, e.user_type)"

		assert_equal [true, true, true, true, true, 'editor'], out.values
	end

	def test_union_administrator_has_all_permissions
		out = Backend.interp "
		@load 'examples/compositions.prog'
		a := Administrator()
		(a.can_view, a.can_create, a.can_manage_users, a.user_type)"

		assert_equal [true, true, true, 'admin'], out.values
	end

	def test_removal_limited_editor_cannot_delete
		refute_raises Prog::Undeclared_Identifier do
			out = Backend.interp "
			@load 'examples/compositions.prog'
			l := Limited_Editor()
			(l.can_create, l.can_update, l.user_type)"
			assert_equal [true, true, 'limited_editor'], out.values
		end

		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			l := Limited_Editor()
			l.can_delete"
		end
	end

	def test_removal_read_only_admin_cannot_write
		refute_raises Prog::Undeclared_Identifier do
			out = Backend.interp "
			@load 'examples/compositions.prog'
			r := Read_Only_Admin()
			(r.can_manage_users, r.can_view, r.user_type)"
			assert_equal [true, true, 'read_only_admin'], out.values
		end

		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			r := Read_Only_Admin()
			r.can_create"
		end

		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			r := Read_Only_Admin()
			r.can_delete"
		end
	end

	def test_intersection_auditor_has_only_shared_permissions
		refute_raises Prog::Undeclared_Identifier do
			out = Backend.interp "
			@load 'examples/compositions.prog'
			a := Auditor()
			(a.can_view_logs, a.user_type)"
			assert_equal [true, 'auditor'], out.values
		end

		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			a := Auditor()
			a.can_manage_users"
		end

		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			a := Auditor()
			a.can_export_data"
		end
	end

	def test_symmetric_difference_specialist_has_unique_permissions
		refute_raises Prog::Undeclared_Identifier do
			out = Backend.interp "
			@load 'examples/compositions.prog'
			s := Specialist()
			(s.can_manage_users, s.can_configure_system, s.can_export_data, s.user_type)"
			assert_equal [true, true, true, 'specialist'], out.values
		end

		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			s := Specialist()
			s.can_view_logs"
		end
	end

	def test_vehicle_sedan_has_basic_features
		out = Backend.interp "
		@load 'examples/compositions.prog'
		s := Sedan()
		(s.has_engine, s.has_wheels, s.model)"

		assert_equal [true, true, 'sedan'], out.values
	end

	def test_vehicle_luxury_sedan_has_luxury_features
		out = Backend.interp "
		@load 'examples/compositions.prog'
		l := Luxury_Sedan()
		(l.has_engine, l.has_leather_seats, l.has_sunroof, l.model)"

		assert_equal [true, true, true, 'luxury_sedan'], out.values
	end

	def test_vehicle_electric_car_has_no_traditional_engine
		out = Backend.interp "
		@load 'examples/compositions.prog'
		e := Electric_Car()
		(e.has_wheels, e.has_battery, e.has_engine, e.model)"

		assert_equal [true, true, false, 'electric'], out.values
	end

	def test_vehicle_luxury_electric_combines_features
		out = Backend.interp "
		@load 'examples/compositions.prog'
		l := Luxury_Electric()
		(l.has_wheels, l.has_leather_seats, l.has_battery, l.has_engine, l.model)"

		assert_equal [true, true, true, false, 'luxury_electric'], out.values
	end

	def test_api_public_user_response_has_only_shared_members
		refute_raises Prog::Undeclared_Identifier do
			out = Backend.interp "
			@load 'examples/compositions.prog'
			p := Public_User_Response()
			(p.status, p.user_id, p.username, p.response_type)"
			assert_equal [200, 0, '', 'public'], out.values
		end

		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			p := Public_User_Response()
			p.email"
		end

		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			p := Public_User_Response()
			p.avatar_url"
		end
	end

	def test_api_private_user_response_has_all_members
		out = Backend.interp "
		@load 'examples/compositions.prog'
		p := Private_User_Response()
		(p.status, p.user_id, p.username, p.email, p.response_type)"

		assert_equal [200, 0, '', '', 'private'], out.values
	end

	def test_api_limited_user_response_removes_private_members
		refute_raises Prog::Undeclared_Identifier do
			out = Backend.interp "
			@load 'examples/compositions.prog'
			l := Limited_User_Response()
			(l.user_id, l.username, l.response_type)"
			assert_equal [0, '', 'limited'], out.values
		end

		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			@load 'examples/compositions.prog'
			l := Limited_User_Response()
			l.email"
		end
	end

	# A bare composition (`| Compo`) only means anything as a direct top-level item of a type's own body -- nested anywhere else, it used to silently merge into whatever scope happened to be on top of the stack (the *enclosing* type, if written inside one) and return some incidental leftover value.

	# `x := |Compo` (and chains, `y := |This ^ That`) -- a composition with no left operand, used as a
	# value (#parse_bare_composition_chain / #interp_anonymous_composition), not merged into whatever
	# scope happens to be on top of the stack. Works anywhere, same as the existing two-name chain form
	# (`x := Base | Compo`) -- not restricted to type bodies.

	def test_bare_composition_assigned_to_a_local_builds_a_scoped_value
		out = Backend.interp "
		Compo { a := 1 }
		x := |Compo
		y := x()
		y.a"
		assert_equal 1, out
	end

	def test_bare_composition_chain_assigned_to_a_local_works
		out = Backend.interp "
		This { a := 1, shared := 'this' }
		That { b := 2, shared := 'that' }
		z := |This ^ That
		w := z()
		(w.a, w.b)"
		assert_equal [1, 2], out.values
	end

	def test_bare_composition_assigned_to_a_local_reflects_in_its_composed_type_set
		out = Backend.interp "
		Compo { a := 1 }
		x := |Compo
		y := x()
		(y =>= Compo, y === Compo)"
		assert_equal [true, true], out.values
	end

	# Declared as a member inside a type body, it scopes to that member -- Compo does not splat into the
	# enclosing Type's own declarations the way a bare `| Compo` *statement* (no `:=`) would.
	def test_bare_composition_assigned_inside_a_type_body_does_not_leak_into_the_enclosing_type
		assert_raises Prog::Undeclared_Identifier do
			Backend.interp "
			Compo { a := 99 }
			Type { x := |Compo }
			t := Type()
			t.a"
		end
	end

	def test_bare_composition_assigned_inside_a_type_body_is_reachable_through_its_member
		out = Backend.interp "
		Compo { a := 99 }
		Type { x := |Compo }
		t := Type()
		i := t.x()
		i.a"
		assert_equal 99, out
	end

	def test_bare_composition_as_a_standalone_statement_raises
		assert_raises Prog::Composition_Outside_Type_Declaration do
			Backend.interp "
			Compo { a := 1 }
			|Compo"
		end
	end

	# The real, working way to get a scoped/local composed type -- a genuine chain (`X | Y`), not a bare
	# prefix (`|Y`) -- still works: #interp_anonymous_composition builds a fresh, unnamed Type from it.
	def test_composition_chain_assigned_to_a_local_still_works
		out = Backend.interp "
		Base {}
		Compo { a := 1 }
		x := Base | Compo
		y := x()
		y.a"
		assert_equal 1, out
	end

	# Composing as a bare statement inside a type's own `{}` body (not just in the header, before it)
	# is a distinct, legitimate form -- must keep working after the fix above.
	def test_composition_as_a_bare_statement_inside_a_type_body_still_works
		out = Backend.interp "
		Number {}
		Float { | Number }
		Float =>= Number"
		assert_equal true, out
	end

	# A composed-in Array/Dictionary/Instance-valued member used to be copied by *reference* -- since
	# composition re-runs for every instance built (not just once, at the composing type's own
	# declaration), every instance of every composing type ended up sharing the exact same mutable
	# object. #dup_composed_value fixes this by duping a mutable value when it's copied in.

	def test_composed_array_member_is_independent_per_instance
		out = Backend.interp "
		Has_Items { items := [] }
		A | Has_Items {}
		a := A()
		b := A()
		a.items.push('a-item')
		b.items.push('b-item')
		(a.items, b.items)"
		assert_equal [['a-item'], ['b-item']], out.values.map(&:values)
	end

	def test_composed_dictionary_member_is_independent_per_instance
		out = Backend.interp "
		Has_Store { store := {} }
		A | Has_Store {}
		a := A()
		b := A()
		a.store[:x] = 1
		b.store[:x] = 2
		(a.store[:x], b.store[:x])"
		assert_equal [1, 2], out.values
	end

	# Method sharing via composition (the whole point of `|`) must be unaffected -- Prog::Func isn't a
	# Prog::Instance, so #dup_composed_value leaves it untouched.
	def test_composed_method_is_still_shared_and_callable
		out = Backend.interp "
		Greeter { greet ( name; \"Hello, `name`!\" ) }
		My_Type | Greeter {}
		My_Type().greet('World')"
		assert_equal 'Hello, World!', out
	end

	# Symmetric difference (`^`) copies in the operand's unique keys the same way `|` does -- same fix applies there too.
	def test_composed_array_member_via_symmetric_difference_is_independent_per_instance
		out = Backend.interp "
		Abc { }
		Def { items := [] }
		S | Abc ^ Def {}
		a := S()
		b := S()
		a.items.push('a-item')
		b.items.push('b-item')
		(a.items, b.items)"
		assert_equal [['a-item'], ['b-item']], out.values.map(&:values)
	end
end
