--  Explicit binding policies.
--
--  Every ambiguous choice a binder could make is a named, explicit policy, never
--  a silent default buried in a parser (invariants BIND-007). Duplicates are
--  rejected unless a resolution is explicitly declared; defaults never replace a
--  malformed supplied value; missing, empty and JSON null are distinct states.
package Web.Binding.Policies is

   pragma Pure;

   --  How to resolve a scalar field supplied more than once. Reject is the
   --  default for scalars; Use_First and Use_Last must be declared explicitly.
   --  Require_Identical accepts repeats only when every occurrence decodes
   --  equal. Collect_All feeds a collection descriptor.
   type Duplicate_Policy is
     (Reject,
      Use_First,
      Use_Last,
      Collect_All,
      Require_Identical);

   --  How to treat a source field with no matching descriptor.
   type Unknown_Field_Policy is
     (Ignore,
      Reject,
      Collect);

   --  Whether a field must be present, and how a default participates.
   type Presence_Policy is
     (Required,
      Optional,
      Optional_With_Default);

   --  How to treat a present-but-empty value. Distinct from missing and from
   --  JSON null.
   type Empty_Policy is
     (Allow_And_Decode,
      Reject_Empty,
      Treat_As_Missing,
      Map_To_None,
      Map_To_Empty_Collection);

   --  How to treat an explicit JSON null. Distinct from missing and from empty.
   type Null_Policy is
     (Reject_Null,
      Null_To_None,
      Null_To_Default,
      Custom_Null);

   --  Whether to stop at the first error or accumulate field errors.
   --  Aggregate_Fields is the normal forms-oriented mode.
   type Aggregation_Mode is
     (Fail_Fast,
      Aggregate_Fields);

   --  How sensitive a value is. Controls raw-value retention, diagnostic
   --  excerpts, trace data, form rerender values and test rendering.
   type Sensitivity is
     (Public_Value,
      Private_Value,
      Secret_Value);

   --  Defaults, stated once so descriptors can rely on them.
   Default_Duplicate_Policy     : constant Duplicate_Policy := Reject;
   Default_Unknown_Field_Policy : constant Unknown_Field_Policy := Reject;
   Default_Empty_Policy         : constant Empty_Policy := Reject_Empty;
   Default_Null_Policy          : constant Null_Policy := Reject_Null;
   Default_Aggregation_Mode     : constant Aggregation_Mode := Aggregate_Fields;
   Default_Sensitivity          : constant Sensitivity := Public_Value;

end Web.Binding.Policies;
