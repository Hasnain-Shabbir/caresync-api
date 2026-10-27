require "test_helper"

# Cycles are allowed (organization -> patients -> organization), but never through an unbounded list. A list inside a
# cycle must be a page (`XPage.items`, reached through a field that takes `perPage`), so the cost grows with the page
# size at every level and the complexity limit makes a deep query unaffordable. A bare list in a cycle would let a client
# nest it for free. Use a paginated_field instead (see Types::BaseObject.paginated_field).
class SchemaShapeTest < ActiveSupport::TestCase
  PAGE_SUFFIX = "Page".freeze

  # type name => [[field path, target type name, bare_list], ...]
  # bare_list is true for a list field that is not the inner list of a page type.
  def edges
    CaresyncApiSchema.types.values.each_with_object({}) do |type, graph|
      next unless type.kind.object? && !type.graphql_name.start_with?("__")

      graph[type.graphql_name] = type.fields.values.filter_map do |field|
        target = field.type.unwrap
        bare = field.type.list? && !type.graphql_name.end_with?(PAGE_SUFFIX)
        [ field.path, target.graphql_name, bare ] if target.kind.object?
      end
    end
  end

  # Returns the field path from `start` back to `start` that contains a bare list, or nil.
  def bare_list_cycle_from(start, graph)
    stack = [ [ start, [], false ] ]
    seen = Set.new
    until stack.empty?
      type, path, through_bare = stack.pop
      graph.fetch(type, []).each do |field_path, target, bare|
        next_path = path + [ field_path ]
        bare_so_far = through_bare || bare
        return next_path if target == start && bare_so_far

        key = [ target, bare_so_far ]
        next if seen.include?(key)

        seen << key
        stack << [ target, next_path, bare_so_far ]
      end
    end
    nil
  end

  test "no cycle in the schema goes through an unpaginated list" do
    graph = edges
    cycles = graph.keys.filter_map { |type| bare_list_cycle_from(type, graph)&.join(" -> ") }

    assert_empty cycles, "Unpaginated list in a cycle. Use paginated_field, or a count:\n#{cycles.join("\n")}"
  end

  test "the detector rejects a bare list in a cycle" do
    graph = { "Org" => [ [ "Org.patients", "Patient", true ] ], "Patient" => [ [ "Patient.organization", "Org", false ] ] }

    assert_equal [ "Org.patients", "Patient.organization" ], bare_list_cycle_from("Org", graph)
  end

  test "the detector accepts a cycle that goes through a page" do
    graph = {
      "Org" => [ [ "Org.patients", "PatientPage", false ] ],
      "PatientPage" => [ [ "PatientPage.patients", "Patient", false ] ],
      "Patient" => [ [ "Patient.organization", "Org", false ] ]
    }

    assert_nil bare_list_cycle_from("Org", graph)
  end

  test "every paginated field takes perPage and has a page type result" do
    page_fields = CaresyncApiSchema.types.values
      .select { |t| t.kind.object? && !t.graphql_name.start_with?("__") }
      .flat_map { |t| t.fields.values }
      .select { |f| f.type.unwrap.graphql_name.end_with?(PAGE_SUFFIX) }

    assert_not_empty page_fields
    page_fields.each do |f|
      assert_includes f.arguments.keys, "perPage", "#{f.path} returns a page but has no perPage argument"
      assert f.complexity.is_a?(Proc), "#{f.path} must carry the page cost (PAGE_COMPLEXITY)"
    end
  end
end
