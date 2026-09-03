require 'minitest/autorun'
require_relative '../src/tape'
require_relative 'base_test'

class Composition_Test < Base_Test
	def test_union_viewer_has_read_permissions
		out = Tape.interp "
		@load 'examples/composition_examples.tape'
		v := Viewer()
		(v.can_view, v.can_list, v.user_type)"

		assert_equal [true, true, 'viewer'], out.values
	end

	def test_union_viewer_does_not_have_write_permissions
		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			v := Viewer()
			v.can_create"
		end
	end

	def test_union_editor_has_read_and_write_permissions
		out = Tape.interp "
		@load 'examples/composition_examples.tape'
		e := Editor()
		(e.can_view, e.can_list, e.can_create, e.can_update, e.can_delete, e.user_type)"

		assert_equal [true, true, true, true, true, 'editor'], out.values
	end

	def test_union_administrator_has_all_permissions
		out = Tape.interp "
		@load 'examples/composition_examples.tape'
		a := Administrator()
		(a.can_view, a.can_create, a.can_manage_users, a.user_type)"

		assert_equal [true, true, true, 'admin'], out.values
	end

	def test_removal_limited_editor_cannot_delete
		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp "
			@load 'examples/composition_examples.tape'
			l := Limited_Editor()
			(l.can_create, l.can_update, l.user_type)"
			assert_equal [true, true, 'limited_editor'], out.values
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			l := Limited_Editor()
			l.can_delete"
		end
	end

	def test_removal_read_only_admin_cannot_write
		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp "
			@load 'examples/composition_examples.tape'
			r := Read_Only_Admin()
			(r.can_manage_users, r.can_view, r.user_type)"
			assert_equal [true, true, 'read_only_admin'], out.values
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			r := Read_Only_Admin()
			r.can_create"
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			r := Read_Only_Admin()
			r.can_delete"
		end
	end

	def test_intersection_auditor_has_only_shared_permissions
		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp "
			@load 'examples/composition_examples.tape'
			a := Auditor()
			(a.can_view_logs, a.user_type)"
			assert_equal [true, 'auditor'], out.values
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			a := Auditor()
			a.can_manage_users"
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			a := Auditor()
			a.can_export_data"
		end
	end

	def test_symmetric_difference_specialist_has_unique_permissions
		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp "
			@load 'examples/composition_examples.tape'
			s := Specialist()
			(s.can_manage_users, s.can_configure_system, s.can_export_data, s.user_type)"
			assert_equal [true, true, true, 'specialist'], out.values
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			s := Specialist()
			s.can_view_logs"
		end
	end

	def test_vehicle_sedan_has_basic_features
		out = Tape.interp "
		@load 'examples/composition_examples.tape'
		s := Sedan()
		(s.has_engine, s.has_wheels, s.model)"

		assert_equal [true, true, 'sedan'], out.values
	end

	def test_vehicle_luxury_sedan_has_luxury_features
		out = Tape.interp "
		@load 'examples/composition_examples.tape'
		l := Luxury_Sedan()
		(l.has_engine, l.has_leather_seats, l.has_sunroof, l.model)"

		assert_equal [true, true, true, 'luxury_sedan'], out.values
	end

	def test_vehicle_electric_car_has_no_traditional_engine
		out = Tape.interp "
		@load 'examples/composition_examples.tape'
		e := Electric_Car()
		(e.has_wheels, e.has_battery, e.has_engine, e.model)"

		assert_equal [true, true, false, 'electric'], out.values
	end

	def test_vehicle_luxury_electric_combines_features
		out = Tape.interp "
		@load 'examples/composition_examples.tape'
		l := Luxury_Electric()
		(l.has_wheels, l.has_leather_seats, l.has_battery, l.has_engine, l.model)"

		assert_equal [true, true, true, false, 'luxury_electric'], out.values
	end

	def test_api_public_user_response_has_only_shared_members
		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp "
			@load 'examples/composition_examples.tape'
			p := Public_User_Response()
			(p.status, p.user_id, p.username, p.response_type)"
			assert_equal [200, 0, '', 'public'], out.values
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			p := Public_User_Response()
			p.email"
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			p := Public_User_Response()
			p.avatar_url"
		end
	end

	def test_api_private_user_response_has_all_members
		out = Tape.interp "
		@load 'examples/composition_examples.tape'
		p := Private_User_Response()
		(p.status, p.user_id, p.username, p.email, p.response_type)"

		assert_equal [200, 0, '', '', 'private'], out.values
	end

	def test_api_limited_user_response_removes_private_members
		refute_raises Tape::Undeclared_Identifier do
			out = Tape.interp "
			@load 'examples/composition_examples.tape'
			l := Limited_User_Response()
			(l.user_id, l.username, l.response_type)"
			assert_equal [0, '', 'limited'], out.values
		end

		assert_raises Tape::Undeclared_Identifier do
			Tape.interp "
			@load 'examples/composition_examples.tape'
			l := Limited_User_Response()
			l.email"
		end
	end
end
