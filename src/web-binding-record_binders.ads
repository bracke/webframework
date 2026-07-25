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
