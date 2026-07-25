with Ada.Strings.Bounded;
with Web.Binding.Errors;

--  Discriminated-union binding support.
--
--  The tagged strategy (preferred): a discriminator field selects one
--  alternative by an explicit wire mapping. The caller decodes the
--  discriminator, resolves it here, binds ONLY the selected alternative's
--  fields, and constructs the Ada discriminated value once, with the known
--  discriminant -- never mutating a mis-discriminated record (invariant BIND-013
--  in spirit; §16 "no invalid record mutation"). A missing discriminator, an
--  unknown wire, and a field belonging to another alternative are distinct
--  errors.
--
--  The structural strategy (optional, declared): several alternatives are tried
--  and exactly one must match; Resolve_Structural turns the per-alternative
--  match flags into Exactly_One / Ambiguous / No_Match (BIND-015).
generic
   type Alternative is (<>);
package Web.Binding.Union_Binders is

   Max_Wire : constant := 64;
   Max_Alternatives : constant := 64;

   package Wire_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Wire);

   type Selector is private;

   --  An empty discriminator mapping.
   --  @return The selector.
   function Empty_Selector return Selector;

   --  A selector with one more (wire -> alternative) mapping.
   --  @param S The selector to extend.
   --  @param Wire The discriminator wire value.
   --  @param Alt The alternative it selects.
   --  @return The extended selector.
   function Map
     (S : Selector; Wire : String; Alt : Alternative) return Selector;

   type Selection (Found : Boolean := False) is record
      case Found is
         when True =>
            Alt : Alternative;
         when False =>
            null;
      end case;
   end record;

   --  Resolve a discriminator wire value to an alternative.
   --  @param S The selector.
   --  @param Wire The wire value.
   --  @return The selection (Found False if unmapped).
   function Resolve (S : Selector; Wire : String) return Selection;

   --  The error id for an absent discriminator (union.missing_discriminator).
   --  @return The error id.
   function Missing_Error return Web.Binding.Errors.Error_Id;

   --  The error id for an unmapped discriminator (union.invalid_discriminator).
   --  @return The error id.
   function Invalid_Error return Web.Binding.Errors.Error_Id;

   type Match_Array is array (Alternative) of Boolean;

   type Structural_Outcome is (Exactly_One, Ambiguous, No_Match);

   --  Decide a structural union from the per-alternative match flags.
   --  @param Matches Which alternatives matched.
   --  @param Chosen The single match, when Exactly_One.
   --  @return Exactly_One, Ambiguous or No_Match.
   function Resolve_Structural
     (Matches : Match_Array; Chosen : out Alternative) return Structural_Outcome;

   --  The error id for an ambiguous structural match (union.ambiguous_alternative).
   --  @return The error id.
   function Ambiguous_Error return Web.Binding.Errors.Error_Id;

   --  The error id for no structural match (union.no_matching_alternative).
   --  @return The error id.
   function No_Match_Error return Web.Binding.Errors.Error_Id;

private

   type Entry_Rec is record
      Wire : Wire_Strings.Bounded_String;
      Alt  : Alternative := Alternative'First;
   end record;

   type Entry_Array is array (1 .. Max_Alternatives) of Entry_Rec;

   type Selector is record
      Count   : Natural := 0;
      Entries : Entry_Array;
   end record;

end Web.Binding.Union_Binders;
