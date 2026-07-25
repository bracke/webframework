with Web.Binding.Paths;
with Web.Binding.Policies;
with Web.Binding.Sources;
with Web.Binding.Errors;
with Web.Binding.Results;

--  Builder-based record binding.
--
--  A Builder assembles a target record without reflection and without unchecked
--  layout (BIND-013). It holds a working copy (seeded with defaults), an error
--  collection and an aggregation mode. Each field is bound through the nested
--  generic Bind_Scalar, which resolves the field's source occurrences (phase 2),
--  decodes the chosen value (phase 1), and assigns it through a caller-supplied
--  setter -- so a missing/duplicate/malformed/undecodable field becomes a
--  structured error at its exact path rather than a bad assignment.
--
--  Finish returns the assembled record only when no error was recorded; a failed
--  bind never yields a partial value (BIND-002). Fields are bound in call order,
--  which fixes the error order (BIND-004). A record may draw fields from several
--  sources: each Bind_Scalar takes its own occurrences, so mixed-source records
--  need no implicit merging.
generic
   type Target is private;
package Web.Binding.Record_Binders is

   package Results is new Web.Binding.Results (Target);

   type Builder is limited private;

   --  Begin binding into a working record seeded from Initial (its field
   --  defaults). Optional fields left unbound keep their seeded value.
   --  @param Initial The seed record supplying field defaults.
   --  @param Mode Fail-fast or field aggregation.
   --  @return A fresh builder.
   function Start
     (Initial : Target;
      Mode    : Web.Binding.Policies.Aggregation_Mode :=
        Web.Binding.Policies.Aggregate_Fields) return Builder;

   --  Bind one scalar field from its source occurrences.
   --
   --  Field_Type is the field's Ada type, Decode its scalar decoder, and Setter
   --  the explicit assignment into the target. A missing Required field is an
   --  error; a missing Optional/Optional_With_Default field keeps the seed. A
   --  malformed present value is an error, never replaced by the default.
   generic
      type Field_Type is private;
      with package Field_Results is new Web.Binding.Results (Field_Type);
      with function Decode
        (Text   : String;
         Path   : Web.Binding.Paths.Field_Path;
         Source : Source_Kind) return Field_Results.Result;
      with procedure Setter (Rec : in out Target; Value : Field_Type);
   procedure Bind_Scalar
     (B          : in out Builder;
      Occ        : Web.Binding.Sources.Occurrences;
      Path       : Web.Binding.Paths.Field_Path;
      Source     : Source_Kind;
      Presence   : Web.Binding.Policies.Presence_Policy :=
        Web.Binding.Policies.Required;
      Duplicates : Web.Binding.Policies.Duplicate_Policy :=
        Web.Binding.Policies.Reject;
      On_Empty   : Web.Binding.Policies.Empty_Policy :=
        Web.Binding.Policies.Reject_Empty);

   --  Bind a collection field from repeated occurrences.
   --
   --  Each occurrence is decoded independently and appended through Append, in
   --  source order, with an exact indexed path (Base_Path[0], Base_Path[1], ...).
   --  A malformed or undecodable element is a structured error at its index and,
   --  under Aggregate_Fields, does not stop the others. The item count is bounded:
   --  more than Max_Items is decode.too_many_items (and never appended); fewer
   --  than Min_Items is decode.invalid_list.
   generic
      type Element is private;
      with package Element_Results is new Web.Binding.Results (Element);
      with function Decode
        (Text   : String;
         Path   : Web.Binding.Paths.Field_Path;
         Source : Source_Kind) return Element_Results.Result;
      with procedure Append (Rec : in out Target; Value : Element);
   procedure Bind_Collection
     (B         : in out Builder;
      Occ       : Web.Binding.Sources.Occurrences;
      Base_Path : Web.Binding.Paths.Field_Path;
      Source    : Source_Kind;
      Min_Items : Natural := 0;
      Max_Items : Natural := 1_024);

   --  Bind a nested record by merging a sub-record bind into this builder.
   --
   --  Sub_Bind performs the nested binding (its own builder over the mapped
   --  keys, using nested paths) and returns a value-or-errors result. On success
   --  the value is assigned through Setter; on failure the sub-errors -- already
   --  carrying their nested paths -- are merged here. When the nested object is
   --  absent and Optional, it is skipped (the seeded default/None is kept); when
   --  present, Sub_Bind runs and its missing fields surface as errors.
   generic
      type Sub_Type is private;
      with package Sub_Results is new Web.Binding.Results (Sub_Type);
      with function Sub_Bind return Sub_Results.Result;
      with procedure Setter (Rec : in out Target; Value : Sub_Type);
   procedure Bind_Nested
     (B        : in out Builder;
      Present  : Boolean;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Optional : Boolean := False);

   --  Record decode.nesting_too_deep when Path is deeper than Max_Depth.
   --  @param B The builder.
   --  @param Path The nested path to check.
   --  @param Source The source kind.
   --  @param Max_Depth The maximum permitted path depth.
   procedure Guard_Depth
     (B         : in out Builder;
      Path      : Web.Binding.Paths.Field_Path;
      Source    : Source_Kind;
      Max_Depth : Depth_Count);

   --  Record an unknown source field per the unknown-field policy.
   --  @param B The builder.
   --  @param Path The unknown field's path.
   --  @param Source Its source kind.
   --  @param Policy Ignore, Reject or Collect.
   procedure Note_Unknown
     (B      : in out Builder;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind;
      Policy : Web.Binding.Policies.Unknown_Field_Policy);

   --  Record an arbitrary error (e.g. a source-precedence conflict).
   --  @param B The builder.
   --  @param Error The error to record.
   procedure Add_Error
     (B : in out Builder; Error : Web.Binding.Errors.Decoding_Error);

   --  Whether any error has been recorded.
   --  @param B The builder.
   --  @return True if an error was recorded.
   function Has_Errors (B : Builder) return Boolean;

   --  Finalize: the assembled record on success, else the recorded errors.
   --  @param B The builder.
   --  @return The bind result.
   function Finish (B : Builder) return Results.Result;

private

   type Builder is limited record
      Working : Target;
      Errors  : Web.Binding.Errors.Error_Collection;
      Mode    : Web.Binding.Policies.Aggregation_Mode :=
        Web.Binding.Policies.Aggregate_Fields;
      Sealed  : Boolean := False;
   end record;

end Web.Binding.Record_Binders;
